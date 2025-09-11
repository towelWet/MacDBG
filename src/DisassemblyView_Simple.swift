import SwiftUI

struct DisassemblyView_Simple: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    @StateObject private var jumpTracker = JumpTracker()
    
    @State private var selectedAddresses: Set<UInt64> = []
    @State private var lastSelectedAddress: UInt64?
    @State private var showingGotoDialog = false
    @State private var gotoAddress: UInt64 = 0
    @State private var showingCopyAlert = false
    
    private let lineHeight: CGFloat = 24
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Simple toolbar
            HStack {
                Text("Disassembly")
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                if debugger.isAttached {
                    Button("▲") {
                        Task { await debugger.expandDisassemblyRange(direction: .backward) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("▼") {
                        Task { await debugger.expandDisassemblyRange(direction: .forward) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Goto") {
                        showingGotoDialog = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Simple disassembly list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(debugger.disassembly) { line in
                        SimpleDisassemblyRow_Simple(
                            line: line,
                            isActive: line.address == debugger.programCounter,
                            isSelected: selectedAddresses.contains(line.address),
                            debugger: debugger,
                            jumpTracker: jumpTracker,
                            aiManager: aiManager,
                            onClicked: { modifiers in handleLineClick(address: line.address, modifiers: modifiers) },
                            onDoubleClicked: { handleDoubleClick(address: line.address) },
                            onAddressClicked: { targetAddress in
                                Task {
                                    await debugger.navigateToAddress(targetAddress)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        selectedAddresses.removeAll()
                                        selectedAddresses.insert(targetAddress)
                                        lastSelectedAddress = targetAddress
                                    }
                                }
                            },
                            selectedAddresses: selectedAddresses
                        )
                        .frame(height: lineHeight)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .onKeyPress(.init("l")) {
            // Cmd+L shortcut to send selected lines to AI chat
            if !selectedAddresses.isEmpty {
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
            return .handled
        }
        .sheet(isPresented: $showingGotoDialog) {
            GotoAddressDialog(
                address: $gotoAddress,
                onGoto: { address in
                    Task {
                        await debugger.getDisassemblyAt(address: address)
                    }
                }
            )
        }
        .alert("Copy Complete", isPresented: $showingCopyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Selected disassembly has been copied to clipboard")
        }
    }
    
    private func handleLineClick(address: UInt64, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            // Toggle selection
            if selectedAddresses.contains(address) {
                selectedAddresses.remove(address)
            } else {
                selectedAddresses.insert(address)
            }
            lastSelectedAddress = address
        } else {
            // Single selection
            selectedAddresses.removeAll()
            selectedAddresses.insert(address)
            lastSelectedAddress = address
        }
    }
    
    private func handleDoubleClick(address: UInt64) {
        // Toggle breakpoint
        if debugger.breakpoints.contains(address) {
            debugger.removeBreakpoint(at: address)
        } else {
            debugger.addBreakpoint(at: address)
        }
    }
}

struct SimpleDisassemblyRow_Simple: View {
    let line: DisassemblyLine
    let isActive: Bool
    let isSelected: Bool
    let debugger: DebuggerController
    let jumpTracker: JumpTracker
    let aiManager: AIModelManager
    let onClicked: (NSEvent.ModifierFlags) -> Void
    let onDoubleClicked: () -> Void
    let onAddressClicked: (UInt64) -> Void
    let selectedAddresses: Set<UInt64>
    
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
                .frame(width: 24, alignment: .leading)
            
            // Instruction
            Text(line.instruction)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(instructionColor)
                .frame(width: 80, alignment: .leading)
            
            // Operands
            Text(line.operands)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .onTapGesture {
            onClicked(NSEvent.modifierFlags)
        }
        .onDoubleTapGesture {
            onDoubleClicked()
        }
        .contextMenu {
            // AI Assistant section
            if !selectedAddresses.isEmpty {
                Button("🤖 Send to AI Chat") {
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
        }
    }
    
    private var backgroundColor: Color {
        if isActive {
            return Color.blue.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var instructionColor: Color {
        if line.instruction.lowercased().hasPrefix("j") {
            return .blue
        } else if line.instruction.lowercased().hasPrefix("call") {
            return .green
        } else if line.instruction.lowercased().hasPrefix("ret") {
            return .orange
        } else {
            return .primary
        }
    }
}

#Preview {
    DisassemblyView_Simple(
        debugger: Debugger(),
        jumpTracker: JumpTracker(),
        aiManager: AIModelManager()
    )
}
