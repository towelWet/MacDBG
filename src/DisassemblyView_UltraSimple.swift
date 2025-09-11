import SwiftUI

struct DisassemblyView_UltraSimple: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    
    var body: some View {
        VStack {
            Text("Disassembly")
            
            Button("Send to AI") {
                sendToAI()
            }
            
            Text("AI Chat functionality added")
        }
    }
    
    private func sendToAI() {
        Task {
            let suggestion = await aiManager.analyzeCodeWithContext(
                code: "Sample disassembly code",
                question: "Analyze this code:",
                context: "Test context"
            )
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
            }
        }
    }
}
