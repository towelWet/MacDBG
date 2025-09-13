    import Foundation
import Combine
import MacDBG

@main
struct MacDBGCLI {
    
    // We need to keep a reference to the cancellable to receive log updates
    private static var logCancellable: AnyCancellable?

    @MainActor
    static func main() async {
        let debugger = DebuggerController()

        // Subscribe to the debugger's log publisher to print messages as they happen
        logCancellable = debugger.$logs.sink { logs in
            // This sink can be used for real-time log display if needed,
            // but for a simple request-response CLI, we'll poll with the 'log' command.
        }

        print("Welcome to MacDBG CLI. Type 'help' for a list of commands.")

        // Main command loop
        while true {
            print("macdbg> ", terminator: "")
            guard let input = readLine(), !input.isEmpty else { continue }

            let parts = input.split(separator: " ").map(String.init)
            guard let command = parts.first else { continue }
            let args = Array(parts.dropFirst())

            switch command {
            case "help":
                printHelp()
            case "ps":
                await listProcesses(debugger: debugger)
            case "attach":
                await attach(to: args.first, debugger: debugger)
            case "detach":
                await detach(debugger: debugger)
            case "step", "s":
                await step(debugger: debugger)
            case "continue", "c":
                await continueExecution(debugger: debugger)
            case "dis", "disassemble":
                await disassemble(debugger: debugger)
            case "reg", "registers":
                await registers(debugger: debugger)
            case "mem", "memory":
                await readMemory(args: args, debugger: debugger)
            case "log":
                await showLog(debugger: debugger)
            case "status":
                await showStatus(debugger: debugger)
            case "quit", "exit":
                print("Detaching if necessary and exiting.")
                await detach(debugger: debugger)
                return
            default:
                print("Unknown command: '\(command)'. Type 'help' for a list of commands.")
            }
        }
    }

    private static func printHelp() {
        print("""
        Available commands:
          ps                  - List running processes.
          attach <pid>        - Attach to a process by its ID.
          detach              - Detach from the current process.
          step, s             - Step a single instruction.
          continue, c         - Continue execution.
          dis, disassemble    - Show disassembly at the current program counter.
          reg, registers      - Show current register values.
          mem <addr> [bytes]  - Read memory at a hex address (e.g., mem 0x10000 256). Defaults to 64 bytes.
          log                 - Show the debug log.
          status              - Show the current debugger status.
          quit, exit          - Exit the debugger.
        """)
    }

    private static func listProcesses(debugger: DebuggerController) async {
        await debugger.refreshProcessList()
        // Give a moment for the async process list to populate
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("PID\t\tProcess Name")
        print("---------------------------------")
        for p in await debugger.processes {
            print("\(p.pid)\t\t\(p.name)")
        }
    }

    private static func attach(to pidString: String?, debugger: DebuggerController) async {
        guard let pidString = pidString, let pid = pid_t(pidString) else {
            print("Usage: attach <pid>")
            return
        }
        await debugger.attach(to: pid)
        print("Status: \(await debugger.status)")
    }

    private static func detach(debugger: DebuggerController) async {
        if await debugger.isAttached {
            await debugger.detach()
            print("Status: \(await debugger.status)")
        } else {
            print("Not attached to any process.")
        }
    }

    private static func step(debugger: DebuggerController) async {
        guard await debugger.isAttached else { print("Not attached."); return }
        print("Stepping...")
        await debugger.stepInto()
        print("Step complete. Status: \(await debugger.status)")
        await disassemble(debugger: debugger)
    }

    private static func continueExecution(debugger: DebuggerController) async {
        guard await debugger.isAttached else { print("Not attached."); return }
        await debugger.continueExecution()
        print("Continuing... Status: \(await debugger.status)")
    }

    private static func disassemble(debugger: DebuggerController) async {
        guard await debugger.isAttached else { print("Not attached."); return }
        await debugger.refreshDisassembly()
        let disassembly = await debugger.disassembly
        if disassembly.isEmpty {
            print("No disassembly available. Process may be running or in an invalid state.")
        } else {
            for line in disassembly {
                print("\(line.formattedAddress)\t\(line.instruction)\t\(line.operands)")
            }
        }
    }

    private static func registers(debugger: DebuggerController) async {
        guard await debugger.isAttached else { print("Not attached."); return }
        await debugger.refreshRegisters()
        let registers = await debugger.registers
        if registers.isEmpty {
            print("No registers available.")
        } else {
            for (key, value) in registers.sorted(by: { $0.key < $1.key }) {
                print("\(key.padding(toLength: 8, withPad: " ", startingAt: 0)): \(value)")
            }
        }
    }

    private static func readMemory(args: [String], debugger: DebuggerController) async {
        guard await debugger.isAttached else { print("Not attached."); return }
        guard let addrStr = args.first else {
            print("Usage: mem <hex_address> [bytes_to_read]")
            return
        }
        let bytes = (args.count > 1 ? Int(args[1]) : 64) ?? 64
        
        // Parse hex address
        let scanner = Scanner(string: addrStr.hasPrefix("0x") ? String(addrStr.dropFirst(2)) : addrStr)
        var address: UInt64 = 0
        guard scanner.scanHexInt64(&address) else {
            print("Invalid hex address: \(addrStr)")
            return
        }
        
        await debugger.readMemory(address: address, bytes: bytes)
        let memory = await debugger.memory
        if memory.isEmpty {
            print("Failed to read memory or address is invalid.")
        } else {
            for (addr, data) in memory.sorted(by: { $0.key < $1.key }) {
                let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                let asciiString = data.map { byte in
                    if (0x20...0x7e).contains(byte) {
                        return String(UnicodeScalar(byte))
                    } else {
                        return "."
                    }
                }.joined()
                print(String(format: "0x%016llx  %-48s %s", addr, hexString, asciiString))
            }
        }
    }

    private static func showLog(debugger: DebuggerController) async {
        print("--- DEBUG LOG ---")
        for log in await debugger.logs {
            print(log)
        }
        print("--- END LOG ---")
    }
    
    private static func showStatus(debugger: DebuggerController) async {
        print("Status: \(await debugger.status)")
    }
}
  
