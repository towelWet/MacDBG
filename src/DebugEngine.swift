import Foundation
import Combine

@MainActor
class DebugEngine: ObservableObject {
    @Published var executablePath: String?
    @Published var consoleLog: [ConsoleEntry] = []
    @Published var disassembly: [DisassemblyLine] = []
    @Published var registers: [Register] = []
    @Published var isDebugging = false
    @Published var isRunning = false

    private var tempScriptURL: URL?

    init() {
        log("DebugEngine initialized. Ready to load a binary.", type: .info)
    }

    func loadAndAnalyzeBinary(path: String) async {
        cleanup()
        self.executablePath = path
        log("Loading binary: \(path)", type: .command)

        // In a real implementation, we would run `otool` or `nm` here
        // to get initial disassembly and symbols.
        // For this example, we'll just log it.
        log("Static analysis would be performed here.", type: .info)

        // For demonstration, let's populate with some dummy data
        disassembly = [
            DisassemblyLine(address: 0x100000, bytes: "55", instruction: "push", operands: "rbp"),
            DisassemblyLine(address: 0x100001, bytes: "48 89 e5", instruction: "mov", operands: "rbp, rsp"),
            DisassemblyLine(address: 0x100004, bytes: "48 83 ec 10", instruction: "sub", operands: "rsp, 0x10")
        ]
        registers = [
            Register(name: "RAX", value: "0x0"),
            Register(name: "RBX", value: "0x0"),
            Register(name: "RCX", value: "0x0"),
            Register(name: "RDX", value: "0x0"),
        ]
        log("Binary loaded and ready for debugging.", type: .success)
    }

    func startDebug() {
        guard let executablePath else {
            log("No executable loaded.", type: .error)
            return
        }
        log("Starting debug session for: \(executablePath)", type: .command)
        isDebugging = true
        runLLDBCommand("process launch --stop-at-entry")
    }

    func stepInto() {
        guard isDebugging, !isRunning else { return }
        log("Stepping into...", type: .command)
        runLLDBCommand("thread step-in")
    }

    func stepOver() {
        guard isDebugging, !isRunning else { return }
        log("Stepping over...", type: .command)
        runLLDBCommand("thread step-over")
    }

    func continueExecution() {
        guard isDebugging, !isRunning else { return }
        log("Continuing execution...", type: .command)
        runLLDBCommand("continue")
    }

    private func runLLDBCommand(_ command: String) {
        guard let executablePath else { return }

        Task(priority: .userInitiated) {
            let script = """
            file \(executablePath)
            \(command)
            register read
            disassemble -c 20
            quit
            """
            
            do {
                let output = try await executeLLDB(script: script)
                parseLLDBOutput(output)
            } catch {
                log("LLDB execution failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func executeLLDB(script: String) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("lldb-script-\(UUID().uuidString).txt")
        
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        self.tempScriptURL = scriptURL
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")
        task.arguments = ["-s", scriptURL.path]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        try task.run()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        task.waitUntilExit()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        if !errorOutput.isEmpty {
            log(errorOutput, type: .error)
        }
        
        return output
    }

    private func parseLLDBOutput(_ output: String) {
        log("--- LLDB Output ---", type: .info)
        log(output, type: .info)
        log("--- End LLDB Output ---", type: .info)

        // This is where a sophisticated parser would be needed.
        // For now, we'll just log the output.
        // A real implementation would use regex or structured parsing
        // to update the disassembly, registers, etc.
        
        // Dummy update for demonstration
        registers = registers.map {
            Register(name: $0.name, value: String(format: "0x%llX", UInt64.random(in: 0...UInt64.max)))
        }
    }

    func log(_ text: String, type: ConsoleEntry.EntryType) {
        let entry = ConsoleEntry(timestamp: Date(), text: text, type: type)
        consoleLog.append(entry)
    }

    func cleanup() {
        if let tempScriptURL {
            try? FileManager.default.removeItem(at: tempScriptURL)
            self.tempScriptURL = nil
        }
        executablePath = nil
        isDebugging = false
        isRunning = false
        consoleLog.removeAll()
        disassembly.removeAll()
        registers.removeAll()
        log("Cleaned up previous session.", type: .info)
    }
}
