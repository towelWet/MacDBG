import SwiftUI

struct AIChatView: View {
    @ObservedObject var aiManager: AIModelManager
    @State private var messageText = ""
    @State private var selectedLines: [DisassemblyLine] = []
    @State private var isWaitingForResponse = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.blue)
                Text("AI Chat")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear Chat") {
                    aiManager.clearSuggestions()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if aiManager.aiSuggestions.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                
                                Text("Start a conversation with AI")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("Select code lines and press Cmd+L, or type a message below")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(aiManager.aiSuggestions.reversed(), id: \.id) { suggestion in
                                ChatMessageView(suggestion: suggestion)
                                    .id(suggestion.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: aiManager.aiSuggestions.count) { _ in
                    if let lastSuggestion = aiManager.aiSuggestions.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastSuggestion.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Selected Lines Preview
            if !selectedLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Selected Lines (\(selectedLines.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Clear") {
                            selectedLines.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedLines, id: \.address) { line in
                                Text("\(line.formattedAddress) \(line.instruction)")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 60)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            // Input Area
            VStack(spacing: 8) {
                HStack {
                    SimpleChatTextField(
                        text: $messageText,
                        placeholder: "Ask AI about the code...",
                        onSend: {
                            sendMessage()
                        }
                    )
                    .focused($isTextFieldFocused)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWaitingForResponse)
                }
                
                // Quick Actions
                HStack {
                    Button("Explain Code") {
                        messageText = "Explain this code:"
                        sendMessage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Find Bugs") {
                        messageText = "Find potential bugs in this code:"
                        sendMessage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Optimize") {
                        messageText = "Suggest optimizations for this code:"
                        sendMessage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    if isWaitingForResponse {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("AI is thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onAppear {
            // Sync with AI manager's chat input when view appears
            if !aiManager.chatInput.isEmpty {
                messageText = aiManager.chatInput
                aiManager.chatInput = "" // Clear after using
            }
        }
        .onChange(of: aiManager.chatInput) { newValue in
            // Update messageText when AI manager sets new chat input
            if !newValue.isEmpty {
                messageText = newValue
                aiManager.chatInput = "" // Clear after using
                isTextFieldFocused = true // Focus the text field
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let message = messageText
        messageText = ""
        isWaitingForResponse = true
        
        Task {
            let suggestion: AISuggestion
            
            if !selectedLines.isEmpty {
                // Analyze selected lines
                let codeContext = selectedLines.map { line in
                    "\(line.formattedAddress) \(line.instruction) \(line.operands)"
                }.joined(separator: "\n")
                
                suggestion = await aiManager.analyzeCodeWithContext(
                    code: codeContext,
                    question: message,
                    context: "Selected disassembly lines"
                )
            } else {
                // General question
                suggestion = await aiManager.askQuestion(message)
            }
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                selectedLines.removeAll()
                isWaitingForResponse = false
            }
        }
    }
    
    func addSelectedLines(_ lines: [DisassemblyLine]) {
        selectedLines.append(contentsOf: lines)
    }
    
    func clearSelectedLines() {
        selectedLines.removeAll()
    }
}

struct ChatMessageView: View {
    let suggestion: AISuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: suggestionTypeIcon)
                    .foregroundColor(suggestionTypeColor)
                
                Text(suggestion.type.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(suggestionTypeColor)
                
                Spacer()
                
                Text(suggestion.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(suggestion.content)
                .font(.body)
                .textSelection(.enabled)
            
            if !suggestion.codeSnippet.isEmpty {
                Text(suggestion.codeSnippet)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var suggestionTypeIcon: String {
        switch suggestion.type {
        case .userMessage:
            return "person.circle.fill"
        case .aiResponse:
            return "brain.head.profile"
        case .instructionComment:
            return "arrow.right.circle"
        case .codeAnalysis:
            return "magnifyingglass"
        case .comment:
            return "text.bubble"
        case .bugDetection:
            return "exclamationmark.triangle"
        case .optimization:
            return "speedometer"
        case .breakpointSuggestion:
            return "stop.circle"
        case .registerExplanation:
            return "cpu"
        case .registerAnalysis:
            return "cpu"
        case .memoryAnalysis:
            return "memorychip"
        case .vulnerability:
            return "exclamationmark.triangle"
        case .general:
            return "message"
        }
    }
    
    private var suggestionTypeColor: Color {
        switch suggestion.type {
        case .userMessage:
            return .blue
        case .aiResponse:
            return .purple
        case .instructionComment:
            return .blue
        case .codeAnalysis:
            return .green
        case .comment:
            return .green
        case .bugDetection:
            return .red
        case .optimization:
            return .orange
        case .breakpointSuggestion:
            return .purple
        case .registerExplanation:
            return .cyan
        case .registerAnalysis:
            return .orange
        case .memoryAnalysis:
            return .indigo
        case .vulnerability:
            return .red
        case .general:
            return .primary
        }
    }
}

// SimpleChatTextField is defined in AIChatView_Enhanced.swift

struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        AIChatView(aiManager: AIModelManager())
            .frame(width: 400, height: 600)
    }
}
