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
        macdbgLog("🚀 LLDBManager.start() called", category: .lldb)
        
        guard process == nil else { 
            macdbgLog("⚠️ Process already running, skipping start", category: .lldb)
            return 
        }

        // Try to find lldb_server.py in multiple locations
        var scriptPath: String?
        
        macdbgLog("🔍 Looking for lldb_server.py...", category: .lldb)
        
        // First try app bundle (for GUI)
        if let bundlePath = Bundle.main.path(forResource: "lldb_server", ofType: "py") {
            scriptPath = bundlePath
            macdbgLog("✅ Found in app bundle: \(bundlePath)", category: .lldb)
        }
        // Then try Resources directory (for CLI)
        else if FileManager.default.fileExists(atPath: "Resources/lldb_server.py") {
            scriptPath = "Resources/lldb_server.py"
            macdbgLog("✅ Found in Resources directory: \(scriptPath!)", category: .lldb)
        }
        // Try absolute path to Resources
        else if FileManager.default.fileExists(atPath: "/Users/towelwet/Documents/[Towel Ware Dev]/Towel Mac Reverse/MacDBG/Resources/lldb_server.py") {
            scriptPath = "/Users/towelwet/Documents/[Towel Ware Dev]/Towel Mac Reverse/MacDBG/Resources/lldb_server.py"
            macdbgLog("✅ Found at absolute path: \(scriptPath!)", category: .lldb)
        }
        
        guard let validScriptPath = scriptPath else {
            macdbgLog("❌ lldb_server.py not found in any location!", category: .error)
            throw NSError(domain: "LLDBManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "lldb_server.py not found in app bundle or Resources directory."])
        }
        
        macdbgLog("🔧 Creating Process and pipes...", category: .lldb)
        let task = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        
        macdbgLog("✅ Pipes created successfully", category: .lldb)

        // Use Xcode's Python so the 'lldb' module is available
        let pythonPath = "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        task.executableURL = URL(fileURLWithPath: pythonPath)
        macdbgLog("🐍 Using Python at: \(pythonPath)", category: .lldb)

        // Pass '0' and '1' so lldb_server.py runs in binary mode (length-prefixed),
        // matching our Swift read/write protocol.
        task.arguments = [validScriptPath, "0", "1"]
        macdbgLog("📝 Task arguments: \(task.arguments!)", category: .lldb)

        // Ensure LLDB's Python modules are on PYTHONPATH. Keep it simple to avoid compile issues.
        // If you have multiple Xcode installs, adjust this path as needed.
        let lldbPy = "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Resources/Python"
        task.environment = ["PYTHONPATH": lldbPy]
        macdbgLog("🔧 PYTHONPATH set to: \(lldbPy)", category: .lldb)

        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        macdbgLog("🔗 Pipes connected to task", category: .lldb)

        macdbgLog("🚀 Starting Python process...", category: .lldb)
        try task.run()
        self.process = task
        macdbgLog("✅ Python process started successfully (PID: \(task.processIdentifier))", category: .lldb)
        onLog?("[LLDBManager] lldb_server.py started.")

        // Start a background thread to read from the script's stdout
        DispatchQueue.global(qos: .userInitiated).async {
            self.readScriptOutput()
        }

        // Start a background thread to read server stderr as UTF-8 lines for diagnostics
        DispatchQueue.global(qos: .utility).async {
            self.readServerStderr()
        }
        
        // Give the Python process time to fully initialize
        macdbgLog("⏳ Waiting for Python process to initialize...", category: .lldb)
        Thread.sleep(forTimeInterval: 2.0)
        
        // Verify the process is still running after initialization
        if let process = self.process, process.isRunning {
            macdbgLog("✅ Python process confirmed running after initialization (PID: \(process.processIdentifier))", category: .lldb)
        } else {
            macdbgLog("❌ Python process died during initialization!", category: .error)
            let error = NSError(domain: "LLDBManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Python process died during startup"])
            macdbgLogCrash(error, context: "Python process failed to initialize properly")
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
        macdbgLog("📤 sendCommand called: \(command)", category: .lldb)
        macdbgLog("   Args: \(args)", category: .lldb)
        
        // Check if LLDBManager is properly initialized
        macdbgLog("🔍 Checking LLDBManager state...", category: .lldb)
        macdbgLog("   Process: \(process != nil ? "✅ Initialized" : "❌ Nil")", category: .lldb)
        macdbgLog("   stdinPipe: \(stdinPipe != nil ? "✅ Initialized" : "❌ Nil")", category: .lldb)
        macdbgLog("   stdoutPipe: \(stdoutPipe != nil ? "✅ Initialized" : "❌ Nil")", category: .lldb)
        macdbgLog("   stderrPipe: \(stderrPipe != nil ? "✅ Initialized" : "❌ Nil")", category: .lldb)
        
        // Check if the Python process is still running
        if let process = process {
            if !process.isRunning {
                let terminationStatus = process.terminationStatus
                let terminationReason = process.terminationReason
                macdbgLog("❌ Python process is not running! Process terminated.", category: .error)
                macdbgLog("   Termination Status: \(terminationStatus)", category: .error)
                macdbgLog("   Termination Reason: \(terminationReason.rawValue)", category: .error)
                
                // Try to restart the Python process
                macdbgLog("🔄 Attempting to restart Python process...", category: .lldb)
                
                // Reset process reference to allow restart
                self.process = nil
                self.stdinPipe = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                
                do {
                    try start()
                    macdbgLog("✅ Python process restarted successfully", category: .lldb)
                } catch {
                    macdbgLog("❌ Failed to restart Python process: \(error)", category: .error)
                    let restartError = NSError(domain: "LLDBManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Python process terminated and restart failed"])
                    macdbgLogCrash(restartError, context: "Python process died before sending command and could not be restarted")
                    return
                }
            } else {
                macdbgLog("✅ Python process is running (PID: \(process.processIdentifier))", category: .lldb)
            }
        }
        
        guard let stdinPipe = stdinPipe else {
            macdbgLog("❌ CRASH PREVENTION: stdinPipe is nil! Cannot send command.", category: .error)
            let error = NSError(domain: "LLDBManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "stdinPipe is nil - LLDBManager not initialized"])
            macdbgLogCrash(error, context: "sendCommand called but LLDBManager not initialized")
            return
        }
        
        // Store the command for response handling
        lastSentCommand = command
        
        var fullCommand: [String: Any] = ["command": command]
        // Flatten args into top-level object to match lldb_server.py expectations
        for (k, v) in args { fullCommand[k] = v }

        do {
            let data = try JSONSerialization.data(withJSONObject: fullCommand, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                onLog?("[Swift-SEND] \(jsonString)")
                macdbgLog("📤 JSON Command: \(jsonString)", category: .lldb)
            }
            
            macdbgLog("📤 Data size: \(data.count) bytes", category: .lldb)
            
            var length = UInt32(data.count).littleEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            
            macdbgLog("📤 Writing to stdin pipe...", category: .lldb)
            
            // Check if the pipe is still valid before writing
            if stdinPipe.fileHandleForWriting.fileDescriptor == -1 {
                macdbgLog("❌ stdinPipe file descriptor is invalid (-1)", category: .error)
                let error = NSError(domain: "LLDBManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "stdinPipe file descriptor is invalid"])
                macdbgLogCrash(error, context: "stdinPipe invalid when trying to write")
                return
            }
            
            // Try to write with error handling
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: lengthData)
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                macdbgLog("✅ Command written to pipe successfully", category: .lldb)
            } catch {
                macdbgLog("❌ Failed to write to pipe: \(error.localizedDescription)", category: .error)
                macdbgLogCrash(error, context: "Failed to write to stdinPipe")
                return
            }
        } catch {
            macdbgLog("❌ Error sending command: \(error.localizedDescription)", category: .error)
            onLog?("[LLDBManager] Error sending command: \(error.localizedDescription)")
            macdbgLogCrash(error, context: "Error sending LLDB command: \(command)")
        }
    }

    // MARK: - High-Level Debugging Commands

    func attach(pid: pid_t, executablePath: String) {
        macdbgLog("🔗 LLDBManager.attach called", category: .lldb)
        macdbgLog("   PID: \(pid)", category: .lldb)
        macdbgLog("   Executable: \(executablePath)", category: .lldb)
        
        do {
            sendCommand(command: "attachToProcess", args: ["pid": pid, "executable": executablePath, "is64Bits": true])
            macdbgLog("✅ Attach command sent successfully", category: .lldb)
        } catch {
            macdbgLog("❌ Failed to send attach command: \(error)", category: .error)
        }
    }

    func detach() {
        sendCommand(command: "detach")
    }

    func stepInstruction() {
        sendCommand(command: "stepInstruction")
    }
    
    func stepInto() {
        sendCommand(command: "stepInto")
    }
    
    func stepOver() {
        sendCommand(command: "stepOver")
    }
    
    func stepOut() {
        sendCommand(command: "stepOut")
    }
    
    func stepUntilUserCode() {
        sendCommand(command: "stepUntilUserCode")
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
