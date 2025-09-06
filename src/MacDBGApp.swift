import SwiftUI
import UniformTypeIdentifiers

@main
struct MacDBGApp: App {
    @StateObject private var debugger = DebuggerController()

    var body: some Scene {
        WindowGroup("MacDBG - Professional macOS Debugger") {
            ContentView()
                .environmentObject(debugger)
                .frame(minWidth: 1400, minHeight: 900)
                .onAppear {
                    // Initialize logging system
                    macdbgLog("🚀 X64DBG-OPTIMIZED MacDBG App Started", category: .system)
                    
                    // Set up crash detection
                    NSSetUncaughtExceptionHandler { exception in
                        macdbgLog("🚨 UNCAUGHT EXCEPTION: \(exception)", category: .crash)
                        _ = LoggingSystem.shared.exportLogs()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    macdbgLog("🛑 App terminating", category: .system)
                    debugger.cleanup()
                    
                    // Export final logs
                    let logURL = LoggingSystem.shared.exportLogs()
                    macdbgLog("📋 Final logs exported to: \(logURL.path)", category: .system)
                }
        }
        .commands {
            MacDBGCommands()
        }
    }
}


// Custom Notification for menu actions
extension Notification.Name {
    static let startDebug = Notification.Name("StartDebug")
    static let stepInto = Notification.Name("StepInto")
    static let stepOver = Notification.Name("StepOver")
    static let continueExecution = Notification.Name("ContinueExecution")
    static let selectAll = Notification.Name("selectAll")
    static let exportPatchedBinary = Notification.Name("ExportPatchedBinary")
}

struct MacDBGCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Export Patched Binary...") {
                NotificationCenter.default.post(name: .exportPatchedBinary, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Start Debugging") {
                NotificationCenter.default.post(name: .startDebug, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift]) // Shift+Cmd+R

            Divider()

            Button("Step Into") {
                NotificationCenter.default.post(name: .stepInto, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(Unicode.Scalar(NSF7FunctionKey)!)), modifiers: [])

            Button("Step Over") {
                NotificationCenter.default.post(name: .stepOver, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(Unicode.Scalar(NSF8FunctionKey)!)), modifiers: [])
            
            Button("Continue") {
                NotificationCenter.default.post(name: .continueExecution, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(Unicode.Scalar(NSF9FunctionKey)!)), modifiers: [])
        }
        
        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                NotificationCenter.default.post(name: .selectAll, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
    }
}
