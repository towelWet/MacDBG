import SwiftUI

struct DisassemblyView_Minimal: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    
    @State private var selectedAddresses: Set<UInt64> = []
    
    var body: some View {
        VStack {
            // Simple toolbar
            HStack {
                Text("Disassembly")
                    .font(.headline)
                
                Spacer()
                
                if !selectedAddresses.isEmpty {
                    Button("🤖 Send to AI Chat") {
                        sendToAI()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            
            Divider()
            
            // Simple list
            List(debugger.disassembly, id: \.address) { line in
                HStack {
                    Text(line.formattedAddress)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    Text(line.bytes)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .leading)
                    
                    Text(line.instruction)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 80, alignment: .leading)
                    
                    Text(line.operands)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
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

struct DisassemblyView_Minimal_Previews: PreviewProvider {
    static var previews: some View {
        DisassemblyView_Minimal(
            debugger: DebuggerController(),
            aiManager: AIModelManager()
        )
    }
}
