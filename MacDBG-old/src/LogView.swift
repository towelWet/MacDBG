import SwiftUI
import AppKit

struct LogView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Debug Log")
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                Button("Copy All") {
                    let all = debugger.logs.joined(separator: "\n")
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(all, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Test Log") {
                    debugger.addManualLog("Test log from UI")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear") {
                    debugger.clearLogs()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.trailing)
            }
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollViewReader { proxy in
                if debugger.logs.isEmpty {
                    VStack(alignment: .center) {
                        Text("No logs yet")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Single multi-line selectable text makes copying ranges easy
                    ScrollView {
                        Text(debugger.logs.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .id("joined-log")
                    }
                    .onChange(of: debugger.logs.count) { _ in
                        if !debugger.logs.isEmpty {
                            proxy.scrollTo("joined-log", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct StatusView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(debugger.isAttached ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text(debugger.status)
                    .font(.caption)
                    .lineLimit(2)
            }
            
            if debugger.isAttached {
                Text("PID: \(debugger.currentPID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}
