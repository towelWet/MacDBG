import SwiftUI

struct DisassemblyView: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    @Binding var showingAIAnalysis: Bool
    
    @State private var selectedAddresses: Set<UInt64> = []
    @State private var showingGotoDialog = false
    @State private var gotoAddress: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Disassembly")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // AI Analysis Button - Always show
                Button(action: { 
                    print("🔍 AI Button clicked, isModelLoaded: \(aiManager.isModelLoaded)")
                    toggleAIChat() 
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                        Text("AI")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle AI Assistant Panel")
                
                Button("Refresh") {
                    Task {
                        await debugger.refreshDisassemblyAroundPC()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Goto") {
                    showingGotoDialog = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Disassembly Content
            if debugger.disassembly.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Disassembly Available")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Launch a binary or attach to a process to view disassembly")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Quick Start:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "play.circle")
                                    .foregroundColor(.blue)
                                Text("Click 'Launch Binary' to select an executable")
                                Spacer()
                            }
                            
                            HStack {
                                Image(systemName: "link.circle")
                                    .foregroundColor(.green)
                                Text("Or select a process from the list to attach")
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Disassembly List
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(debugger.disassembly, id: \.address) { line in
                            DisassemblyRowView(
                                line: line,
                                isActive: line.address == debugger.programCounter,
                                isSelected: selectedAddresses.contains(line.address),
                                onTap: { toggleSelection(line.address) },
                                onContextMenu: { showContextMenu(for: line) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingGotoDialog) {
            VStack(spacing: 16) {
                Text("Go to Address")
                    .font(.headline)
                
                TextField("Address (e.g., 0x1000)", text: $gotoAddress)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Cancel") {
                        showingGotoDialog = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Go") {
                        if let address = parseAddress(gotoAddress) {
                            Task {
                                await debugger.getDisassemblyAt(address: address)
                            }
                        }
                        showingGotoDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    private func toggleSelection(_ address: UInt64) {
        if selectedAddresses.contains(address) {
            selectedAddresses.remove(address)
        } else {
            selectedAddresses.insert(address)
        }
    }
    
    private func showContextMenu(for line: DisassemblyLine) {
        // If there are selected addresses, send all selected lines
        if !selectedAddresses.isEmpty {
            sendSelectedToAI()
        } else {
            // If no selection, send just this line
            sendLineToAI(line)
        }
    }
    
    private func sendSelectedToAI() {
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
                    showingAIAnalysis = true // Show AI panel when analysis is added
                }
            }
        }
    }
    
    private func sendLineToAI(_ line: DisassemblyLine) {
        Task {
            let suggestion = await aiManager.analyzeCodeWithContext(
                code: "\(line.formattedAddress) \(line.instruction) \(line.operands)",
                question: "Explain what this assembly instruction does:",
                context: "Single disassembly line analysis"
            )
            
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                showingAIAnalysis = true // Show AI panel when analysis is added
            }
        }
    }
    
    private func toggleAIChat() {
        showingAIAnalysis.toggle()
        debugger.addLog("🤖 AI Chat \(showingAIAnalysis ? "shown" : "hidden")")
        print("🔍 AI Chat toggled: \(showingAIAnalysis)")
    }
    
    private func parseAddress(_ addressString: String) -> UInt64? {
        let trimmed = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return UInt64(String(trimmed.dropFirst(2)), radix: 16)
        } else {
            return UInt64(trimmed, radix: 16) ?? UInt64(trimmed)
        }
    }
}

struct DisassemblyRowView: View {
    let line: DisassemblyLine
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onContextMenu: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Address
            Text(line.formattedAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Bytes
            Text(line.bytes)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            // Instruction
            Text(line.instruction)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(instructionColor)
                .frame(width: 60, alignment: .leading)
            
            // Operands
            Text(line.operands)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("🤖 Send to AI Chat") {
                onContextMenu()
            }
            
            Button("📋 Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.formattedAddress, forType: .string)
            }
            
            Button("🔍 Go to Address") {
                // Go to functionality
            }
        }
    }
    
    private var backgroundColor: Color {
        if isActive {
            return Color.blue.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.15)
        } else {
            return Color.clear
        }
    }
    
    private var instructionColor: Color {
        let inst = line.instruction.lowercased()
        if inst.hasPrefix("j") && inst != "jmp" {
            return .blue
        } else if inst.hasPrefix("call") {
            return .green
        } else if inst.hasPrefix("ret") {
            return .orange
        } else if inst.contains("mov") {
            return .purple
        } else {
            return .primary
        }
    }
}
