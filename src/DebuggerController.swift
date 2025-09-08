import Foundation
import SwiftUI

/// PERFORMANCE: DebuggerController with x64dbg-style optimizations
@MainActor
public class DebuggerController: ObservableObject, LLDBManagerDelegate {
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
        lldbManager.delegate = self
        lldbManager.onLog = { [weak self] message in
            DispatchQueue.main.async {
                self?.addLog(message)
            }
        }
    }
    
    // MARK: - Process Management
    public func refreshProcessList() {
        // Implementation...
        processes = [] // Simplified for now
    }
    
    public func attachToProcess(_ pid: pid_t) async {
        selectedPID = pid
        addLog("🔗 Attaching to process \(pid)...")
        
        lldbManager.sendCommand(command: "attach", args: ["pid": pid])
    }
    
    // MARK: - Binary Launch
    public func launchBinary(path: String, arguments: [String] = []) async {
        addLog("🚀 Launching binary: \(path)")
        
        let actualExecutablePath = resolveExecutablePath(path)
        macdbgLog("🔍 Resolved executable path: \(actualExecutablePath)", category: .launch)
        
        lldbManager.sendCommand(command: "prepareExecutable", args: [
            "path": path
        ])
        
        attachedProcessPath = actualExecutablePath
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
        
        // Fetch large buffer like x64dbg
        let instructionsBefore: UInt64 = 200
        let instructionsAfter: UInt64 = 300
        let start: UInt64 = pc > instructionsBefore * 4 ? pc - instructionsBefore * 4 : 0
        let totalCount = Int(instructionsBefore + instructionsAfter)
        
        lldbManager.getDisassembly(from: start, count: totalCount)
    }
    
    // MARK: - Stepping
    public func stepInto() async {
        guard isAttached else { return }
        addLog("🦶 Step Into")
        lldbManager.sendCommand(command: "stepInto", args: [:])
    }
    
    public func stepOver() async {
        guard isAttached else { return }
        addLog("🦶 Step Over")
        lldbManager.sendCommand(command: "stepOver", args: [:])
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
        lldbManager.getDisassembly(from: programCounter, count: 150)
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
        DispatchQueue.main.async {
            self.state = .attached
            self.isAttached = true
            self.addLog("🔗 Successfully attached to process")
        }
    }
    
    func lldbManagerDidDetach() {
        DispatchQueue.main.async {
            self.isAttached = false
            self.state = .idle
            self.currentPID = 0
            self.programCounter = 0
            self.registers.removeAll()
            self.disassembly.removeAll()
            self.memory.removeAll()
            self.addLog("🔗 Detached from process")
        }
    }
    
    func lldbManagerDidStop(event: LLDBStoppedEvent) {
        DispatchQueue.main.async {
            self.state = .stopped(reason: event.reason)
            self.programCounter = event.pc
            
            if event.reason == "launched" {
                self.isAttached = true
                
                // Clear cache for new binary
                self.instructionBuffer.removeAll()
                self.disassemblyCache.removeAll()
                self.lastCachedRange = nil
                self.requestThrottle = Date.distantPast
                
                self.addLog("🚀 Binary launched - PC: 0x\(String(format: "%llx", event.pc))")
                
                // Force stop after launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.lldbManager.forceStopAndReport()
                }
            }
            
            // Refresh data
            Task {
                await self.refreshRegisters()
                await self.refreshDisassemblyAroundPC()
            }
        }
    }
    
    func lldbManagerDidReceiveRegisters(response: LLDBRegistersResponse) async {
        DispatchQueue.main.async {
            // Convert String values to UInt64
            var convertedRegisters: [String: UInt64] = [:]
            for (key, value) in response.registers {
                if let intValue = UInt64(value.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                    convertedRegisters[key] = intValue
                } else if let intValue = UInt64(value) {
                    convertedRegisters[key] = intValue
                }
            }
            self.registers = convertedRegisters
            self.addLog("📊 Registers updated (\(response.registers.count) registers)")
        }
    }
    
    func lldbManagerDidReceiveDisassembly(response: LLDBDisassemblyResponse) {
        instructionQueue.async {
            // Update instruction buffer in background
            self.updateInstructionBuffer(with: response.lines)
            
            // Cache results
            for line in response.lines {
                self.disassemblyCache[line.address] = line
            }
            
            if let firstLine = response.lines.first, let lastLine = response.lines.last {
                self.lastCachedRange = (start: firstLine.address, end: lastLine.address)
            }
            
            // Update UI
            DispatchQueue.main.async {
                self.disassembly = self.getVisibleInstructions()
                self.addLog("📊 Disassembly updated (\(response.lines.count) instructions)")
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
    public func stepOut() async {
        lldbManager.sendCommand(command: "stepOut", args: [:])
        addLog("⬆️ Step out")
    }
    
    public func continueExecution() async {
        lldbManager.sendCommand(command: "continue", args: [:])
        addLog("▶️ Continue execution")
    }
    
    public func detach() {
        lldbManager.sendCommand(command: "detach", args: [:])
        addLog("🔌 Detaching from process")
    }
    
    public func attach(to pid: pid_t) async {
        selectedPID = pid
        lldbManager.sendCommand(command: "attach", args: ["pid": pid])
        addLog("🎯 Attaching to PID: \(pid)")
    }
    
    public func expandDisassemblyRange(direction: DisassemblyDirection) async {
        // Stub implementation
        addLog("📈 Expanding disassembly range: \(direction)")
    }
    
    public func getDisassemblyAt(address: UInt64) async {
        lldbManager.sendCommand(command: "getDisassembly", args: ["address": String(format: "0x%llx", address)])
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
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
