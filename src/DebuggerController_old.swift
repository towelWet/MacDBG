import Foundation
import Combine
import Darwin
import AppKit

public enum DebuggerState {
    case idle
    case attaching(pid_t)
    case running
    case stepping
    case continuing
    case stopped(reason: String)
    case detaching
    case error(String)
}

@MainActor
public class DebuggerController: ObservableObject, LLDBManagerDelegate {
    @Published public var state: DebuggerState = .idle {
        didSet {
            updateStatus(from: state)
        }
    }
    @Published public var status = "Ready"
    @Published public var isAttached = false
    @Published var currentPID: pid_t = 0
    @Published public var programCounter: UInt64 = 0
    @Published public var processes: [ProcessInfo] = []
    @Published public var registers: [String: String] = [:]
    @Published public var disassembly: [DisassemblyLine] = []
    @Published public var disassemblyUpdateTrigger: Int = 0  // Force UI updates
    @Published public var memory: [MemoryLine] = []
    @Published public var logs: [String] = []
    @Published public var navigationTarget: UInt64 = 0  // Target address for navigation focus
    @Published public var breakpoints: Set<UInt64> = []  // Active breakpoint addresses
    private var breakpointIDs: [UInt64: Int] = [:]  // Map address -> LLDB breakpoint ID
    @Published public var attachedProcessPath: String? = nil  // Path to attached process binary
    private var nextBreakpointID: Int = 1  // Track next expected breakpoint ID
    private var pendingBreakpointAddress: UInt64? = nil  // Address waiting for breakpoint ID
    
    // MARK: - Patch Tracking
    @Published public var memoryPatches: [UInt64: [UInt8]] = [:]  // Track patches for export
    private var originalBytes: [UInt64: [UInt8]] = [:]  // Store original bytes for potential restoration
    
    // MARK: - Performance Optimizations
    // PERFORMANCE: x64dbg-style instruction buffer and caching
    private var instructionBuffer: [DisassemblyLine] = []
    private var bufferBaseAddress: UInt64 = 0
    private var bufferSize: Int = 0
    private var maxBufferSize: Int = 2048  // Large buffer like x64dbg
    
    private var disassemblyCache: [UInt64: DisassemblyLine] = [:]
    private var lastCachedRange: (start: UInt64, end: UInt64)?
    private var requestThrottle: Date = Date.distantPast
    
    // PERFORMANCE: Batch processing queue
    private let instructionQueue = DispatchQueue(label: "instruction.processing", qos: .userInitiated)
    
    private let lldbManager = LLDBManager()
    
    public init() {
        refreshProcessList()
        // Seed an initial log so the Log tab is never empty
        addLog("MacDBG initialized")
        lldbManager.delegate = self
        lldbManager.onLog = { [weak self] logMessage in
            self?.addLog(logMessage)
        }
        do {
            try lldbManager.start()
        } catch {
            addLog("Failed to start LLDBManager: \(error.localizedDescription)")
            status = "❌ LLDBManager failed to start"
        }
    }
    
    deinit {
        // Avoid calling @MainActor methods from deinit; CLI lldb will be stopped on explicit detach
    }
    
    public func refreshProcessList() {
        Task {
            let newProcesses = await self.getRunningProcesses()
            await MainActor.run {
                self.processes = newProcesses
            }
        }
    }
    
    public func attach(to pid: pid_t) async {
        guard !isAttached else {
            addLog("Already attached to a process")
            return
        }
        
        status = "Attaching to PID \(pid)..."
        addLog("Starting attach to PID \(pid)")
        
        // Check if target is protected
        if await isProtectedProcess(pid: pid) {
            status = "❌ Cannot attach to protected process"
            addLog("WARNING: PID \(pid) appears to be a protected/system process")
            addLog("Try attaching to user-built applications instead")
            return
        }

        // Find the executable path for the given PID
        guard let processInfo = processes.first(where: { $0.pid == pid }),
              let executablePath = findExecutablePath(for: processInfo) else {
            status = "❌ Could not find executable for PID \(pid)"
            addLog("Failed to get executable path for PID \(pid)")
            return
        }

        lldbManager.attach(pid: pid, executablePath: executablePath)

        self.state = .attaching(pid)
        currentPID = pid // Set PID immediately for context
        attachedProcessPath = executablePath // Store for export functionality
        addLog("Attach command sent for PID \(pid) with executable \(executablePath)")


    }

    
    public func detach() {
        guard isAttached else { return }
        
        state = .detaching
        addLog("Detaching from PID \(currentPID)")
        clearAllBreakpoints()  // Clear breakpoints on detach
        lldbManager.detach()
    }
    
    public func step() async {
        guard case .stopped = state else {
            addLog("STEP_CMD: Aborted, not in a stopped state. Current state: \(state)")
            return
        }
        
        addLog("STEP_CMD: Starting step from PC: \(String(format: "0x%llx", programCounter))")
        state = .stepping
        addLog("STEP_CMD: Sending 'stepInstruction' to lldb_server.py...")
        lldbManager.stepInstruction()
    }
    
    public func stepInto() async {
        await step()
    }
    
    public func stepOver() async {
        guard case .stopped = state else {
            addLog("STEP_OVER: Aborted, not in a stopped state. Current state: \(state)")
            return
        }
        
        addLog("STEP_OVER: Starting step from PC: \(String(format: "0x%llx", programCounter))")
        state = .stepping
        addLog("STEP_OVER: Sending 'stepOver'...")
        lldbManager.stepOver()
    }
    
    public func stepOut() async {
        guard case .stopped = state else {
            addLog("STEP_OUT: Aborted, not in a stopped state.")
            return
        }
        state = .stepping
        addLog("STEP_OUT: Sending 'stepOut'...")
        lldbManager.stepOut()
    }
    
    public func continueExecution() async {
        guard case .stopped = state else {
            addLog("CONTINUE_CMD: Aborted, not in a stopped state.")
            return
        }
        
        state = .continuing
        addLog("Continue command sent.")
        lldbManager.continueExecution()
        // Optimistically assume the process is now running.
        // We won't get another event until it stops again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Brief delay to allow status to show 'continuing'
            self.state = .running
        }
    }
    
    private func getRunningProcesses() async -> [ProcessInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid,ppid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let output = String(data: data, encoding: .utf8) {
                let lines = output.split(whereSeparator: \.isNewline).dropFirst() // Drop header
                return lines.compactMap {
                    let parts = $0.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                    guard parts.count >= 3,
                          let pid = pid_t(parts[0]),
                          let ppid = pid_t(parts[1]) else {
                        return nil
                    }
                    let name = String(parts[2])
                    return ProcessInfo(pid: pid, ppid: ppid, name: name)
                }
            }
        } catch {
            addLog("Failed to get running processes: \(error.localizedDescription)")
        }
        return []
    }

    private func findExecutablePath(for processInfo: ProcessInfo) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(processInfo.pid)", "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {
            addLog("Failed to find executable path: \(error.localizedDescription)")
        }
        return nil
    }

    public func cleanup() {
        lldbManager.stop()
    }
    
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
    
    // Call on app termination to detach cleanly and stop LLDB backend.
    public func shutdownOnExit() {
        if isAttached {
            addLog("App exiting: detaching from PID \(currentPID)...")
            lldbManager.detach()
        }
        cleanup()
    }
    
    public func addLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        
        // Ensure UI updates happen on main thread
        if Thread.isMainThread {
            logs.append(logEntry)
        } else {
            DispatchQueue.main.async {
                self.logs.append(logEntry)
            }
        }
    }
    
    // Expose a safe UI-accessible method to inject a manual log for debugging UI pipeline
    func addManualLog(_ message: String) {
        addLog(message)
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    public func readMemory(address: String, bytes: Int) async {
        guard isAttached else {
            addLog("No process available for memory read")
            return
        }
        
        guard let addr = UInt64(address.hasPrefix("0x") ? String(address.dropFirst(2)) : address, radix: 16) else {
            addLog("Invalid address format: \(address)")
            return
        }
        
        addLog("Memory read command sent for address \(address).")
        lldbManager.readMemory(from: addr, count: bytes)
    }
    
    public func writeByte(address: UInt64, value: UInt8) async {
        guard isAttached else {
            addLog("No process available for memory write")
            return
        }
        
        guard case .stopped = state else {
            addLog("WRITE_BYTE: Aborted, not in a stopped state.")
            return
        }
        
        addLog("Writing byte 0x\(String(format: "%02x", value)) to address 0x\(String(format: "%llx", address))")
        lldbManager.writeByte(at: address, value: value)
        
        // Refresh disassembly after writing to show the change
        await refreshDisassembly()
    }
    
    public func writeBytes(address: UInt64, bytes: [UInt8]) async {
        guard isAttached else {
            addLog("❌ No process available for memory write")
            status = "❌ No process attached"
            return
        }
        
        guard case .stopped = state else {
            addLog("❌ WRITE_BYTES: Process must be stopped to write memory")
            status = "❌ Process must be stopped to write memory"
            return
        }
        
        addLog("⚡ RUNTIME MEMORY PATCH: Writing \(bytes.count) bytes to address 0x\(String(format: "%llx", address))")
        addLog("   Bytes: \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        addLog("   ✅ TEMPORARY: Process memory only, binary file unchanged (like x64dbg)")
        addLog("🎯 Target Process: \(attachedProcessPath ?? "unknown") (PID: \(currentPID))")
        status = "Writing memory..."
        
        // Store original bytes before overwriting (if not already stored)
        if originalBytes[address] == nil {
            // Read current bytes from disassembly if available
            if let currentLine = disassembly.first(where: { $0.address == address }) {
                let hexString = currentLine.bytes.replacingOccurrences(of: " ", with: "")
                var currentBytes: [UInt8] = []
                for i in stride(from: 0, to: hexString.count, by: 2) {
                    let start = hexString.index(hexString.startIndex, offsetBy: i)
                    let end = hexString.index(start, offsetBy: 2)
                    if let byte = UInt8(String(hexString[start..<end]), radix: 16) {
                        currentBytes.append(byte)
                    }
                }
                if !currentBytes.isEmpty {
                    originalBytes[address] = currentBytes
                }
            }
        }
        
        // Track this patch for export
        memoryPatches[address] = bytes
        
        // Write bytes sequentially
        for (offset, byte) in bytes.enumerated() {
            lldbManager.writeByte(at: address + UInt64(offset), value: byte)
        }
        
        // Trigger non-blocking UI update to reflect changes
        triggerDelayedRefresh()
    }
    
    // MARK: - Binary Export (x64dbg style)
    
    public func exportPatchedBinary(to url: URL) async -> Bool {
        guard isAttached else {
            addLog("❌ No process attached for binary export")
            status = "❌ No process attached for binary export"
            return false
        }
        
        guard let processPath = attachedProcessPath else {
            addLog("❌ Could not determine process binary path")
            status = "❌ Could not determine process binary path"
            return false
        }
        
        addLog("🔄 Exporting patched binary from \(processPath) to \(url.path)")
        status = "🔄 Exporting patched binary..."
        
        do {
            // Copy original binary to destination
            let sourceURL = URL(fileURLWithPath: processPath)
            try FileManager.default.copyItem(at: sourceURL, to: url)
            
            addLog("✅ Binary copied successfully")
            
            // Apply patches if any exist
            if !memoryPatches.isEmpty {
                addLog("🔧 Applying \(memoryPatches.count) memory patches to exported binary...")
                let success = await applyPatchesToBinary(at: url)
                if success {
                    addLog("✅ All patches applied successfully to exported binary")
                    status = "✅ Patched binary exported with \(memoryPatches.count) modifications"
                } else {
                    addLog("⚠️ Some patches may not have been applied correctly")
                    status = "⚠️ Binary exported but patch application had issues"
                }
            } else {
                addLog("ℹ️ No memory patches to apply - exported original binary")
                status = "✅ Binary exported (no patches applied)"
            }
            
            return true
        } catch {
            addLog("❌ Export failed: \(error.localizedDescription)")
            status = "❌ Export failed: \(error.localizedDescription)"
            return false
        }
    }
    
    public func getExportFilename() -> String {
        guard let processPath = attachedProcessPath else {
            return "patched_binary"
        }
        
        let nameWithoutExtension = URL(fileURLWithPath: processPath).deletingPathExtension().lastPathComponent
        
        return "\(nameWithoutExtension)_patched"
    }
    
    /// Apply memory patches to a binary file on disk
    private func applyPatchesToBinary(at url: URL) async -> Bool {
        guard !memoryPatches.isEmpty else { 
            addLog("ℹ️ No patches to apply")
            return true 
        }
        
        do {
            // Read the binary file
            var binaryData = try Data(contentsOf: url)
            addLog("📖 Read binary file: \(binaryData.count) bytes")
            
            // Get the base address of the process to calculate file offsets
            guard let baseAddress = await getProcessBaseAddress() else {
                addLog("❌ Could not determine process base address for patch conversion")
                return false
            }
            
            var successfulPatches = 0
            var failedPatches = 0
            
            // Apply each patch
            for (address, patchBytes) in memoryPatches {
                // Convert memory address to file offset
                if let fileOffset = await convertMemoryAddressToFileOffset(address: address, baseAddress: baseAddress) {
                    // Ensure we don't write beyond the file
                    if fileOffset + UInt64(patchBytes.count) <= binaryData.count {
                        // Apply the patch
                        for (i, byte) in patchBytes.enumerated() {
                            binaryData[Int(fileOffset) + i] = byte
                        }
                        successfulPatches += 1
                        addLog("✅ Applied patch at file offset 0x\(String(format: "%llx", fileOffset)) (memory 0x\(String(format: "%llx", address))): \(patchBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
                    } else {
                        failedPatches += 1
                        addLog("❌ Patch at memory 0x\(String(format: "%llx", address)) extends beyond file bounds")
                    }
                } else {
                    failedPatches += 1
                    addLog("❌ Could not convert memory address 0x\(String(format: "%llx", address)) to file offset")
                }
            }
            
            // Write the patched binary back to disk
            try binaryData.write(to: url)
            addLog("💾 Wrote patched binary: \(binaryData.count) bytes")
            addLog("📊 Patch summary: \(successfulPatches) successful, \(failedPatches) failed")
            
            return failedPatches == 0
        } catch {
            addLog("❌ Failed to apply patches to binary: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get the base address of the attached process
    private func getProcessBaseAddress() async -> UInt64? {
        // For now, use a common base address for executables on macOS
        // In a more complete implementation, this would query LLDB for the actual base address
        return 0x100000000  // Common base for 64-bit executables on macOS
    }
    
    /// Convert a memory address to a file offset
    private func convertMemoryAddressToFileOffset(address: UInt64, baseAddress: UInt64) async -> UInt64? {
        // Simple conversion: subtract base address to get file offset
        // This is a basic implementation - a complete version would parse Mach-O headers
        // to properly convert between memory addresses and file offsets
        if address >= baseAddress {
            let offset = address - baseAddress
            addLog("🔄 Converted memory address 0x\(String(format: "%llx", address)) to file offset 0x\(String(format: "%llx", offset))")
            return offset
        } else {
            addLog("⚠️ Memory address 0x\(String(format: "%llx", address)) is below base address 0x\(String(format: "%llx", baseAddress))")
            return nil
        }
    }
    
    // MARK: - Breakpoint Management
    
    public func setBreakpoint(at address: UInt64) async {
        guard isAttached else {
            addLog("No process available for breakpoint")
            return
        }
        
        addLog("🔴 Setting breakpoint at address 0x\(String(format: "%llx", address))")
        
        // Optimistically add to UI (will be confirmed by server response)
        breakpoints.insert(address)
        
        // Track this address as pending breakpoint ID confirmation
        pendingBreakpointAddress = address
        
        // Send command to LLDB server
        lldbManager.sendCommand(command: "setBreakpointAtVirtualAddress", args: ["address": address])
    }
    
    public func removeBreakpoint(at address: UInt64) async {
        guard isAttached else {
            addLog("No process available for breakpoint removal")
            return
        }
        
        guard let bkptId = breakpointIDs[address] else {
            addLog("❌ No breakpoint ID found for address 0x\(String(format: "%llx", address))")
            // Remove from UI anyway in case of inconsistency
            breakpoints.remove(address)
            return
        }
        
        addLog("⚪ Removing breakpoint \(bkptId) at address 0x\(String(format: "%llx", address))")
        
        // Remove from UI immediately for responsiveness
        breakpoints.remove(address)
        breakpointIDs.removeValue(forKey: address)
        
        // Send command to remove specific breakpoint
        lldbManager.sendCommand(command: "removeBreakpoint", args: ["bkpt_id": bkptId])
    }
    
    public func listBreakpoints() async {
        guard isAttached else { return }
        lldbManager.sendCommand(command: "listBreakpoints", args: [:])
    }
    
    public func enableBreakpoint(at address: UInt64) async {
        guard isAttached else { return }
        lldbManager.sendCommand(command: "enableBreakpoint", args: ["address": address])
    }
    
    public func disableBreakpoint(at address: UInt64) async {
        guard isAttached else { return }
        lldbManager.sendCommand(command: "disableBreakpoint", args: ["address": address])
    }
    
    public func refreshRegisters() async {
        guard isAttached else { 
            macdbgLog("❌ refreshRegisters called but not attached", category: .error)
            return 
        }
        macdbgLog("📤 Sending getRegisters command to LLDB", category: .lldb)
        lldbManager.getRegisters()
    }
    public func refreshDisassembly() async {
        guard isAttached, programCounter != 0 else { return }
        let pc = programCounter
        let start: UInt64 = pc > 0x100 ? pc - 0x100 : pc  // Smaller range
        lldbManager.getDisassembly(from: start, count: 150)  // Reduced from 512
    }
    
    /// Force immediate disassembly refresh with UI update
    public func forceDisassemblyRefresh() async {
        // First trigger a fresh disassembly from LLDB
        await refreshDisassembly()
        
        // Fast UI refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.disassemblyUpdateTrigger += 1
            self.objectWillChange.send()
        }
    }
    
    /// Trigger a delayed refresh to avoid main thread blocking
    private func triggerDelayedRefresh() {
        // Schedule refresh on a background queue to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await self.refreshDisassembly()
                
                // Fast UI update on main thread
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.disassemblyUpdateTrigger += 1
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    /// X64DBG-STYLE: Ultra-fast disassembly with smart caching
    public func refreshDisassemblyAroundPC() async {
        guard isAttached, programCounter != 0 else { 
            macdbgLog("❌ refreshDisassemblyAroundPC: isAttached=\(isAttached), PC=0x\(String(format: "%llx", programCounter))", category: .error)
            return 
        }
        let pc = programCounter
        
        // X64DBG OPTIMIZATION: Check buffer first before any network calls
        if let cachedInstructions = getFromInstructionBuffer(around: pc) {
            macdbgLog("⚡ CACHE HIT: Using buffered instructions around PC=0x\(String(format: "%llx", pc))", category: .performance)
            DispatchQueue.main.async {
                self.disassembly = cachedInstructions
            }
            return
        }
        
        macdbgLog("📤 CACHE MISS: Fetching fresh disassembly around PC=0x\(String(format: "%llx", pc))", category: .lldb)
        
        // X64DBG-STYLE: Large buffer fetch for fewer network calls
        let instructionsBefore: UInt64 = 200   // Much larger buffer
        let instructionsAfter: UInt64 = 300    // Even more context
        let start: UInt64 = pc > instructionsBefore * 4 ? pc - instructionsBefore * 4 : 0
        let totalCount = Int(instructionsBefore + instructionsAfter)  // 500 instructions total
        
        macdbgLog("📤 X64DBG-STYLE FETCH: start=0x\(String(format: "%llx", start)), count=\(totalCount)", category: .lldb)
        lldbManager.getDisassembly(from: start, count: totalCount)
    }
    
    // X64DBG-STYLE: Get instructions from buffer like mInstBuffer
    private func getFromInstructionBuffer(around pc: UInt64) -> [DisassemblyLine]? {
        guard !instructionBuffer.isEmpty else { return nil }
        
        // Find PC in buffer
        guard let pcIndex = instructionBuffer.firstIndex(where: { $0.address >= pc }) else {
            return nil
        }
        
        // Extract visible window around PC (like x64dbg)
        let visibleCount = 100
        let startIndex = max(0, pcIndex - visibleCount / 2)
        let endIndex = min(instructionBuffer.count, startIndex + visibleCount)
        
        if endIndex > startIndex {
            return Array(instructionBuffer[startIndex..<endIndex])
        }
        
        return nil
    }
    
    public func getDisassemblyAt(address: UInt64, count: Int = 100) async {  // Reduced default
        guard isAttached else { return }
        lldbManager.getDisassembly(from: address, count: count)
    }
    
    /// Navigate to a specific address (for jump following)
    public func navigateToAddress(_ address: UInt64) async {
        guard isAttached else { return }
        addLog("🎯 Navigating to address: \(String(format: "0x%llx", address))")
        
        // Set a temporary navigation target to trigger focus
        DispatchQueue.main.async {
            self.navigationTarget = address
        }
        
        await getDisassemblyAt(address: address, count: 100)
    }
    
    public func expandDisassemblyRange(direction: DisassemblyDirection) async {
        guard isAttached, !disassembly.isEmpty else { return }
        
        let count = 128
        switch direction {
        case .backward:
            if let firstAddress = disassembly.first?.address, firstAddress > UInt64(count * 8) {
                let newStart = firstAddress - UInt64(count * 8)
                addLog("Expanding disassembly backward from: \(String(format: "0x%llx", newStart))")
                lldbManager.getDisassembly(from: newStart, count: count)
            }
        case .forward:
            if let lastAddress = disassembly.last?.address {
                let newStart = lastAddress + 1
                addLog("Expanding disassembly forward from: \(String(format: "0x%llx", newStart))")
                lldbManager.getDisassembly(from: newStart, count: count)
            }
        }
    }
    // ... (rest of the class remains the same)
    private func isProtectedProcess(pid: pid_t) async -> Bool {
        // Block a tiny set by well-known names
        let hardBlockedNames: Set<String> = ["kernel_task", "launchd", "WindowServer"]
        if let app = NSRunningApplication(processIdentifier: pid) {
            if let name = app.localizedName, hardBlockedNames.contains(name) {
                addLog("Blocking attach to critical system process: \(name)")
                return true
            }
            // Block system apps/binaries under /System to avoid SIP/TCC failures (e.g., Calculator)
            if let url = app.bundleURL, url.path.starts(with: "/System") { return true }
            if let url = app.executableURL, url.path.starts(with: "/System") { return true }
        }
        return false
    }
    
    // MARK: - LLDBManagerDelegate
    
    func lldbManagerDidAttach() {
        DispatchQueue.main.async {
            self.isAttached = true
            // Most of the time, attaching stops the process immediately.
            // We'll wait for the first 'stopped' event to confirm.
            self.addLog("Attach confirmed by server. Waiting for initial stop event.")
            // Proactively request an async interrupt shortly after attach
            // to guarantee we reach a stopped state and can fetch PC/regs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.addLog("Forcing stop and immediate report of PC/regs...")
                self.lldbManager.forceStopAndReport()
            }
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
            self.addLog("Detach confirmed.")
        }
    }
    
    func lldbManagerDidStop(event: LLDBStoppedEvent) {
        DispatchQueue.main.async {
            macdbgLog("📥 RECEIVED STOP EVENT: reason=\(event.reason), pc=0x\(String(format: "%llx", event.pc)), threadId=\(event.threadId)", category: .lldb)
            macdbgLog("🔄 Processing stop event on main thread", category: .threading)
            
            let oldPC = self.programCounter
            self.state = .stopped(reason: event.reason)
            
            // CRITICAL: Set PC FIRST, then refresh disassembly
            self.programCounter = event.pc
            
            // If this is from a launch, mark as attached
            if event.reason == "launched" {
                macdbgLog("✅ LAUNCH STOP EVENT: Marking as attached", category: .launch)
                self.isAttached = true
                
                // CLEAR CACHE for new binary
                self.disassemblyCache.removeAll()
                self.lastCachedRange = nil
                self.requestThrottle = Date.distantPast
                
                self.addLog("🚀 LAUNCHED BINARY STOPPED: Process is now attached and ready for debugging")
                self.addLog("🎯 PC at entry point: \(String(format: "0x%llx", event.pc))")
                
                // CRITICAL: Force stop after launch to ensure we can get disassembly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {  // Even faster
                    self.lldbManager.forceStopAndReport()
                }
            } else {
                self.addLog("🚀 STEP COMPLETE: PC \(String(format: "0x%llx", oldPC)) → \(String(format: "0x%llx", event.pc))")
            }
            
            macdbgLog("🎯 Selecting thread ID: \(event.threadId)", category: .lldb)
            // Ensure LLDB selects the correct thread
            self.lldbManager.selectThreadID(event.threadId)
            
            macdbgLog("🔄 Starting async refresh of registers and disassembly", category: .ui)
            // IMMEDIATELY refresh disassembly around new PC for reliable focus
            Task {
                macdbgLog("📊 Refreshing registers", category: .ui)
                await self.refreshRegisters()
                
                macdbgLog("📋 Refreshing disassembly", category: .ui)
                await self.refreshDisassemblyAroundPC()
                
                macdbgLog("✅ Stop event processing completed", category: .lldb)
            }
        }
    }
    
    func lldbManagerDidReceiveRegisters(response: LLDBRegistersResponse) {
        DispatchQueue.main.async {
            macdbgLog("📥 RECEIVED REGISTERS: \(response.registers.count) registers", category: .lldb)
            self.registers = response.registers
            self.addLog("Registers updated (\(response.registers.count) registers).")
            macdbgLog("✅ Registers UI updated", category: .ui)
        }
    }

    func lldbManagerDidReceiveDisassembly(response: LLDBDisassemblyResponse) {
        // X64DBG OPTIMIZATION: Process in background, update UI once
        instructionQueue.async {
            macdbgLog("📥 X64DBG-STYLE PROCESSING: \(response.lines.count) lines", category: .lldb)
            
            // Update instruction buffer like x64dbg's mInstBuffer
            self.updateInstructionBuffer(with: response.lines)
            
            // PERFORMANCE: Cache in background
            for line in response.lines {
                self.disassemblyCache[line.address] = line
            }
            
            // Update cached range
            if let firstLine = response.lines.first, let lastLine = response.lines.last {
                self.lastCachedRange = (start: firstLine.address, end: lastLine.address)
            }
            
            // Single UI update with optimized data
            DispatchQueue.main.async {
                self.disassembly = self.getVisibleInstructions()
                let newLines = response.lines
                macdbgLog("⚡ X64DBG-STYLE CACHED: \(newLines.count) lines in buffer", category: .performance)
            if newLines.count > 0 {
                let firstAddr = String(format: "0x%llx", newLines.first!.address)
                let lastAddr = String(format: "0x%llx", newLines.last!.address)
                self.addLog("   Range: \(firstAddr) to \(lastAddr)")
                
                macdbgLog("📊 Disassembly range: \(firstAddr) to \(lastAddr)", category: .lldb)
                
                // Sample a few instructions to see what we have
                let sampleCount = min(5, newLines.count)
                for i in 0..<sampleCount {
                    let line = newLines[i]
                    self.addLog("   [\(i)]: \(line.instruction) \(line.operands) (bytes: \(line.bytes))")
                }
                
                // CRITICAL: Check for conditional jumps to debug the issue
                let conditionalJumps = newLines.filter { line in
                    let inst = line.instruction.lowercased()
                    return inst.hasPrefix("j") && inst != "jmp" && inst != "jmpq"
                }
                if !conditionalJumps.isEmpty {
                    self.addLog("🚨 FOUND CONDITIONAL JUMPS:")
                    for jump in conditionalJumps.prefix(3) {
                        self.addLog("   - \(jump.formattedAddress): \(jump.instruction) \(jump.operands) (bytes: \(jump.bytes))")
                    }
                } else {
                    self.addLog("ℹ️ No conditional jumps found in this disassembly range")
                }
            } else {
                macdbgLog("⚠️ Received empty disassembly response!", category: .error)
            }
            
            if self.disassembly.isEmpty {
                self.disassembly = newLines
                self.addLog("🔄 Fresh disassembly set with \(newLines.count) lines")
            } else {
                // Merge and sort by address, removing duplicates
                var mergedLines = self.disassembly
                var addedCount = 0
                var replacedCount = 0
                
                for newLine in newLines {
                    if let existingIndex = mergedLines.firstIndex(where: { $0.address == newLine.address }) {
                        // Replace existing line with new one (important for after memory writes!)
                        let oldLine = mergedLines[existingIndex]
                        mergedLines[existingIndex] = newLine
                        replacedCount += 1
                        
                        // Debug log replacements of conditional jumps
                        if oldLine.instruction.lowercased().hasPrefix("j") || newLine.instruction.lowercased().hasPrefix("j") {
                            self.addLog("🔄 REPLACED at \(newLine.formattedAddress): '\(oldLine.instruction)' → '\(newLine.instruction)' (bytes: \(oldLine.bytes) → \(newLine.bytes))")
                        }
                    } else {
                        mergedLines.append(newLine)
                        addedCount += 1
                    }
                }
                let sortedLines = mergedLines.sorted { $0.address < $1.address }
                self.disassembly = sortedLines
                self.addLog("🔄 Merged disassembly: added \(addedCount), replaced \(replacedCount), total \(self.disassembly.count)")
                
                // Force immediate UI update after disassembly change
                self.disassemblyUpdateTrigger += 1
                self.objectWillChange.send()
                
                // Additional force update to ensure SwiftUI recognizes the change
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
                
                self.addLog("🔄 Triggered immediate UI update after disassembly merge (trigger: \(self.disassemblyUpdateTrigger))")
            }
            
            // Ensure the current PC is present; if not, request a focused window at PC.
            if self.programCounter != 0 && !self.disassembly.contains(where: { $0.address == self.programCounter }) {
                self.addLog("⚠️ PC not in current disassembly window. Requesting focused disassembly at PC...")
                Task { await self.refreshDisassemblyAroundPC() }
            } else {
                self.addLog("Disassembly updated. Total instructions: \(self.disassembly.count)")
            }
        }
    }

    func lldbManagerDidReceiveMemory(response: LLDBMemoryResponse) {
        DispatchQueue.main.async {
            self.memory = response.lines
            self.addLog("Memory updated.")
        }
    }
    
    func lldbManagerDidReceiveError(error: LLDBErrorEvent) {
        DispatchQueue.main.async {
            self.state = .error(error.message)
            self.addLog("Received error from debugger: \(error.message)")
        }
    }
    
    func lldbManagerDidReceiveBreakpointResponse(response: [String: Any]) {
        DispatchQueue.main.async {
            // Handle breakpoint creation/removal responses
            guard let bkptId = response["bkpt_id"] as? Int else { return }
            
            // Find which address this breakpoint ID corresponds to
            if let address = self.pendingBreakpointAddress {
                self.breakpointIDs[address] = bkptId
                self.addLog("✅ Breakpoint \(bkptId) confirmed for address 0x\(String(format: "%llx", address))")
                self.pendingBreakpointAddress = nil
            }
        }
    }
    
    func lldbManagerDidReceiveWriteByteResponse(success: Bool, error: String?) {
        DispatchQueue.main.async {
            if success {
                // Memory patch successful - refresh disassembly to show changes
                Task {
                    await self.refreshDisassemblyAroundPC()
                }
            } else {
                self.addLog("❌ Memory patch failed: \(error ?? "Unknown error")")
            }
        }
    }
    
    // MARK: - Binary Path Resolution
    
    /// Resolve the actual executable path from an app bundle or return the original path
    private func resolveExecutablePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        
        // Check if this is an app bundle
        if url.pathExtension.lowercased() == "app" {
            macdbgLog("Detected app bundle: \(path)", category: .launch)
            
            // Look for Info.plist to get executable name
            let infoPlistPath = url.appendingPathComponent("Contents/Info.plist").path
            if FileManager.default.fileExists(atPath: infoPlistPath) {
                if let plistData = FileManager.default.contents(atPath: infoPlistPath),
                   let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                   let executableName = plist["CFBundleExecutable"] as? String {
                    
                    let executablePath = url.appendingPathComponent("Contents/MacOS/\(executableName)").path
                    macdbgLog("Found executable in Info.plist: \(executableName)", category: .launch)
                    macdbgLog("Full executable path: \(executablePath)", category: .launch)
                    
                    if FileManager.default.fileExists(atPath: executablePath) {
                        return executablePath
                    } else {
                        macdbgLog("⚠️ Executable not found at expected path: \(executablePath)", category: .error)
                    }
                }
            }
            
            // Fallback: try to guess executable name from app name
            let appName = url.deletingPathExtension().lastPathComponent
            let fallbackPath = url.appendingPathComponent("Contents/MacOS/\(appName)").path
            macdbgLog("Trying fallback executable path: \(fallbackPath)", category: .launch)
            
            if FileManager.default.fileExists(atPath: fallbackPath) {
                return fallbackPath
            }
            
            macdbgLog("⚠️ Could not resolve executable in app bundle, using original path", category: .error)
        }
        
        return path
    }
    
    // MARK: - Binary Launching (Safe - Original File Untouched)
    
    /// Launch a binary file (creates NEW process, original file untouched)
    public func launchBinary(path: String, arguments: [String] = []) async {
        macdbgLog("🚀 LAUNCH BINARY INITIATED", category: .launch)
        macdbgLog("Binary path: \(path)", category: .launch)
        macdbgLog("Arguments: \(arguments)", category: .launch)
        macdbgLog("Current working directory: \(FileManager.default.currentDirectoryPath)", category: .launch)
        
        // Handle app bundles - extract the actual executable
        let actualExecutablePath = resolveExecutablePath(path)
        macdbgLog("Resolved executable path: \(actualExecutablePath)", category: .launch)
        
        if actualExecutablePath != path {
            addLog("📦 App bundle detected: \(path)")
            addLog("🎯 Actual executable: \(actualExecutablePath)")
        }
        
        addLog("🚀 LAUNCHING BINARY: \(path)")
        addLog("✅ SAFE: This creates a NEW process, original file remains untouched")
        addLog("🛑 STOP AT ENTRY: Will stop at main/entry point for debugging")
        
        // Store the original path for reference, but use actual executable for LLDB
        attachedProcessPath = path
        
        macdbgLog("Setting state to attaching", category: .launch)
        // Update state to indicate launching
        state = .attaching(0) // Use 0 as placeholder PID for launching
        
        macdbgLog("Sending prepareExecutable command with resolved path", category: .launch)
        // Step 1: Prepare executable (use actual executable path, not app bundle)
        lldbManager.sendCommand(command: "prepareExecutable", args: [
            "path": actualExecutablePath,
            "is64Bits": true,
            "cwd": FileManager.default.currentDirectoryPath,
            "args": arguments
        ])
        
        macdbgLog("Scheduling createProcess command", category: .launch)
        // Step 2: Create process after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            macdbgLog("Executing createProcess command", category: .launch)
            self.addLog("🔄 Creating process...")
            self.lldbManager.sendCommand(command: "createProcess", args: [:])
        }
        
        macdbgLog("Launch binary sequence initiated successfully", category: .launch)
    }
    
    // MARK: - Memory Operations (Runtime Patches like x64dbg)
    
    func lldbManagerDidReceiveWriteByteResponse(success: Bool, error: String?) async {
        if success {
            addLog("✅ Memory write successful (PROCESS MEMORY ONLY)")
            addLog("🔒 Binary file on disk remains UNCHANGED - this is memory-only like x64dbg")
            status = "✅ Memory patched (file safe)"
            // Note: Refresh is now handled by the timed refresh in writeBytes for better reliability
        } else {
            let errorMsg = error ?? "Unknown error"
            addLog("❌ Memory write failed: \(errorMsg)")
            status = "❌ Memory write failed: \(errorMsg)"
        }
    }
    
    private func updateStatus(from state: DebuggerState) {
        switch state {
        case .idle:
            self.status = "Ready"
        case .attaching(let pid):
            self.status = "Attaching to PID \(pid)..."
        case .running:
            self.status = "Running..."
        case .stepping:
            self.status = "Stepping..."
        case .continuing:
            self.status = "Continuing..."
        case .stopped(let reason):
            self.status = "✅ Stopped (reason: \(reason))"
        case .detaching:
            self.status = "Detaching..."
        case .error(let message):
            self.status = "❌ Error: \(message)"
        }
    }
}

// MARK: - Error Types

enum DebuggerError: LocalizedError {
    case attachFailed(String)
    case invalidProcess
    
    var errorDescription: String? {
        switch self {
        case .attachFailed(let message):
            return "Attach failed: \(message)"
        case .invalidProcess:
            return "Invalid or inaccessible process"
        }
    }
}


// MARK: - Extensions

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - X64DBG-Style Instruction Buffer Management

extension DebuggerController {
    
    /// X64DBG-STYLE: Update instruction buffer efficiently like mInstBuffer
    private func updateInstructionBuffer(with newInstructions: [DisassemblyLine]) {
        guard let firstInstr = newInstructions.first, let lastInstr = newInstructions.last else { return }
        
        let newStart = firstInstr.address
        let newEnd = lastInstr.address
        
        // Smart merge strategy like x64dbg
        if instructionBuffer.isEmpty || 
           newStart < bufferBaseAddress || 
           newEnd > bufferBaseAddress + UInt64(bufferSize * 8) {
            // Replace with new buffer
            instructionBuffer = newInstructions
            bufferBaseAddress = newStart
            bufferSize = newInstructions.count
            macdbgLog("🔄 X64DBG BUFFER REPLACE: base=0x\(String(format: "%llx", newStart)), size=\(newInstructions.count)", category: .performance)
        } else {
            // Merge efficiently
            mergeInstructionsIntoBuffer(newInstructions)
        }
        
        // Maintain reasonable buffer size like x64dbg
        if instructionBuffer.count > maxBufferSize {
            let trimStart = instructionBuffer.count - maxBufferSize
            instructionBuffer = Array(instructionBuffer[trimStart...])
            if let firstKept = instructionBuffer.first {
                bufferBaseAddress = firstKept.address
            }
            bufferSize = instructionBuffer.count
            macdbgLog("✂️ X64DBG BUFFER TRIM: kept \(maxBufferSize) instructions", category: .performance)
        }
    }
    
    private func mergeInstructionsIntoBuffer(_ newInstructions: [DisassemblyLine]) {
        // Add new instructions not already in buffer
        var added = 0
        for newInstr in newInstructions {
            if !instructionBuffer.contains(where: { $0.address == newInstr.address }) {
                instructionBuffer.append(newInstr)
                added += 1
            }
        }
        
        // Sort by address to maintain order
        instructionBuffer.sort { $0.address < $1.address }
        bufferSize = instructionBuffer.count
        
        if added > 0 {
            macdbgLog("🔀 X64DBG BUFFER MERGE: added \(added) new instructions, total=\(bufferSize)", category: .performance)
        }
    }
    
    /// X64DBG-STYLE: Get visible instructions optimized for UI
    private func getVisibleInstructions() -> [DisassemblyLine] {
        guard !instructionBuffer.isEmpty else { return [] }
        
        let pc = programCounter
        let visibleCount = 200  // Good balance of context and performance
        
        // Find PC position in buffer
        if let pcIndex = instructionBuffer.firstIndex(where: { $0.address >= pc }) {
            let startIndex = max(0, pcIndex - visibleCount / 2)
            let endIndex = min(instructionBuffer.count, startIndex + visibleCount)
            let visible = Array(instructionBuffer[startIndex..<endIndex])
            macdbgLog("👁️ X64DBG VISIBLE: showing \(visible.count) instructions around PC", category: .ui)
            return visible
        }
        
        // Fallback: show recent instructions
        let startIndex = max(0, instructionBuffer.count - visibleCount)
        let fallback = Array(instructionBuffer[startIndex...])
        macdbgLog("👁️ X64DBG FALLBACK: showing \(fallback.count) recent instructions", category: .ui)
        return fallback
    }
}

// MARK: - Breakpoint Management Extension (x64dbg style)

extension DebuggerController {
    
    /// Toggle breakpoint at address (double-click behavior like x64dbg)
    public func toggleBreakpoint(at address: UInt64) async {
        guard isAttached else { return }
        
        if breakpoints.contains(address) {
            // Remove existing breakpoint
            await removeBreakpoint(at: address)
        } else {
            // Add new breakpoint
            await setBreakpoint(at: address)
        }
    }
    
    /// Check if address has breakpoint (for UI red dots)
    public func hasBreakpoint(at address: UInt64) -> Bool {
        return breakpoints.contains(address)
    }
    
    /// Clear all breakpoints on detach
    public func clearAllBreakpoints() {
        breakpoints.removeAll()
        breakpointIDs.removeAll()
        pendingBreakpointAddress = nil
        addLog("🗑️ Cleared all breakpoints")
    }
}

