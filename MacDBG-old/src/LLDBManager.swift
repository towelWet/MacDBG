import Foundation

protocol LLDBManagerDelegate: AnyObject {
    func lldbManagerDidAttach() async
    func lldbManagerDidDetach() async
    func lldbManagerDidStop(event: LLDBStoppedEvent) async
    func lldbManagerDidReceiveRegisters(response: LLDBRegistersResponse) async
    func lldbManagerDidReceiveDisassembly(response: LLDBDisassemblyResponse) async
    func lldbManagerDidReceiveMemory(response: LLDBMemoryResponse) async
    func lldbManagerDidReceiveError(error: LLDBErrorEvent) async
    func lldbManagerDidReceiveBreakpointResponse(response: [String: Any]) async
    func lldbManagerDidReceiveWriteByteResponse(success: Bool, error: String?) async
    func lldbManagerDidReceiveStringReferences(response: LLDBStringReferencesResponse) async
}

/// Manages the `lldb_server.py` script, providing a high-level interface for debugging.
/// This class handles launching the Python script, sending JSON commands, and receiving responses.
class LLDBManager {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let responseQueue = DispatchQueue(label: "com.windsurf.macdbg.lldbmanager.response")
    private var responseBuffer = Data()
    
    // Track last sent command for response handling
    private var lastSentCommand: String?
    
    // PERFORMANCE: Request batching and caching
    private let commandQueue = DispatchQueue(label: "lldb.commands", qos: .userInitiated)
    private var pendingCommands: [(String, [String: Any])] = []
    private var batchTimer: Timer?
    private let batchDelay: TimeInterval = 0.01 // 10ms batching for ultra-fast response

    weak var delegate: LLDBManagerDelegate?
    var onLog: ((String) -> Void)?

    init() {}

    func start() throws {
        guard process == nil else { return }

        guard let scriptPath = Bundle.main.path(forResource: "lldb_server", ofType: "py") else {
            throw NSError(domain: "LLDBManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "lldb_server.py not found in app bundle."])
        }
        let task = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        // Use Xcode's Python so the 'lldb' module is available
        task.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/python3")

        // Pass '0' and '1' so lldb_server.py runs in binary mode (length-prefixed),
        // matching our Swift read/write protocol.
        task.arguments = [scriptPath, "0", "1"]

        // Ensure LLDB's Python modules are on PYTHONPATH. Keep it simple to avoid compile issues.
        // If you have multiple Xcode installs, adjust this path as needed.
        let lldbPy = "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Resources/Python"
        task.environment = ["PYTHONPATH": lldbPy]

        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        try task.run()
        self.process = task
        onLog?("[LLDBManager] lldb_server.py started.")

        // Start a background thread to read from the script's stdout
        DispatchQueue.global(qos: .userInitiated).async {
            self.readScriptOutput()
        }

        // Start a background thread to read server stderr as UTF-8 lines for diagnostics
        DispatchQueue.global(qos: .utility).async {
            self.readServerStderr()
        }
    }

    private func readExact(from handle: FileHandle, count: Int) throws -> Data? {
        var buffer = Data()
        var remaining = count
        while remaining > 0 {
            if let chunk = try handle.read(upToCount: remaining) {
                if chunk.isEmpty {
                    return nil // EOF
                }
                buffer.append(chunk)
                remaining -= chunk.count
            } else {
                return nil
            }
        }
        return buffer
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        onLog?("[LLDBManager] lldb_server.py stopped.")
    }

    private func readScriptOutput() {
        guard let fileHandle = stdoutPipe?.fileHandleForReading else { return }

        while true {
            do {
                // Read the 4-byte length prefix (little-endian to match Python's struct.pack('i', ...))
                guard let lengthData = try readExact(from: fileHandle, count: 4) else {
                    onLog?("[LLDBManager] Pipe closed or failed to read length.")
                    break
                }

                let length = UInt32(littleEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) })

                // Read the JSON payload exactly
                guard let messageData = try readExact(from: fileHandle, count: Int(length)) else {
                    onLog?("[LLDBManager] Failed to read full message payload.")
                    continue
                }

                // Process the message on the main response queue
                responseQueue.async {
                    self.processMessage(messageData)
                }
            } catch {
                onLog?("[LLDBManager] Error reading from pipe: \(error)")
                break
            }
        }
    }

    private func processMessage(_ data: Data) {
        if let jsonString = String(data: data, encoding: .utf8) {
            onLog?("[Swift-RECV] \(jsonString)")
        }
        let decoder = JSONDecoder()
        do {
            // 1. Decode the message into a generic dictionary to inspect its type.
            guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let typeString = jsonObject["type"] as? String,
                  let messageType = LLDBMessage.MessageType(rawValue: typeString) else {
                // Fallback for legacy responses like {"status": "ok"|"error"|"event", ...}
                if let legacy = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let status = legacy["status"] as? String {
                    switch status.lowercased() {
                    case "ok":
                        // Check if this is an attach response by looking at the command that was sent
                        if let command = lastSentCommand, command == "attachToProcess" {
                            onLog?("[Server] OK (attached)")
                            Task { @MainActor in
                                await delegate?.lldbManagerDidAttach()
                            }
                        } else if legacy["sectionName"] != nil || (legacy["fileAddr"] != nil && legacy["loadAddr"] != nil) {
                            onLog?("[Server] OK (attached)")
                            Task { @MainActor in
                                await delegate?.lldbManagerDidAttach()
                            }
                        } else if legacy["bkpt_id"] != nil {
                            // This is a breakpoint response
                            onLog?("[Server] OK (breakpoint)")
                            Task { @MainActor in
                                await delegate?.lldbManagerDidReceiveBreakpointResponse(response: legacy)
                            }
                        } else {
                            onLog?("[Server] OK")
                        }
                        return
                    case "error":
                        let msg = (legacy["message"] as? String) ?? "unknown error"
                        onLog?("[Server-ERROR] \(msg)")
                        let errorEvent = LLDBErrorEvent(message: msg)
                        Task { @MainActor in
                            await delegate?.lldbManagerDidReceiveError(error: errorEvent)
                        }
                        return
                    case "event":
                        // For now, just log and ignore
                        if let t = legacy["type"] as? String {
                            onLog?("[Server-Event] \(t)")
                        } else {
                            onLog?("[Server-Event]")
                        }
                        return
                    default:
                        break
                    }
                }
                onLog?("[LLDBManager] Failed to decode message type from JSON.")
                return
            }

            // 2. Extract the payload and re-serialize it to Data.
            guard let payloadObject = jsonObject["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payloadObject, options: []) else {
                // Handle messages with no payload, like 'attached' and 'detached'.
                switch messageType {
                case .attached:
                    Task { @MainActor in
                        await delegate?.lldbManagerDidAttach()
                    }
                case .detached:
                    Task { @MainActor in
                        await delegate?.lldbManagerDidDetach()
                    }
                default:
                    onLog?("[LLDBManager] Message type \(messageType) is missing a payload.")
                }
                return
            }

            // 3. Decode the specific payload type.
            switch messageType {
            case .log:
                if let logPayload = try? decoder.decode([String: String].self, from: payloadData),
                   let message = logPayload["message"] {
                    onLog?("[Python] \(message)")
                }
            case .stopped:
                let event = try decoder.decode(LLDBStoppedEvent.self, from: payloadData)
                Task { @MainActor in
                    await delegate?.lldbManagerDidStop(event: event)
                }
            case .registers:
                let response = try decoder.decode(LLDBRegistersResponse.self, from: payloadData)
                Task { @MainActor in
                    await delegate?.lldbManagerDidReceiveRegisters(response: response)
                }
            case .disassembly:
                let response = try decoder.decode(LLDBDisassemblyResponse.self, from: payloadData)
                
                // Debug: Log what disassembly lines we received from JSON
                print("🔍 LLDBManager decoded \(response.lines.count) disassembly lines")
                let conditionalJumps = response.lines.filter { line in
                    let inst = line.instruction.lowercased()
                    return inst.hasPrefix("j") && inst != "jmp" && inst != "jmpq"
                }
                if !conditionalJumps.isEmpty {
                    print("🚨 LLDBManager found conditional jumps in JSON:")
                    for jump in conditionalJumps.prefix(3) {
                        print("   - \(jump.formattedAddress): '\(jump.instruction)' \(jump.operands) (bytes: \(jump.bytes))")
                    }
                }
                
                Task { @MainActor in
                    await delegate?.lldbManagerDidReceiveDisassembly(response: response)
                }
            case .memory:
                let response = try decoder.decode(LLDBMemoryResponse.self, from: payloadData)
                Task { @MainActor in
                    await delegate?.lldbManagerDidReceiveMemory(response: response)
                }
            case .writeByte:
                let response = try decoder.decode(LLDBWriteByteResponse.self, from: payloadData)
                Task { @MainActor in
                    await delegate?.lldbManagerDidReceiveWriteByteResponse(success: response.success, error: response.error)
                }
            case .string_references:
                // Parse the string references response using AnyCodable
                do {
                    let rawResponse = try decoder.decode(AnyCodable.self, from: payloadData)
                    if let responseDict = rawResponse.value as? [String: Any],
                       let payload = responseDict["payload"] as? [String: Any],
                       let stringAddress = payload["string_address"] as? UInt64,
                       let referencesArray = payload["references"] as? [[String: Any]],
                       let count = payload["count"] as? Int {
                        
                        let references = referencesArray.compactMap { refDict -> StringReference? in
                            guard let address = refDict["address"] as? UInt64,
                                  let instruction = refDict["instruction"] as? String,
                                  let module = refDict["module"] as? String else {
                                return nil
                            }
                            return StringReference(address: address, instruction: instruction, module: module)
                        }
                        
                        let payload = StringReferencesPayload(stringAddress: stringAddress, references: references, count: count)
                        let response = LLDBStringReferencesResponse(payload: payload)
                        
                        Task { @MainActor in
                            await delegate?.lldbManagerDidReceiveStringReferences(response: response)
                        }
                    }
                } catch {
                    print("Failed to parse string references response: \(error)")
                }
            case .error:
                let errorEvent = try decoder.decode(LLDBErrorEvent.self, from: payloadData)
                Task { @MainActor in
                    await delegate?.lldbManagerDidReceiveError(error: errorEvent)
                }
            case .attached, .detached: // Already handled
                break
            }
        } catch {
            onLog?("[LLDBManager] Error decoding JSON: \(error.localizedDescription)")
            if let jsonString = String(data: data, encoding: .utf8) {
                onLog?("[LLDBManager] Raw message: \(jsonString)")
            }
        }
    }

    func sendCommand(command: String, args: [String: Any] = [:]) {
        // Store the command for response handling
        lastSentCommand = command
        
        var fullCommand: [String: Any] = ["command": command]
        // Flatten args into top-level object to match lldb_server.py expectations
        for (k, v) in args { fullCommand[k] = v }

        do {
            let data = try JSONSerialization.data(withJSONObject: fullCommand, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                onLog?("[Swift-SEND] \(jsonString)")
                macdbgLog("📤 LLDB Command Sent: \(command) with args: \(args)", category: .lldb)
            }
            var length = UInt32(data.count).littleEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            
            stdinPipe?.fileHandleForWriting.write(lengthData)
            stdinPipe?.fileHandleForWriting.write(data)
        } catch {
            onLog?("[LLDBManager] Error sending command: \(error.localizedDescription)")
            macdbgLogCrash(error, context: "Error sending LLDB command: \(command)")
        }
    }

    // MARK: - High-Level Debugging Commands

    func attach(pid: pid_t, executablePath: String) {
        sendCommand(command: "attachToProcess", args: ["pid": pid, "executable": executablePath, "is64Bits": true])
    }

    func detach() {
        sendCommand(command: "detach")
    }

    func stepInstruction() {
        sendCommand(command: "stepInstruction")
    }
    
    func stepOver() {
        sendCommand(command: "stepOver")
    }
    
    func stepOut() {
        sendCommand(command: "stepOut")
    }

    func continueExecution() {
        sendCommand(command: "continueExecution")
    }

    func getRegisters() {
        sendCommand(command: "getRegisters")
    }

    func breakExecution() {
        sendCommand(command: "breakExecution")
    }

    func forceStopAndReport() {
        sendCommand(command: "forceStopAndReport")
    }

    func getDisassembly(from address: UInt64, count: Int) {
        sendCommand(command: "disassembly", args: ["address": address, "count": count])
    }

    func readMemory(from address: UInt64, count: Int) {
        sendCommand(command: "readMemory", args: ["address": address, "length": count])
    }
    
    func writeByte(at address: UInt64, value: UInt8) {
        sendCommand(command: "writeByte", args: ["address": address, "value": value])
    }
    
    func selectThreadID(_ tid: UInt64) {
        sendCommand(command: "selectThreadID", args: ["tid": tid])
    }
    
    private func readServerStderr() {
        guard let fileHandle = stderrPipe?.fileHandleForReading else { return }
        let newline = "\n".data(using: .utf8)!
        var buffer = Data()
        while true {
            do {
                let chunk = try fileHandle.read(upToCount: 512) ?? Data()
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let r = buffer.range(of: newline) {
                    let lineData = buffer.subdata(in: 0..<r.lowerBound)
                    buffer.removeSubrange(0..<r.upperBound)
                    if let s = String(data: lineData, encoding: .utf8), !s.isEmpty {
                        onLog?("[Python-ERR] \(s)")
                    }
                }
            } catch {
                onLog?("[LLDBManager] Error reading stderr: \(error)")
                break
            }
        }
    }
}
