import Foundation
import SwiftUI

/// AI Model Manager for integrating Qwen2.5-Coder model with MacDBG
@MainActor
public class AIModelManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isModelLoaded = false
    @Published public var modelName = "No Model"
    @Published public var isLoading = false
    @Published public var lastError: String?
    @Published public var aiSuggestions: [AISuggestion] = []
    
    // MARK: - Private Properties
    private let aiBridge: AIModelBridge
    private let modelPath: String
    
    // MARK: - Initialization
    public init() {
        self.aiBridge = AIModelBridge()
        
        // Get the model path from the bundle
        if let bundlePath = Bundle.main.resourcePath {
            self.modelPath = "\(bundlePath)/models/qwen2.5-coder-3b-instruct-q4_0.gguf"
        } else {
            self.modelPath = ""
        }
        
        // Try to load the actual model on initialization
        Task {
            await loadModel()
        }
    }
    
    // MARK: - Model Management
    public func loadModel() async {
        guard !modelPath.isEmpty else {
            lastError = "Model path not found"
            macdbgLog("❌ AI Model path not found in bundle", category: .error)
            return
        }
        
        // Check if model file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            lastError = "Model file not found at path: \(modelPath)"
            macdbgLog("❌ AI Model file not found at path: \(modelPath)", category: .error)
            return
        }
        
        macdbgLog("🤖 Starting AI model load from: \(modelPath)", category: .system)
        isLoading = true
        lastError = nil
        
        // Load model on background thread
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                macdbgLog("🤖 Calling aiBridge.loadModel...", category: .system)
                let success = self.aiBridge.loadModel(self.modelPath)
                macdbgLog("🤖 aiBridge.loadModel returned: \(success)", category: .system)
                
                DispatchQueue.main.async {
                    self.isModelLoaded = success
                    self.isLoading = false
                    
                    if success {
                        self.modelName = self.aiBridge.getModelName()
                        macdbgLog("✅ AI Model loaded successfully: \(self.modelName)", category: .system)
                    } else {
                        self.lastError = "Failed to load AI model from C++ bridge"
                        macdbgLog("❌ Failed to load AI model from C++ bridge", category: .error)
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    public func unloadModel() {
        aiBridge.unloadModel()
        isModelLoaded = false
        modelName = "No Model"
        aiSuggestions.removeAll()
        macdbgLog("🤖 AI Model unloaded", category: .system)
    }
    
    // MARK: - Text Generation
    public func generateText(prompt: String, maxTokens: Int = 512) async -> String {
        guard isModelLoaded else {
            let error = lastError ?? "AI model not loaded"
            macdbgLog("❌ AI generation failed: \(error)", category: .error)
            return "Error: \(error)\n\nTry restarting MacDBG to reload the AI model."
        }
        
        macdbgLog("🤖 Generating AI response for prompt: \(prompt.prefix(50))...", category: .system)
        
        return await withCheckedContinuation { continuation in
            aiBridge.generateTextAsync(prompt, maxTokens: Int32(maxTokens)) { result in
                if let result = result, !result.isEmpty {
                    macdbgLog("✅ AI generation completed successfully", category: .system)
                    continuation.resume(returning: result)
                } else {
                    macdbgLog("❌ AI generation returned empty result", category: .error)
                    continuation.resume(returning: "Error: AI model returned empty response")
                }
            }
        }
    }
    
    // MARK: - Debugger-Specific AI Features
    public func analyzeDisassembly(_ disassembly: [DisassemblyLine], context: String = "") async -> AISuggestion {
        let disassemblyText = disassembly.map { line in
            "0x\(String(format: "%llx", line.address)): \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze this x64 assembly code and provide insights:
        
        Context: \(context)
        
        Assembly:
        \(disassemblyText)
        
        Please provide:
        1. What this code does
        2. Potential vulnerabilities
        3. Optimization suggestions
        4. Register usage analysis
        5. Control flow analysis
        """
        
        let analysis = await generateText(prompt: prompt, maxTokens: 1024)
        
        return AISuggestion(
            id: UUID(),
            type: .codeAnalysis,
            title: "Assembly Analysis",
            content: analysis,
            codeSnippet: disassemblyText,
            timestamp: Date(),
            address: disassembly.first?.address
        )
    }
    
    public func generateInstructionComment(_ instruction: DisassemblyLine, context: String = "") async -> AISuggestion {
        let instructionText = "0x\(String(format: "%llx", instruction.address)): \(instruction.instruction) \(instruction.operands)"
        
        let prompt = """
        Add a detailed comment for this assembly instruction:
        
        Context: \(context)
        
        Instruction: \(instructionText)
        
        Provide a clear, technical comment explaining what this instruction does and its purpose in the program flow.
        """
        
        let comment = await generateText(prompt: prompt, maxTokens: 256)
        
        return AISuggestion(
            id: UUID(),
            type: .instructionComment,
            title: "Instruction Comment",
            content: comment,
            codeSnippet: instructionText,
            timestamp: Date(),
            address: instruction.address
        )
    }
    
    public func suggestBreakpoints(_ disassembly: [DisassemblyLine], context: String = "") async -> AISuggestion {
        let disassemblyText = disassembly.map { line in
            "0x\(String(format: "%llx", line.address)): \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        let prompt = """
        Suggest optimal breakpoint locations for debugging this code:
        
        Context: \(context)
        
        Code:
        \(disassemblyText)
        
        Suggest specific addresses and explain why each breakpoint would be useful for debugging.
        """
        
        let suggestions = await generateText(prompt: prompt, maxTokens: 512)
        
        return AISuggestion(
            id: UUID(),
            type: .breakpointSuggestion,
            title: "Breakpoint Suggestions",
            content: suggestions,
            codeSnippet: disassemblyText,
            timestamp: Date(),
            address: nil
        )
    }
    
    public func explainRegisterState(_ registers: [String: UInt64], context: String = "") async -> AISuggestion {
        let registerText = registers.map { (name, value) in
            "\(name): 0x\(String(format: "%llx", value))"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze this CPU register state and explain what it tells us:
        
        Context: \(context)
        
        Registers:
        \(registerText)
        
        Explain:
        1. Current execution state
        2. Function call context
        3. Data being processed
        4. Potential issues or interesting patterns
        """
        
        let explanation = await generateText(prompt: prompt, maxTokens: 512)
        
        return AISuggestion(
            id: UUID(),
            type: .registerExplanation,
            title: "Register State Analysis",
            content: explanation,
            codeSnippet: registerText,
            timestamp: Date(),
            address: nil
        )
    }
    
    public func analyzeMemoryPattern(_ memory: [UInt64: [UInt8]], context: String = "") async -> AISuggestion {
        let memoryText = memory.prefix(10).map { (address, bytes) in
            let hexBytes = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            return "0x\(String(format: "%llx", address)): \(hexBytes)"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze this memory dump and identify patterns:
        
        Context: \(context)
        
        Memory:
        \(memoryText)
        
        Identify:
        1. Data structures
        2. Strings or text
        3. Code patterns
        4. Potential vulnerabilities
        5. Interesting values
        """
        
        let analysis = await generateText(prompt: prompt, maxTokens: 512)
        
        return AISuggestion(
            id: UUID(),
            type: .memoryAnalysis,
            title: "Memory Pattern Analysis",
            content: analysis,
            codeSnippet: memoryText,
            timestamp: Date(),
            address: nil
        )
    }
    
    // MARK: - Suggestion Management
    public func addSuggestion(_ suggestion: AISuggestion) {
        aiSuggestions.append(suggestion)
        
        // Keep only the last 50 suggestions
        if aiSuggestions.count > 50 {
            aiSuggestions.removeFirst(aiSuggestions.count - 50)
        }
    }
    
    public func clearSuggestions() {
        aiSuggestions.removeAll()
    }
    
    // MARK: - Chat Functions
    
    public func askQuestion(_ question: String) async -> AISuggestion {
        macdbgLog("🤖 Processing question: \(question)", category: .system)
        let response = await generateText(prompt: question)
        macdbgLog("🤖 Generated response: \(response.prefix(100))...", category: .system)
        
        return AISuggestion(
            id: UUID(),
            type: .aiResponse,
            title: "AI Response",
            content: response,
            timestamp: Date()
        )
    }
    
    public func analyzeCodeWithContext(code: String, question: String, context: String) async -> AISuggestion {
        let prompt = """
        Context: \(context)
        
        Code:
        \(code)
        
        Question: \(question)
        
        Please provide a detailed analysis.
        """
        
        let response = await generateText(prompt: prompt)
        
        return AISuggestion(
            id: UUID(),
            type: .codeAnalysis,
            title: "Code Analysis",
            content: response,
            timestamp: Date()
        )
    }
    
    public func removeSuggestion(_ suggestion: AISuggestion) {
        aiSuggestions.removeAll { $0.id == suggestion.id }
    }
    
    // MARK: - Configuration
    public func setTemperature(_ temperature: Float) {
        aiBridge.setTemperature(temperature)
    }
    
    public func setTopP(_ topP: Float) {
        aiBridge.setTopP(topP)
    }
    
    public func setMaxTokens(_ maxTokens: Int) {
        aiBridge.setMaxTokens(Int32(maxTokens))
    }
}

// MARK: - AI Suggestion Data Model
public struct AISuggestion: Identifiable, Codable {
    public let id: UUID
    public let type: AISuggestionType
    public let title: String
    public let content: String
    public let codeSnippet: String
    public let timestamp: Date
    public let address: UInt64?
    
    public init(id: UUID = UUID(), type: AISuggestionType, title: String, content: String, codeSnippet: String = "", timestamp: Date = Date(), address: UInt64? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.codeSnippet = codeSnippet
        self.timestamp = timestamp
        self.address = address
    }
}

public enum AISuggestionType: String, CaseIterable, Codable {
    case userMessage = "User Message"
    case aiResponse = "AI Response"
    case codeAnalysis = "Code Analysis"
    case instructionComment = "Instruction Comment"
    case comment = "Comment"
    case breakpointSuggestion = "Breakpoint Suggestion"
    case registerExplanation = "Register Explanation"
    case registerAnalysis = "Register Analysis"
    case memoryAnalysis = "Memory Analysis"
    case vulnerability = "Vulnerability"
    case bugDetection = "Bug Detection"
    case optimization = "Optimization"
    case general = "General"
    
    public var icon: String {
        switch self {
        case .userMessage:
            return "person.circle.fill"
        case .aiResponse:
            return "brain.head.profile"
        case .codeAnalysis:
            return "doc.text.magnifyingglass"
        case .instructionComment:
            return "arrow.right.circle"
        case .comment:
            return "text.bubble"
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
        case .bugDetection:
            return "exclamationmark.triangle"
        case .optimization:
            return "speedometer"
        case .general:
            return "message"
        }
    }
    
    public var color: Color {
        switch self {
        case .userMessage:
            return .blue
        case .aiResponse:
            return .purple
        case .codeAnalysis:
            return .blue
        case .instructionComment:
            return .blue
        case .comment:
            return .green
        case .breakpointSuggestion:
            return .red
        case .registerExplanation:
            return .cyan
        case .registerAnalysis:
            return .orange
        case .memoryAnalysis:
            return .purple
        case .vulnerability:
            return .red
        case .bugDetection:
            return .red
        case .optimization:
            return .yellow
        case .general:
            return .primary
        }
    }
}
