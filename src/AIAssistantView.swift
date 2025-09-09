import SwiftUI

/// AI Assistant View for MacDBG - Provides AI-powered analysis and suggestions
public struct AIAssistantView: View {
    @EnvironmentObject private var debugger: DebuggerController
    @StateObject private var aiManager = AIModelManager()
    @State private var selectedSuggestion: AISuggestion?
    @State private var isAnalyzing = false
    @State private var analysisType: AIAnalysisType = .disassembly
    @State private var customPrompt = ""
    @State private var showingSettings = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main Content
            HStack(spacing: 0) {
                // AI Suggestions List
                suggestionsListView
                    .frame(width: 300)
                
                Divider()
                
                // Analysis Content
                analysisContentView
            }
        }
        .sheet(isPresented: $showingSettings) {
            AISettingsView(aiManager: aiManager)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                    Text("AI Assistant")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Circle()
                        .fill(aiManager.isModelLoaded ? .green : .red)
                        .frame(width: 8, height: 8)
                    
                    Text(aiManager.isModelLoaded ? "Model: \(aiManager.modelName)" : "No Model Loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Analysis Type Picker
                Picker("Analysis Type", selection: $analysisType) {
                    ForEach(AIAnalysisType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
                
                // Analyze Button
                Button(action: performAnalysis) {
                    HStack(spacing: 6) {
                        if isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "brain")
                        }
                        Text("Analyze")
                    }
                }
                .disabled(!aiManager.isModelLoaded || isAnalyzing || !canAnalyze)
                .buttonStyle(.borderedProminent)
                
                // Settings Button
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Suggestions List View
    private var suggestionsListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Suggestions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear") {
                    aiManager.clearSuggestions()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            
            if aiManager.aiSuggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No AI suggestions yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Click 'Analyze' to get AI insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(aiManager.aiSuggestions.reversed(), id: \.id) { suggestion in
                    SuggestionRowView(suggestion: suggestion)
                        .onTapGesture {
                            selectedSuggestion = suggestion
                        }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    // MARK: - Analysis Content View
    private var analysisContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion = selectedSuggestion {
                SuggestionDetailView(suggestion: suggestion)
            } else {
                analysisInputView
            }
        }
    }
    
    // MARK: - Analysis Input View
    private var analysisInputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Analysis")
                .font(.headline)
                .fontWeight(.semibold)
                .padding()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Analysis Type: \(analysisType.rawValue)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if analysisType == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Prompt:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                    }
                } else {
                    Text(analysisType.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
            .padding()
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    private var canAnalyze: Bool {
        switch analysisType {
        case .disassembly:
            return !debugger.disassembly.isEmpty
        case .registers:
            return !debugger.registers.isEmpty
        case .memory:
            return !debugger.memory.isEmpty
        case .custom:
            return !customPrompt.isEmpty
        }
    }
    
    // MARK: - Actions
    private func performAnalysis() {
        guard !isAnalyzing else { return }
        
        isAnalyzing = true
        
        Task {
            let suggestion: AISuggestion
            
            switch analysisType {
            case .disassembly:
                suggestion = await aiManager.analyzeDisassembly(
                    debugger.disassembly,
                    context: "Current program counter: 0x\(String(format: "%llx", debugger.programCounter))"
                )
            case .registers:
                suggestion = await aiManager.explainRegisterState(
                    debugger.registers,
                    context: "Current program counter: 0x\(String(format: "%llx", debugger.programCounter))"
                )
            case .memory:
                suggestion = await aiManager.analyzeMemoryPattern(
                    debugger.memory,
                    context: "Current program counter: 0x\(String(format: "%llx", debugger.programCounter))"
                )
            case .custom:
                let response = await aiManager.generateText(prompt: customPrompt)
                suggestion = AISuggestion(
                    type: .codeAnalysis,
                    title: "Custom Analysis",
                    content: response
                )
            }
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                selectedSuggestion = suggestion
                isAnalyzing = false
            }
        }
    }
}

// MARK: - Suggestion Row View
struct SuggestionRowView: View {
    let suggestion: AISuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: suggestion.type.icon)
                    .foregroundColor(suggestion.type.color)
                    .frame(width: 16)
                
                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                Text(suggestion.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(suggestion.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Suggestion Detail View
struct SuggestionDetailView: View {
    let suggestion: AISuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: suggestion.type.icon)
                    .foregroundColor(suggestion.type.color)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(suggestion.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let address = suggestion.address {
                    Text("0x\(String(format: "%llx", address))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            ScrollView {
                Text(suggestion.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - AI Analysis Type
enum AIAnalysisType: String, CaseIterable {
    case disassembly = "Disassembly"
    case registers = "Registers"
    case memory = "Memory"
    case custom = "Custom"
    
    var description: String {
        switch self {
        case .disassembly:
            return "Analyze the current disassembly for code patterns, vulnerabilities, and optimization opportunities."
        case .registers:
            return "Explain the current CPU register state and what it reveals about program execution."
        case .memory:
            return "Analyze memory patterns to identify data structures and interesting values."
        case .custom:
            return "Provide a custom analysis based on your specific prompt."
        }
    }
}

// MARK: - AI Settings View
struct AISettingsView: View {
    @ObservedObject var aiManager: AIModelManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var temperature: Float = 0.7
    @State private var topP: Float = 0.9
    @State private var maxTokens: Int = 512
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperature: \(temperature, specifier: "%.2f")")
                        .font(.subheadline)
                    
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                        .onChange(of: temperature) { newValue in
                            aiManager.setTemperature(newValue)
                        }
                    
                    Text("Controls randomness. Lower values make responses more focused.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top P: \(topP, specifier: "%.2f")")
                        .font(.subheadline)
                    
                    Slider(value: $topP, in: 0...1, step: 0.05)
                        .onChange(of: topP) { newValue in
                            aiManager.setTopP(newValue)
                        }
                    
                    Text("Controls diversity. Lower values focus on more likely tokens.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Max Tokens: \(maxTokens)")
                        .font(.subheadline)
                    
                    Slider(value: Binding(
                        get: { Float(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 64...2048, step: 64)
                        .onChange(of: maxTokens) { newValue in
                            aiManager.setMaxTokens(newValue)
                        }
                    
                    Text("Maximum length of AI responses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

struct AIAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        AIAssistantView()
            .environmentObject(DebuggerController())
    }
}
