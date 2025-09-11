import SwiftUI

struct DisassemblyView_Basic: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    
    @State private var selectedAddresses: Set<UInt64> = []
    
    var body: some View {
        VStack {
            Text("Disassembly")
                .font(.headline)
                .padding()
            
            if !selectedAddresses.isEmpty {
                Button("🤖 Send to AI Chat") {
                    sendToAI()
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            
            List(debugger.disassembly, id: \.address) { line in
                Text("\(line.formattedAddress) \(line.instruction) \(line.operands)")
                    .font(.system(.caption, design: .monospaced))
                    .background(selectedAddresses.contains(line.address) ? Color.blue.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        if selectedAddresses.contains(line.address) {
                            selectedAddresses.remove(line.address)
                        } else {
                            selectedAddresses.insert(line.address)
                        }
                    }
                    .contextMenu {
                        if !selectedAddresses.isEmpty {
                            Button("🤖 Send to AI Chat") {
                                sendToAI()
                            }
                        }
                    }
            }
        }
        .onKeyPress(.init("l")) {
            sendToAI()
            return .handled
        }
    }
    
    private func sendToAI() {
        guard !selectedAddresses.isEmpty else { return }
        
        let selectedLines = debugger.disassembly.filter { selectedAddresses.contains($0.address) }
        
        if !selectedLines.isEmpty {
            Task {
                let suggestion = await aiManager.analyzeCodeWithContext(
                    code: selectedLines.map { line in
                        "\(line.formattedAddress) \(line.instruction) \(line.operands)"
                    }.joined(separator: "\n"),
                    question: "Analyze this code:",
                    context: "Selected disassembly lines"
                )
                
                await MainActor.run {
                    aiManager.addSuggestion(suggestion)
                }
            }
        }
    }
}
