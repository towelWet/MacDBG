import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var debugger: DebuggerController
    @StateObject private var aiManager = AIModelManager()
    @State private var showingExportDialog = false
    @State private var showingAIAnalysis = true
    @State private var selectedAISuggestion: AISuggestion?
    
    var body: some View {
        HSplitView {
            // Left sidebar - Process list and controls (narrower like x64dbg)
            VStack(alignment: .leading, spacing: 8) {
                Text("MacDBG V3")
                    .font(.title3)
                    .fontWeight(.bold)
                
                ProcessListView(debugger: debugger)
                
                Divider()
                
                DebugControlsView(debugger: debugger)
                
                // AI Quick Actions
                if aiManager.isModelLoaded {
                    Divider()
                    AIQuickActionsView(aiManager: aiManager, debugger: debugger)
                }
                
                Spacer()
                
                StatusView(debugger: debugger)
            }
            .frame(minWidth: 220, maxWidth: 280)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            
            // Main workspace with AI chat section
            HSplitView {
                // Main workspace - Original 4-panel layout
                mainWorkspaceView
                    .frame(minWidth: 400)
                
                // AI chat section with built-in resize
                if showingAIAnalysis {
                    AIChatView_Enhanced(aiManager: aiManager)
                        .frame(minWidth: 200, idealWidth: 300, maxWidth: 500)
                }
            }
        }
        .onAppear {
            debugger.refreshProcessList()
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: ExportDocument(content: debugger.exportData()),
            contentType: .json,
            defaultFilename: debugger.getExportFilename()
        ) { result in
            switch result {
            case .success(let url):
                debugger.addLog("Exported debug data to: \(url.path)")
            case .failure(let error):
                debugger.addLog("Export failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Main Workspace View
    private var mainWorkspaceView: some View {
        HSplitView {
            // Center section - Disassembly and Memory
            VSplitView {
                // Top center - Disassembly
                VStack(spacing: 0) {
                    HStack {
                        Text("Disassembly")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                        
                        // AI Analysis Button
                        if aiManager.isModelLoaded {
                            Button(action: { showingAIAnalysis.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain")
                                    Text("AI")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Toggle AI Assistant Panel")
                        }
                        
                        Button("Refresh") {
                            Task {
                                await debugger.refreshDisassemblyAroundPC()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    DisassemblyView(
                        debugger: debugger, 
                        aiManager: aiManager,
                        showingAIAnalysis: $showingAIAnalysis
                    )
                }
                .roundedBorder()
                
                // Bottom center - Memory view
                VStack(spacing: 0) {
                    HStack {
                        Text("Memory")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    MemoryView(debugger: debugger)
                }
                .roundedBorder()
            }
            
            // Right section - Registers and Debug Log
            VSplitView {
                // Top right - Registers
                VStack(spacing: 0) {
                    HStack {
                        Text("Registers")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Refresh") {
                            Task {
                                await debugger.refreshRegisters()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    RegistersView(debugger: debugger)
                }
                .roundedBorder()
                
                // Bottom right - DEBUG LOG (RESTORED!)
                VStack(spacing: 0) {
                    HStack {
                        Text("Debug Log")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Clear") {
                            debugger.logs.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Export") {
                            showingExportDialog = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    LogView(debugger: debugger)
                }
                .roundedBorder()
            }
            .frame(minWidth: 300, maxWidth: 400)
        }
    }
}

// MARK: - AI Quick Actions View
struct AIQuickActionsView: View {
    @ObservedObject var aiManager: AIModelManager
    @ObservedObject var debugger: DebuggerController
    @State private var isAnalyzing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.blue)
                Text("AI Assistant")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            VStack(spacing: 4) {
                Button("Analyze Code") {
                    analyzeDisassembly()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!debugger.isAttached || isAnalyzing)
                
                Button("Explain Registers") {
                    analyzeRegisters()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!debugger.isAttached || debugger.registers.isEmpty || isAnalyzing)
                
                Button("Memory Pattern") {
                    analyzeMemory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!debugger.isAttached || debugger.memory.isEmpty || isAnalyzing)
            }
            
            if isAnalyzing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func analyzeDisassembly() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        
        Task {
            let suggestion = await aiManager.analyzeDisassembly(
                debugger.disassembly,
                context: "Current PC: 0x\(String(format: "%llx", debugger.programCounter))"
            )
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                isAnalyzing = false
            }
        }
    }
    
    private func analyzeRegisters() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        
        Task {
            let suggestion = await aiManager.explainRegisterState(
                debugger.registers,
                context: "Current PC: 0x\(String(format: "%llx", debugger.programCounter))"
            )
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                isAnalyzing = false
            }
        }
    }
    
    private func analyzeMemory() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        
        Task {
            let suggestion = await aiManager.analyzeMemoryPattern(
                debugger.memory,
                context: "Current PC: 0x\(String(format: "%llx", debugger.programCounter))"
            )
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                isAnalyzing = false
            }
        }
    }
}

// MARK: - AI Assistant Panel
struct AIAssistantPanel: View {
    @ObservedObject var aiManager: AIModelManager
    @Binding var selectedSuggestion: AISuggestion?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.blue)
                Text("AI Assistant")
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
            .background(Color(NSColor.controlBackgroundColor))
            
            // Suggestions List
            if aiManager.aiSuggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No AI suggestions yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Use the AI buttons in the left sidebar to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
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
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// Export document for sharing debug data
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        content = ""
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1400, height: 900)
    }
}

// MARK: - Resizable AI Chat View
struct ResizableAIChatView: View {
    @ObservedObject var aiManager: AIModelManager
    @State private var chatWidth: CGFloat = 400
    @State private var isDragging = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Resize handle
            Rectangle()
                .fill(isDragging ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3))
                .frame(width: 8)
                .onHover { hovering in
                    if hovering && !isDragging {
                        NSCursor.resizeLeftRight.push()
                    } else if !hovering && !isDragging {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                NSCursor.resizeLeftRight.push()
                            }
                            let newWidth = chatWidth - value.translation.width
                            chatWidth = max(200, min(600, newWidth))
                        }
                        .onEnded { _ in
                            isDragging = false
                            NSCursor.pop()
                        }
                )
            
            // AI Chat content
            AIChatView_Enhanced(aiManager: aiManager)
                .frame(width: chatWidth)
        }
    }
}

// MARK: - Extensions for better UX
extension View {
    func roundedBorder() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }
}