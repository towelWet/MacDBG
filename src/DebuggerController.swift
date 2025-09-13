import Foundation
import SwiftUI
import Darwin

/// PERFORMANCE: DebuggerController with x64dbg-style optimizations
@MainActor
public class DebuggerController: ObservableObject, LLDBManagerDelegate {
    private let logger = LoggingSystem.shared
    @Published public var state = DebuggerState.idle {
        didSet {
            updateStatus(from: state)
        }
    }
    
    // MARK: - Published Properties
    @Published public var isAttached = false
    @Published public var currentPID: pid_t = 0
    @Published public var selectedPID: pid_t = 0
    @Published public var processes: [ProcessInfo] = []
    @Published public var programCounter: UInt64 = 0
    @Published public var registers: [String: UInt64] = [:]
    @Published public var disassembly: [DisassemblyLine] = []
    @Published public var memory: [UInt64: [UInt8]] = [:]
    @Published public var breakpoints: Set<UInt64> = []
    @Published public var logs: [String] = []
    @Published public var disassemblyUpdateTrigger: Int = 0
    @Published public var navigationTarget: UInt64? = nil
    @Published public var status: String = "Ready"
    
    // MARK: - String Analysis (Ghidra-style)
    @Published public var strings: [StringData] = []
    @Published public var stringReferences: [StringReference] = []
    @Published public var selectedStringAddress: UInt64? = nil
    
    // MARK: - Private State
    private var breakpointIDs: [UInt64: Int] = [:]
    private var pendingBreakpointAddress: UInt64?
    private var attachedProcessPath: String?
    
    // MARK: - x64dbg-style Performance Optimizations
    private var instructionBuffer: [DisassemblyLine] = []
    private var bufferBaseAddress: UInt64 = 0
    private var bufferSize: Int = 0
    private var maxBufferSize: Int = 2048
    
    private var disassemblyCache: [UInt64: DisassemblyLine] = [:]
    private var lastCachedRange: (start: UInt64, end: UInt64)?
    private var requestThrottle: Date = Date.distantPast
    
    private let instructionQueue = DispatchQueue(label: "instruction.processing", qos: .userInitiated)
    
    // MARK: - Memory Patching
    @Published public var memoryPatches: [UInt64: [UInt8]] = [:]
    private var originalBytes: [UInt64: [UInt8]] = [:]
    
    private let lldbManager = LLDBManager()
    
    public init() {
        refreshProcessList()
        addLog("MacDBG initialized")
        lldbManager.delegate = self
        lldbManager.onLog = { [weak self] message in
            DispatchQueue.main.async {
                self?.addLog(message)
            }
        }
        
        // Start the LLDB manager
        do {
            try lldbManager.start()
            addLog("✅ LLDB Manager started successfully")
        } catch {
            addLog("❌ Failed to start LLDB Manager: \(error.localizedDescription)")
            status = "LLDB Manager failed to start"
        }
    }
    
    // MARK: - Process Management
    public func refreshProcessList() {
        Task {
            let newProcesses = await getRunningProcesses()
            await MainActor.run {
                self.processes = newProcesses
                self.addLog("🔄 Process list refreshed: \(newProcesses.count) processes found")
            }
        }
    }
    
    private func getRunningProcesses() async -> [ProcessInfo] {
        logger.log("🔄 Getting real running processes from system", category: .system)
        
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid,ppid,comm"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        var processes: [ProcessInfo] = []
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let lines = output.components(separatedBy: .newlines)
            logger.log("📊 Found \(lines.count) process lines from ps command", category: .system)
            
            var processedCount = 0
            var skippedCount = 0
            
            for line in lines.dropFirst() { // Skip header
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                
                // Split by whitespace and filter out empty parts
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 3,
                      let pid = Int32(parts[0]),
                      let ppid = Int32(parts[1]) else { 
                    skippedCount += 1
                    if skippedCount <= 5 { // Log first 5 failures for debugging
                        logger.log("🔍 DEBUG: Skipped line '\(trimmed)' - parts: \(parts.count)", category: .system)
                    }
                    continue 
                }
                
                // The process name is everything after the first two numbers
                let name = parts[2...].joined(separator: " ")
                
                // Skip empty names and kernel threads in brackets
                if !name.isEmpty && !name.hasPrefix("[") {
                    processes.append(ProcessInfo(pid: pid, ppid: ppid, name: name))
                    processedCount += 1
                    if processedCount <= 5 { // Log first 5 successful processes
                        logger.log("🔍 DEBUG: Processed '\(name)' (PID: \(pid))", category: .system)
                    }
                } else {
                    skippedCount += 1
                    if skippedCount <= 5 { // Log first 5 skipped processes
                        logger.log("🔍 DEBUG: Skipped process '\(name)' (empty or kernel thread)", category: .system)
                    }
                }
            }
            
            logger.log("🔍 DEBUG: Processed \(processedCount) processes, skipped \(skippedCount) lines", category: .system)
            
            logger.log("✅ Successfully parsed \(processes.count) valid processes", category: .system)
            
        } catch {
            logger.log("❌ Failed to get processes: \(error.localizedDescription)", category: .error)
            
            // Fallback to a minimal static list if ps command fails
            processes = [
                ProcessInfo(pid: 1, ppid: 0, name: "launchd"),
                ProcessInfo(pid: getpid(), ppid: 1, name: "MacDBG")
            ]
            logger.log("🔄 Using fallback process list with \(processes.count) processes", category: .system)
        }
        
        return processes.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    public func attachToProcess(_ pid: pid_t) async {
        macdbgLog("🔗 DebuggerController.attachToProcess called", category: .lldb)
        macdbgLog("   PID: \(pid)", category: .lldb)
        
        selectedPID = pid
        addLog("🔗 Attaching to process \(pid)...")
        
        do {
            // Try to get the executable path for the process
            macdbgLog("🔍 Getting executable path for PID \(pid)", category: .lldb)
            let executablePath = await getExecutablePath(for: pid) ?? "/usr/bin/true"
            macdbgLog("📁 Using executable path: \(executablePath)", category: .lldb)
            
            // Set the attached process path for string extraction
            attachedProcessPath = executablePath
            
            // Use Python server for persistent LLDB session
            macdbgLog("📤 Sending attachToProcess command to LLDBManager", category: .lldb)
            lldbManager.sendCommand(command: "attachToProcess", args: ["pid": pid, "executable": executablePath, "is64Bits": true])
            macdbgLog("✅ Attach command sent successfully", category: .lldb)
        } catch {
            macdbgLog("❌ Error in attachToProcess: \(error)", category: .error)
            macdbgLogCrash(error, context: "attachToProcess failed for PID \(pid)")
        }
    }
    
    // MARK: - Binary Launch
    public func launchBinary(path: String, arguments: [String] = []) async {
        addLog("🚀 Launching binary: \(path)")
        
        let actualExecutablePath = resolveExecutablePath(path)
        macdbgLog("🔍 Resolved executable path: \(actualExecutablePath)", category: .launch)
        
        if actualExecutablePath != path {
            addLog("📦 App bundle detected: \(path)")
            addLog("🎯 Actual executable: \(actualExecutablePath)")
        }
        
        // Store the original path for reference
        attachedProcessPath = path
        
        // Update state to indicate launching
        state = .attaching(0) // Use 0 as placeholder PID for launching
        
        // Step 1: Prepare executable
        lldbManager.sendCommand(command: "prepareExecutable", args: [
            "path": actualExecutablePath,
            "is64Bits": true,
            "cwd": FileManager.default.currentDirectoryPath,
            "args": arguments
        ])
        
        // Step 2: Create process after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.lldbManager.sendCommand(command: "createProcess", args: [:])
        }
    }
    
    private func resolveExecutablePath(_ path: String) -> String {
        if path.hasSuffix(".app") {
            let plistPath = path + "/Contents/Info.plist"
            if let plistData = FileManager.default.contents(atPath: plistPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let executable = plist["CFBundleExecutable"] as? String {
                return path + "/Contents/MacOS/" + executable
            }
            
            let macosDir = path + "/Contents/MacOS"
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: macosDir),
               let firstExecutable = contents.first {
                return macosDir + "/" + firstExecutable
            }
        }
        
        return path
    }
    
    // MARK: - x64dbg-style Disassembly with Smart Caching
    public func refreshDisassemblyAroundPC() async {
        guard isAttached, programCounter != 0 else {
            macdbgLog("❌ refreshDisassemblyAroundPC: not ready", category: .error)
            return
        }
        
        let pc = programCounter
        
        // Check buffer first (x64dbg optimization)
        if let cachedInstructions = getFromInstructionBuffer(around: pc) {
            macdbgLog("⚡ CACHE HIT: Using buffered instructions", category: .performance)
            self.disassembly = cachedInstructions
            return
        }
        
        macdbgLog("📤 CACHE MISS: Fetching fresh disassembly", category: .lldb)
        
        // Use Python server for persistent LLDB session
        lldbManager.sendCommand(command: "disassembly", args: ["address": String(format: "0x%llx", pc), "count": 50])
    }
    
    private func executeDirectDisassembly(around pc: UInt64) async {
        guard let executablePath = attachedProcessPath else {
            addLog("❌ No executable path available for disassembly")
            return
        }
        
        let lldbScript = """
target create "\(executablePath)"
process attach --pid \(currentPID)
disassemble --pc --count 50
register read rip
quit
"""
        
        addLog("🔧 Direct LLDB disassembly around PC: 0x\(String(format: "%llx", pc))")
        
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb")
                process.arguments = ["--no-lldbinit", "--batch"]
                
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                
                try process.run()
                
                // Send commands
                let inputHandle = inputPipe.fileHandleForWriting
                inputHandle.write(lldbScript.data(using: .utf8)!)
                inputHandle.closeFile()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                process.waitUntilExit()
                
                await MainActor.run {
                    self.addLog("📄 LLDB Disassembly Output:")
                    self.addLog(output)
                    
                    // Parse disassembly and registers
                    self.parseDirectLLDBDisassembly(output)
                }
                
            } catch {
                await MainActor.run {
                    self.addLog("❌ Direct LLDB disassembly failed: \(error)")
                }
            }
        }
    }
    
    private func parseDirectLLDBDisassembly(_ output: String) {
        var newDisassembly: [DisassemblyLine] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Parse disassembly lines like: "->  0x7ff8125dd93a <+10>: retq"
            // or: "    0x7ff8125dd93b <+11>: nop"
            if line.contains("0x") && line.contains(":") {
                // Extract address from lines like "->  0x7ff8125dd93a <+10>: retq"
                let addressPattern = "0x[0-9a-fA-F]+"
                if let range = line.range(of: addressPattern, options: .regularExpression) {
                    let addressStr = String(line[range])
                    let rest = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    
                    if let address = UInt64(addressStr.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                        // Extract instruction after the colon
                        let colonRange = rest.range(of: ":")
                        if let colonRange = colonRange {
                            let instruction = String(rest[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                            
                            // Split instruction and operands
                            let parts = instruction.components(separatedBy: .whitespaces)
                            let instructionName = parts.first ?? ""
                            let operands = parts.dropFirst().joined(separator: " ")
                            
                            let disasmLine = DisassemblyLine(
                                address: address,
                                bytes: "", // LLDB doesn't show bytes in this format
                                instruction: instructionName,
                                operands: operands
                            )
                            newDisassembly.append(disasmLine)
                        }
                    }
                }
            }
            // Also parse RIP register value
            else if line.contains("rip = 0x") {
                if let range = line.range(of: "rip = 0x") {
                    let ripString = String(line[range.upperBound...]).components(separatedBy: .whitespaces).first ?? ""
                    if let ripValue = UInt64(ripString, radix: 16) {
                        programCounter = ripValue
                        addLog("📍 PC updated to: 0x\(String(format: "%llx", ripValue))")
                    }
                }
            }
        }
        
        if !newDisassembly.isEmpty {
            disassembly = newDisassembly
            addLog("✅ Disassembly updated: \(newDisassembly.count) instructions")
        }
    }
    
    // MARK: - Stepping
    public func stepInto() async {
        guard isAttached else { return }
        addLog("🦶 Step Into")
        
        // Use Python server stepping method (persistent LLDB session)
        lldbManager.sendCommand(command: "stepInto")
    }
    
    public func stepOver() async {
        guard isAttached else { return }
        addLog("🦶 Step Over")
        
        // Use Python server stepping method (persistent LLDB session)
        lldbManager.sendCommand(command: "stepInstruction")
    }
    
    public func stepOut() async {
        guard isAttached else { return }
        addLog("🦶 Step Out")
        
        // Use Python server stepping method (persistent LLDB session)
        lldbManager.sendCommand(command: "stepOut")
    }
    
    public func stepUntilUserCode() async {
        guard isAttached else { return }
        addLog("🏃 Step Until User Code")
        
        // Use Python server stepping method (persistent LLDB session)
        lldbManager.sendCommand(command: "stepUntilUserCode")
    }
    
    public func continueExecution() async {
        guard isAttached else { return }
        addLog("▶️ Continue")
        
        // Use Python server stepping method (persistent LLDB session)
        lldbManager.sendCommand(command: "continueExecution")
    }
    
    // Direct LLDB execution - proven to work from CLI tests
    private func executeDirectLLDBCommand(_ command: String) async {
        guard let executablePath = attachedProcessPath else {
            addLog("❌ No executable path available")
            return
        }
        
        let lldbScript = """
target create "\(executablePath)"
process attach --pid \(currentPID)
\(command)
register read rip
disassemble --pc --count 10
quit
"""
        
        addLog("🔧 Executing direct LLDB: \(command)")
        
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb")
                process.arguments = ["--no-lldbinit", "--batch"]
                
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                
                try process.run()
                
                // Send commands
                let inputHandle = inputPipe.fileHandleForWriting
                inputHandle.write(lldbScript.data(using: .utf8)!)
                inputHandle.closeFile()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                process.waitUntilExit()
                
                await MainActor.run {
                    self.addLog("📄 LLDB Output:")
                    self.addLog(output)
                    
                    // Parse the output for RIP register value
                    self.parseDirectLLDBOutput(output)
                }
                
            } catch {
                await MainActor.run {
                    self.addLog("❌ Direct LLDB execution failed: \(error)")
                }
            }
        }
    }
    
    private func parseDirectLLDBOutput(_ output: String) {
        // Extract RIP register value
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("rip = 0x") {
                if let range = line.range(of: "rip = 0x") {
                    let ripString = String(line[range.upperBound...]).components(separatedBy: .whitespaces).first ?? ""
                    if let ripValue = UInt64(ripString, radix: 16) {
                        programCounter = ripValue
                        addLog("📍 PC updated to: 0x\(String(format: "%llx", ripValue))")
                        
                        // Refresh disassembly with new PC
                        Task {
                            await refreshDisassembly()
                        }
                        break
                    }
                }
            }
        }
    }
    
    
    // MARK: - Breakpoints
    public func setBreakpoint(at address: UInt64) async {
        guard isAttached else { return }
        pendingBreakpointAddress = address
        addLog("🔴 Setting breakpoint at 0x\(String(format: "%llx", address))")
        lldbManager.sendCommand(command: "setBreakpoint", args: ["address": String(format: "0x%llx", address)])
    }
    
    public func removeBreakpoint(at address: UInt64) async {
        guard isAttached, let breakpointID = breakpointIDs[address] else { return }
        addLog("⚪ Removing breakpoint at 0x\(String(format: "%llx", address))")
        lldbManager.sendCommand(command: "removeBreakpoint", args: ["id": breakpointID])
    }
    
    public func toggleBreakpoint(at address: UInt64) async {
        if breakpoints.contains(address) {
            await removeBreakpoint(at: address)
        } else {
            await setBreakpoint(at: address)
        }
    }
    
    public func hasBreakpoint(at address: UInt64) -> Bool {
        return breakpoints.contains(address)
    }
    
    public func clearAllBreakpoints() {
        breakpoints.removeAll()
        breakpointIDs.removeAll()
        pendingBreakpointAddress = nil
        addLog("🗑️ Cleared all breakpoints")
    }
    
    // MARK: - Refresh Functions
    public func refreshRegisters() async {
        guard isAttached else { return }
        lldbManager.getRegisters()
    }
    
    public func refreshDisassembly() async {
        guard isAttached else { return }
        await refreshDisassemblyAroundPC()
    }
    
    // MARK: - Memory Operations
    public func getMemoryAt(address: UInt64, size: Int = 256) async {
        guard isAttached else { return }
        lldbManager.readMemory(from: address, count: size)
    }
    
    public func writeByteAtAddress(_ address: UInt64, byte: UInt8) async {
        guard isAttached else { return }
        
        // Store original byte if not already stored
        if originalBytes[address] == nil {
            originalBytes[address] = [memory[address]?.first ?? 0]
        }
        
        // Store the patch
        memoryPatches[address] = [byte]
        
        // Send write command
        lldbManager.sendCommand(command: "writeByte", args: [
            "address": String(format: "0x%llx", address),
            "value": String(format: "0x%02x", byte)
        ])
        
        addLog("✏️ Patched byte at 0x\(String(format: "%llx", address)): 0x\(String(format: "%02x", byte))")
    }
    
    // MARK: - Logging
    public func addLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        
        if Thread.isMainThread {
            logs.append(logEntry)
        } else {
            DispatchQueue.main.async {
                self.logs.append(logEntry)
            }
        }
    }
    
    // MARK: - State Management
    private func updateStatus(from state: DebuggerState) {
        // Update UI state based on debugger state
    }
    
    public func cleanup() {
        // lldbManager cleanup would go here if the method existed
        clearAllBreakpoints()
    }
    
    // MARK: - Export
    public func exportData() -> String {
        let exportData: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "isAttached": isAttached,
            "programCounter": String(format: "0x%llx", programCounter),
            "disassemblyCount": disassembly.count,
            "registerCount": registers.count,
            "logCount": logs.count
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) {
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
    
    public func getExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "macdbg_debug_\(formatter.string(from: Date())).json"
    }
}

// MARK: - LLDBManagerDelegate
extension DebuggerController {
    func lldbManagerDidConnect() {
        DispatchQueue.main.async {
            self.addLog("🔌 LLDB Manager connected")
        }
    }
    
    func lldbManagerDidDisconnect() {
        DispatchQueue.main.async {
            self.isAttached = false
            self.state = .idle
            self.currentPID = 0
            self.addLog("🔌 LLDB Manager disconnected")
        }
    }
    
    func lldbManagerDidAttach(pid: pid_t) {
        DispatchQueue.main.async {
            self.isAttached = true
            self.currentPID = pid
            self.state = .attached
            self.addLog("🔗 Attached to process \(pid)")
        }
    }
    
    func lldbManagerDidAttach() async {
        await MainActor.run {
            state = .attached
            isAttached = true
            addLog("🔗 Successfully attached to process")
        }
        
        logger.log("✅ Process attachment confirmed, stopping process for debugging", category: .lldb)
        
        // Wait a moment for the process to stabilize
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Stop the process first so we can debug it
        lldbManager.sendCommand(command: "stopExecution", args: [:])
        addLog("⏸️ Stopping process for debugging")
        
        // Wait for process to stop, then request initial data
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Request registers first to get the program counter
        lldbManager.getRegisters()
        
        logger.log("📊 Initial register request sent, will request disassembly after registers are loaded", category: .lldb)
    }
    
    func lldbManagerDidDetach() async {
        await MainActor.run {
            isAttached = false
            state = .idle
            currentPID = 0
            programCounter = 0
            registers.removeAll()
            disassembly.removeAll()
            memory.removeAll()
            addLog("🔌 Detached from process")
        }
    }
    
    func lldbManagerDidStop(event: LLDBStoppedEvent) async {
        await MainActor.run {
            state = .stopped(reason: event.reason)
            programCounter = event.pc
            
            if event.reason == "launched" {
                isAttached = true
                
                // Clear cache for new binary
                instructionBuffer.removeAll()
                disassemblyCache.removeAll()
                lastCachedRange = nil
                requestThrottle = Date.distantPast
                
                addLog("🚀 Binary launched - PC: 0x\(String(format: "%llx", event.pc))")
                
                // Force stop after launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.lldbManager.forceStopAndReport()
                }
            }
            
            addLog("⏸️ Process stopped at 0x\(String(format: "%llx", event.pc)): \(event.reason)")
        }
        
        // Refresh data immediately
        lldbManager.getRegisters()
        
        // For stepping events, refresh disassembly around the NEW PC to highlight current instruction
        if event.reason == "step" || event.reason == "step_into" || event.reason == "step_over" || event.reason == "step_out" || event.reason == "step_until_user_code" {
            addLog("🎯 Refreshing disassembly around new PC: 0x\(String(format: "%llx", event.pc))")
            addLog("🔄 Sending disassembly request for stepping event...")
            lldbManager.getDisassembly(from: event.pc, count: 50)
        } else {
            addLog("🔄 Sending disassembly request for non-stepping event...")
            lldbManager.getDisassembly(from: event.pc, count: 50)
        }
    }
    
    func lldbManagerDidReceiveRegisters(response: LLDBRegistersResponse) async {
        await MainActor.run {
            // Convert String values to UInt64, handling null values
            var convertedRegisters: [String: UInt64] = [:]
            for (key, value) in response.registers {
                guard let value = value, !value.isEmpty else { continue }
                if let intValue = UInt64(value.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                    convertedRegisters[key] = intValue
                } else if let intValue = UInt64(value) {
                    convertedRegisters[key] = intValue
                }
            }
            self.registers = convertedRegisters
            self.addLog("📊 Registers updated (\(convertedRegisters.count) registers)")
            
            // Update program counter from RIP register
            if let rip = convertedRegisters["rip"], rip != 0 {
                let oldPC = self.programCounter
                self.programCounter = rip
                logger.log("🎯 Program counter updated to: 0x\(String(format: "%llx", rip))", category: .lldb)
                
                // If PC changed significantly, refresh disassembly around the new PC
                if oldPC != rip {
                    addLog("🔄 PC changed from 0x\(String(format: "%llx", oldPC)) to 0x\(String(format: "%llx", rip)) - refreshing disassembly")
                    self.lldbManager.getDisassembly(from: rip, count: 50)
                }
                
                // If we're attached and don't have disassembly yet, request it from the PC
                if self.isAttached && self.disassembly.isEmpty {
                    logger.log("📊 Requesting disassembly from PC after register load", category: .lldb)
                    self.lldbManager.getDisassembly(from: rip, count: 100)
                }
            }
            
            // Auto-extract strings after successful attachment (like Ghidra)
            if self.isAttached && self.attachedProcessPath != nil && self.strings.isEmpty {
                Task {
                    // Small delay to let everything settle
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self.extractStrings()
                }
            }
        }
    }
    
    func lldbManagerDidReceiveDisassembly(response: LLDBDisassemblyResponse) async {
        await MainActor.run {
            addLog("📥 Received disassembly response with \(response.lines.count) lines")
            
            // Filter out invalid disassembly lines to prevent crashes
            let validLines = response.lines.filter { line in
                line.address > 0 && 
                !line.instruction.isEmpty &&
                line.instruction != "??" &&
                line.instruction != "invalid"
            }
            
            addLog("📊 Filtered to \(validLines.count) valid instructions")
            
            // Directly update the disassembly array on main thread
            disassembly = validLines
            addLog("📊 Disassembly updated (\(validLines.count) valid instructions)")
            
            if !validLines.isEmpty {
                addLog("🎯 Disassembly range: 0x\(String(format: "%llx", validLines.first!.address)) - 0x\(String(format: "%llx", validLines.last!.address))")
                
                // Check if current PC is in the disassembly
                let currentPC = programCounter
                if let pcIndex = validLines.firstIndex(where: { $0.address == currentPC }) {
                    addLog("✅ Current PC (0x\(String(format: "%llx", currentPC))) found at index \(pcIndex) in disassembly")
                } else {
                    addLog("⚠️ Current PC (0x\(String(format: "%llx", currentPC))) NOT found in disassembly range")
                }
            } else {
                addLog("⚠️ No valid disassembly lines received")
            }
        }
    }
    
    func lldbManagerDidReceiveMemory(response: LLDBMemoryResponse) async {
        DispatchQueue.main.async {
            // Convert lines to memory dictionary
            for line in response.lines {
                // Convert string address to UInt64
                if let address = UInt64(line.address.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                    // Convert hex string bytes to [UInt8]
                    let hexString = line.bytes.replacingOccurrences(of: " ", with: "")
                    var bytes: [UInt8] = []
                    for i in stride(from: 0, to: hexString.count, by: 2) {
                        let start = hexString.index(hexString.startIndex, offsetBy: i)
                        let end = hexString.index(start, offsetBy: 2)
                        if let byte = UInt8(String(hexString[start..<end]), radix: 16) {
                            bytes.append(byte)
                        }
                    }
                    self.memory[address] = bytes
                }
            }
            self.addLog("💾 Memory updated: \(response.lines.count) lines")
        }
    }
    
    func lldbManagerDidReceiveError(error: LLDBErrorEvent) async {
        DispatchQueue.main.async {
            self.addLog("❌ LLDB Error: \(error.message)")
        }
    }
    
    func lldbManagerDidReceiveBreakpointResponse(response: [String: Any]) async {
        DispatchQueue.main.async {
            if let success = response["success"] as? Bool, success,
               let address = self.pendingBreakpointAddress,
               let id = response["id"] as? Int {
                self.breakpoints.insert(address)
                self.breakpointIDs[address] = id
                self.addLog("✅ Breakpoint set at 0x\(String(format: "%llx", address))")
            } else {
                self.addLog("❌ Failed to set breakpoint")
            }
            self.pendingBreakpointAddress = nil
        }
    }
    
    func lldbManagerDidReceiveWriteByteResponse(success: Bool, error: String?) async {
        DispatchQueue.main.async {
            if success {
                self.addLog("✅ Byte write successful")
            } else {
                self.addLog("❌ Byte write failed: \(error ?? "unknown error")")
            }
        }
    }
}

// MARK: - x64dbg-style Instruction Buffer Management
extension DebuggerController {
    private func updateInstructionBuffer(with newInstructions: [DisassemblyLine]) {
        guard let firstInstr = newInstructions.first, let lastInstr = newInstructions.last else { return }
        
        let newStart = firstInstr.address
        let newEnd = lastInstr.address
        
        if instructionBuffer.isEmpty ||
           newStart < bufferBaseAddress ||
           newEnd > bufferBaseAddress + UInt64(bufferSize * 8) {
            // Replace buffer
            instructionBuffer = newInstructions
            bufferBaseAddress = newStart
            bufferSize = newInstructions.count
            macdbgLog("🔄 X64DBG BUFFER REPLACE: \(newInstructions.count) instructions", category: .performance)
        } else {
            // Merge
            mergeInstructionsIntoBuffer(newInstructions)
        }
        
        // Trim if too large
        if instructionBuffer.count > maxBufferSize {
            let trimStart = instructionBuffer.count - maxBufferSize
            instructionBuffer = Array(instructionBuffer[trimStart...])
            if let firstKept = instructionBuffer.first {
                bufferBaseAddress = firstKept.address
            }
            bufferSize = instructionBuffer.count
        }
    }
    
    private func mergeInstructionsIntoBuffer(_ newInstructions: [DisassemblyLine]) {
        var added = 0
        for newInstr in newInstructions {
            if !instructionBuffer.contains(where: { $0.address == newInstr.address }) {
                instructionBuffer.append(newInstr)
                added += 1
            }
        }
        
        instructionBuffer.sort { $0.address < $1.address }
        bufferSize = instructionBuffer.count
    }
    
    private func getFromInstructionBuffer(around pc: UInt64) -> [DisassemblyLine]? {
        guard !instructionBuffer.isEmpty else { return nil }
        
        guard let pcIndex = instructionBuffer.firstIndex(where: { $0.address >= pc }) else {
            return nil
        }
        
        let visibleCount = 100
        let startIndex = max(0, pcIndex - visibleCount / 2)
        let endIndex = min(instructionBuffer.count, startIndex + visibleCount)
        
        if endIndex > startIndex {
            return Array(instructionBuffer[startIndex..<endIndex])
        }
        
        return nil
    }
    
    private func getVisibleInstructions() -> [DisassemblyLine] {
        guard !instructionBuffer.isEmpty else { return [] }
        
        let pc = programCounter
        let visibleCount = 200
        
        if let pcIndex = instructionBuffer.firstIndex(where: { $0.address >= pc }) {
            let startIndex = max(0, pcIndex - visibleCount / 2)
            let endIndex = min(instructionBuffer.count, startIndex + visibleCount)
            return Array(instructionBuffer[startIndex..<endIndex])
        }
        
        let startIndex = max(0, instructionBuffer.count - visibleCount)
        return Array(instructionBuffer[startIndex...])
    }
    
    // MARK: - Missing Methods Referenced by Views
    
    
    public func detach() {
        lldbManager.sendCommand(command: "detach", args: [:])
        addLog("🔌 Detaching from process")
    }
    
    public func attach(to pid: pid_t) async {
        logger.log("🔗 Starting attach to process \(pid)", category: .lldb)
        
        // Check if already attached to this process
        if isAttached && currentPID == pid {
            logger.log("⚠️ Already attached to PID \(pid), skipping duplicate attach", category: .lldb)
            addLog("⚠️ Already attached to PID: \(pid)")
            return
        }
        
        // If attached to different process, detach first
        if isAttached && currentPID != pid {
            logger.log("🔄 Detaching from PID \(currentPID) before attaching to \(pid)", category: .lldb)
            detach()
            // Wait a moment for detach to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        selectedPID = pid
        
        // Try to get the executable path for the process
        let executablePath = await getExecutablePath(for: pid) ?? "/usr/bin/true"
        logger.log("📁 Using executable path: \(executablePath)", category: .lldb)
        
        // Set the attached process path for string extraction
        attachedProcessPath = executablePath
        
        // Use Python server for persistent LLDB session
        lldbManager.sendCommand(command: "attachToProcess", args: ["pid": pid, "executable": executablePath, "is64Bits": true])
    }
    
    private func executeDirectAttach(pid: pid_t, executablePath: String) async {
        let lldbScript = """
target create "\(executablePath)"
process attach --pid \(pid)
register read rip
disassemble --pc --count 10
"""
        
        addLog("🔧 Direct LLDB attach to PID: \(pid)")
        
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb")
                process.arguments = ["--no-lldbinit", "--batch"]
                
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                
                try process.run()
                
                // Send commands
                let inputHandle = inputPipe.fileHandleForWriting
                inputHandle.write(lldbScript.data(using: .utf8)!)
                inputHandle.closeFile()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                process.waitUntilExit()
                
                await MainActor.run {
                    self.addLog("📄 LLDB Attach Output:")
                    self.addLog(output)
                    
                    // Check if attach was successful
                    if output.contains("Process") && (output.contains("stopped") || output.contains("attached")) {
                        self.isAttached = true
                        self.currentPID = pid
                        self.state = .attached
                        self.addLog("✅ Successfully attached to PID: \(pid)")
                        
                        // Parse initial state
                        self.parseDirectLLDBOutput(output)
                        
                        // Trigger disassembly refresh after successful attach
                        Task {
                            await self.refreshDisassemblyAroundPC()
                        }
                    } else {
                        self.addLog("❌ Failed to attach to PID: \(pid)")
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.addLog("❌ Direct LLDB attach failed: \(error)")
                }
            }
        }
    }
    
    private func getExecutablePath(for pid: pid_t) async -> String? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "comm="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let execPath = output, !execPath.isEmpty {
                logger.log("📁 Found executable path for PID \(pid): \(execPath)", category: .lldb)
                return execPath
            }
        } catch {
            logger.log("❌ Failed to get executable path for PID \(pid): \(error)", category: .error)
        }
        
        return nil
    }
    
    public func expandDisassemblyRange(direction: DisassemblyDirection) async {
        // Stub implementation
        addLog("📈 Expanding disassembly range: \(direction)")
    }
    
    public func getDisassemblyAt(address: UInt64, count: Int = 200) async {
        guard isAttached else { return }
        addLog("🎯 Requesting disassembly around address: 0x\(String(format: "%llx", address))")
        
        // Use direct LLDB disassembly
        await executeDirectDisassemblyAt(address: address, count: count)
    }
    
    private func executeDirectDisassemblyAt(address: UInt64, count: Int) async {
        guard let executablePath = attachedProcessPath else {
            addLog("❌ No executable path available for disassembly")
            return
        }
        
        let lldbScript = """
target create "\(executablePath)"
process attach --pid \(currentPID)
disassemble --address 0x\(String(format: "%llx", address)) --count \(count)
register read rip
quit
"""
        
        addLog("🔧 Direct LLDB disassembly at address: 0x\(String(format: "%llx", address))")
        
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb")
                process.arguments = ["--no-lldbinit", "--batch"]
                
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                
                process.standardInput = inputPipe
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                
                try process.run()
                
                // Send commands
                let inputHandle = inputPipe.fileHandleForWriting
                inputHandle.write(lldbScript.data(using: .utf8)!)
                inputHandle.closeFile()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                process.waitUntilExit()
                
                await MainActor.run {
                    self.addLog("📄 LLDB Disassembly Output:")
                    self.addLog(output)
                    
                    // Parse disassembly and registers
                    self.parseDirectLLDBDisassembly(output)
                }
                
            } catch {
                await MainActor.run {
                    self.addLog("❌ Direct LLDB disassembly failed: \(error)")
                }
            }
        }
    }
    
    public func writeBytes(address: UInt64, bytes: [UInt8]) async {
        let hexString = bytes.map { String(format: "%02x", $0) }.joined()
        lldbManager.sendCommand(command: "writeBytes", args: [
            "address": String(format: "0x%llx", address),
            "bytes": hexString
        ])
        addLog("✏️ Writing \(bytes.count) bytes at 0x\(String(format: "%llx", address))")
    }
    
    public func readMemory(address: UInt64, bytes: Int) async {
        lldbManager.readMemory(from: address, count: bytes)
    }
    
    public func addManualLog(_ message: String) {
        addLog("👤 \(message)")
    }
    
    public func clearLogs() {
        logs.removeAll()
        addLog("🧹 Logs cleared")
    }
    
    public func navigateToAddress(_ address: UInt64) async {
        navigationTarget = address
        addLog("🧭 Navigating to address: 0x\(String(format: "%llx", address))")
    }
    
    // MARK: - String Analysis (Ghidra-style Implementation)
    
    /// Extract strings from the attached process (like Ghidra's string analysis)
    public func extractStrings() async {
        guard isAttached, let processPath = attachedProcessPath else {
            addLog("❌ No process attached for string extraction")
            return
        }
        
        addLog("🔍 Extracting strings from process...")
        
        // Simple file-based string extraction for now
        // TODO: Implement LLDB-based memory string extraction
        let extractedStrings = await extractStringsFromBinary(path: processPath)
        
        await MainActor.run {
            self.strings = extractedStrings
            addLog("✅ Extracted \(extractedStrings.count) strings")
        }
    }
    
    /// Navigate to the first code reference of a string (like Ghidra's "Go To" functionality)
    public func navigateToStringReference(_ stringAddress: UInt64) {
        print("🎯 CRITICAL: Finding FIRST code reference to string 0x\(String(format: "%llx", stringAddress))")
        selectedStringAddress = stringAddress
        
        // Send command to find string references
        lldbManager.sendCommand(command: "findStringReferences", args: ["stringAddress": stringAddress])
    }
    
    /// Find all code references to a string (like Ghidra's XRef functionality)
    public func findStringReferences(_ stringAddress: UInt64) {
        print("🎯 Finding ALL references to string 0x\(String(format: "%llx", stringAddress))")
        selectedStringAddress = stringAddress
        
        // Send command to find string references
        lldbManager.sendCommand(command: "findStringReferences", args: ["stringAddress": stringAddress])
    }
    
    /// Handle string references response from LLDB server
    func lldbManagerDidReceiveStringReferences(response: LLDBStringReferencesResponse) async {
        await MainActor.run {
            addLog("🔍 Found \(response.payload.count) string references")
            
            // Update string references for XRef panel
            stringReferences = response.payload.references
            
            // If we have references, navigate to the first one (like Ghidra)
            if let firstRef = response.payload.references.first {
                addLog("🎯 Navigating to first reference at 0x\(String(format: "%llx", firstRef.address))")
                Task {
                    await navigateToAddress(firstRef.address)
                }
            } else {
                addLog("❌ No references found for string 0x\(String(format: "%llx", response.payload.stringAddress))")
            }
        }
    }
    
    /// Simple file-based string extraction (temporary implementation)
    private func extractStringsFromBinary(path: String) async -> [StringData] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                var strings: [StringData] = []
                
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    let bytes = Array(data)
                    
                    var currentString = ""
                    var startOffset = 0
                    let baseAddress: UInt64 = 0x100000000  // Typical macOS base address
                    
                    for (i, byte) in bytes.enumerated() {
                        if byte >= 32 && byte <= 126 { // Printable ASCII
                            if currentString.isEmpty {
                                startOffset = i
                            }
                            if let scalar = UnicodeScalar(Int(byte)) {
                                currentString += String(Character(scalar))
                            }
                        } else {
                            if currentString.count >= 4 { // Minimum string length
                                let stringData = StringData(
                                    address: baseAddress + UInt64(startOffset),
                                    content: currentString,
                                    length: currentString.count
                                )
                                strings.append(stringData)
                            }
                            currentString = ""
                        }
                    }
                    
                    // Don't forget the last string
                    if currentString.count >= 4 {
                        let stringData = StringData(
                            address: baseAddress + UInt64(startOffset),
                            content: currentString,
                            length: currentString.count
                        )
                        strings.append(stringData)
                    }
                    
                } catch {
                    print("Error reading binary file: \(error)")
                }
                
                continuation.resume(returning: strings)
            }
        }
    }
}


// MARK: - DateFormatter Extension
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
