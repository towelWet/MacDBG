import SwiftUI

struct DebugControlsView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Controls")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button(action: { Task { await debugger.stepInto() } }) {
                        Image(systemName: "arrow.right.to.line")
                    }
                    .help("Step Into")
                    .disabled(!debugger.isAttached)

                    Button(action: { Task { await debugger.stepOver() } }) {
                        Image(systemName: "arrowshape.turn.up.right")
                    }
                    .help("Step Over")
                    .disabled(!debugger.isAttached)

                    Button(action: { Task { await debugger.stepOut() } }) {
                        Image(systemName: "arrow.uturn.left.circle")
                    }
                    .help("Step Out")
                    .disabled(!debugger.isAttached)

                    Button(action: { Task { await debugger.continueExecution() } }) {
                        Image(systemName: "play.circle")
                    }
                    .help("Continue")
                    .disabled(!debugger.isAttached)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                
                Button(action: {
                    debugger.detach()
                }) {
                    Label("Detach", systemImage: "stop.circle")
                        .foregroundColor(.red)
                }
                .disabled(!debugger.isAttached)
                .buttonStyle(.bordered)
            }
            
            if debugger.isAttached {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target: PID \(debugger.currentPID)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
}
