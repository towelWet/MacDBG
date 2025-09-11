import Foundation
import SwiftUI

@MainActor
public class MinimalDebuggerController: ObservableObject {
    @Published public var isAttached = false
    @Published public var logs: [String] = []
    @Published public var status: String = "Ready"
    
    public init() {
        addLog("Minimal debugger initialized")
    }
    
    public func addLog(_ message: String) {
        logs.append("[\(Date())] \(message)")
    }
    
    public func addManualLog(_ message: String) {
        addLog("👤 \(message)")
    }
    
    public func clearLogs() {
        logs.removeAll()
        addLog("🧹 Logs cleared")
    }
    
    public func attach(to pid: pid_t) async {
        addLog("🎯 Attaching to PID: \(pid)")
        isAttached = true
        status = "Attached to PID \(pid)"
    }
    
    public func detach() {
        addLog("🔌 Detaching from process")
        isAttached = false
        status = "Ready"
    }
}
