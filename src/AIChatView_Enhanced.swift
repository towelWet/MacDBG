import SwiftUI

struct AIChatView_Enhanced: View {
    @ObservedObject var aiManager: AIModelManager
    @State private var messageText = ""
    @State private var isWaitingForResponse = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with ChatGPT-style branding
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.white)
                        .font(.title2)
                    Text("AI Assistant")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                
                Spacer()
                
                Button(action: {
                    aiManager.clearSuggestions()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Chat Messages - ChatGPT style
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if aiManager.aiSuggestions.isEmpty {
                            // Welcome message
                            VStack(spacing: 16) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue.opacity(0.6))
                                
                                VStack(spacing: 8) {
                                    Text("Welcome to AI Assistant")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("I can help you analyze disassembly code, explain instructions, find bugs, and suggest optimizations.")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                // Quick start buttons
                                VStack(spacing: 8) {
                                    Text("Quick Start")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 12) {
                                        QuickActionButton(
                                            icon: "arrow.right.circle",
                                            title: "Explain Code",
                                            color: .blue
                                        ) {
                                            messageText = "Explain this disassembly code:"
                                            sendMessage()
                                        }
                                        
                                        QuickActionButton(
                                            icon: "exclamationmark.triangle",
                                            title: "Find Bugs",
                                            color: .red
                                        ) {
                                            messageText = "Find potential bugs in this code:"
                                            sendMessage()
                                        }
                                        
                                        QuickActionButton(
                                            icon: "speedometer",
                                            title: "Optimize",
                                            color: .orange
                                        ) {
                                            messageText = "Suggest optimizations for this code:"
                                            sendMessage()
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            // Chat messages
                            ForEach(aiManager.aiSuggestions, id: \.id) { suggestion in
                                ChatMessageBubble(suggestion: suggestion)
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
            
            // Input Area - ChatGPT style
            VStack(spacing: 12) {
                // Typing indicator
                if isWaitingForResponse {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("AI is thinking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                // Input field with send button
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        SimpleChatTextField(
                            text: $messageText,
                            placeholder: "Message AI Assistant...",
                            onSend: {
                                if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sendMessage()
                                }
                            }
                        )
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isTextFieldFocused ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWaitingForResponse)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        print("🤖 [AIChatView] Sending message: \(message)")
        messageText = ""
        isWaitingForResponse = true
        
        // Add user message to chat
        let userMessage = AISuggestion(
            type: .userMessage,
            title: "You",
            content: message,
            timestamp: Date()
        )
        aiManager.addSuggestion(userMessage)
        
        Task {
            print("🤖 [AIChatView] Calling aiManager.askQuestion...")
            let suggestion = await aiManager.askQuestion(message)
            print("🤖 [AIChatView] Received suggestion: \(suggestion.title)")
            
            await MainActor.run {
                print("🤖 [AIChatView] Adding AI response to array...")
                aiManager.addSuggestion(suggestion)
                print("🤖 [AIChatView] Suggestions count: \(aiManager.aiSuggestions.count)")
                isWaitingForResponse = false
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(width: 80, height: 60)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// Simple chat text field that handles Shift+Enter vs Enter properly
struct SimpleChatTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.backgroundColor = NSColor.clear
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text {
            let selectedRange = nsView.selectedRange()
            nsView.string = text
            nsView.setSelectedRange(selectedRange)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SimpleChatTextField
        
        init(_ parent: SimpleChatTextField) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift is currently pressed
                if NSEvent.modifierFlags.contains(.shift) {
                    // Shift+Enter: Insert newline at cursor position
                    let selectedRange = textView.selectedRange()
                    textView.insertText("\n", replacementRange: selectedRange)
                    return true
                } else {
                    // Enter only: Send message
                    DispatchQueue.main.async {
                        self.parent.onSend()
                    }
                    return true
                }
            }
            return false
        }
    }
}

struct ChatMessageBubble: View {
    let suggestion: AISuggestion
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar based on message type
            if suggestion.type == .userMessage {
                // User Avatar
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
            } else {
                // AI Avatar
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
            }
            
            // Message content
            VStack(alignment: .leading, spacing: 8) {
                // Message header
                HStack {
                    Text(suggestion.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(suggestion.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Message content
                VStack(alignment: suggestion.type == .userMessage ? .trailing : .leading, spacing: 8) {
                    Text(suggestion.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(suggestion.type == .userMessage ? .white : .primary)
                    
                    if !suggestion.codeSnippet.isEmpty {
                        CodeBlockView(code: suggestion.codeSnippet)
                    }
                }
                .padding()
                .background(
                    suggestion.type == .userMessage 
                        ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(NSColor.controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(12)
            }
        }
    }
}

struct CodeBlockView: View {
    let code: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Code")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
}

struct AIChatView_Enhanced_Previews: PreviewProvider {
    static var previews: some View {
        AIChatView_Enhanced(aiManager: AIModelManager())
            .frame(width: 500, height: 700)
    }
}
