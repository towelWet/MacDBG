import SwiftUI

struct DisassemblyView: View {
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var aiManager: AIModelManager
    @Binding var showingAIAnalysis: Bool
    
    @State private var selectedAddresses: Set<UInt64> = []
    @State private var lastSelectedAddress: UInt64? = nil
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
                // Virtualized Disassembly List (x64dbg-style performance)
                ScrollViewReader { proxy in
                    ScrollView {
                        let hasSelectedLines = !selectedAddresses.isEmpty
                        let visibleLines = debugger.disassembly // Show ALL lines like x64dbg
                        
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visibleLines, id: \.address) { line in
                                OptimizedDisassemblyRowView(
                                    line: line,
                                    isActive: line.address == debugger.programCounter,
                                    isSelected: selectedAddresses.contains(line.address),
                                    hasSelectedLines: hasSelectedLines,
                                    onTap: { toggleSelection(line.address) },
                                    onTapWithModifiers: { isShift, isCommand in 
                                        toggleSelectionWithModifier(line.address, isShiftPressed: isShift, isCommandPressed: isCommand)
                                    },
                                    onContextMenu: { showContextMenu(for: line) },
                                    onSendSelected: { sendSelectedToAI() },
                                    onCopySelection: { copySelection() },
                                    onCopyLine: { copyLine(line) },
                                    onFollowInDump: { followInDump(line) },
                                    onFollowInMemoryMap: { followInMemoryMap(line) },
                                    onAddLabel: { addLabel(to: line) },
                                    onAddComment: { addComment(to: line) }
                                )
                                .id(line.address)
                                .animation(.none, value: selectedAddresses) // Disable animations for performance
                            }
                        }
                        .drawingGroup() // Rasterize for better performance with many items
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        // Scroll to program counter like x64dbg
                        if debugger.programCounter != 0 {
                            proxy.scrollTo(debugger.programCounter, anchor: .center)
                        }
                    }
                    .onChange(of: debugger.navigationTarget) { target in
                        // Handle string navigation (like Ghidra's "Go To" functionality)
                        if let targetAddress = target {
                            print("🎯 DisassemblyView: Navigating to target address 0x\(String(format: "%llx", targetAddress))")
                            
                            // First check if the address is already in our disassembly
                            if debugger.disassembly.contains(where: { $0.address == targetAddress }) {
                                // Address is already visible, just scroll to it
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(targetAddress, anchor: .center)
                                }
                                print("🎯 Scrolled to existing address in disassembly")
                            } else {
                                // Address not visible, request disassembly at that location
                                print("🎯 Address not in current disassembly, requesting new disassembly")
                                Task {
                                    await debugger.getDisassemblyAt(address: targetAddress, count: 200)
                                    // After we get new disassembly, scroll to the target
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo(targetAddress, anchor: .center)
                                        }
                                    }
                                }
                            }
                            
                            // Clear the navigation target after handling
                            debugger.navigationTarget = nil
                        }
                    }
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
        // x64dbg-style selection: single click = select only that line
        Task { @MainActor in
            selectedAddresses.removeAll()
            selectedAddresses.insert(address)
            lastSelectedAddress = address
        }
    }
    
    private func toggleSelectionWithModifier(_ address: UInt64, isShiftPressed: Bool, isCommandPressed: Bool) {
        Task { @MainActor in
            if isCommandPressed {
                // Cmd+click: toggle individual line (like x64dbg Ctrl+click)
                if selectedAddresses.contains(address) {
                    selectedAddresses.remove(address)
                    if lastSelectedAddress == address {
                        lastSelectedAddress = selectedAddresses.first
                    }
                } else {
                    selectedAddresses.insert(address)
                    lastSelectedAddress = address
                }
            } else if isShiftPressed, let lastAddress = lastSelectedAddress {
                // Shift+click: select range from last selected to current
                selectRange(from: lastAddress, to: address)
                lastSelectedAddress = address
            } else {
                // Regular click: select only this line
                selectedAddresses.removeAll()
                selectedAddresses.insert(address)
                lastSelectedAddress = address
            }
        }
    }
    
    private func selectRange(from startAddress: UInt64, to endAddress: UInt64) {
        // Find the range in the disassembly and select all lines in between
        let disassembly = debugger.disassembly
        guard let startIndex = disassembly.firstIndex(where: { $0.address == startAddress }),
              let endIndex = disassembly.firstIndex(where: { $0.address == endAddress }) else {
            return
        }
        
        let minIndex = min(startIndex, endIndex)
        let maxIndex = max(startIndex, endIndex)
        
        selectedAddresses.removeAll()
        for i in minIndex...maxIndex {
            selectedAddresses.insert(disassembly[i].address)
        }
    }
    
    private func showContextMenu(for line: DisassemblyLine) {
        // Always send the specific line that was right-clicked
        // This provides more predictable behavior
        sendLineToAI(line)
    }
    
    private func sendSelectedToAI() {
        print("🔍 sendSelectedToAI called with \(selectedAddresses.count) selected addresses")
        
        // Get selected lines
        let selectedLines = Array(debugger.disassembly
            .filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address })
        
        print("🔍 Found \(selectedLines.count) selected lines to send to chat")
        
        guard !selectedLines.isEmpty else {
            print("🔍 No selected lines found!")
            return
        }
        
        // Format the selected lines for the chat input
        let codeText = selectedLines.map { line in
            "\(line.formattedAddress) \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        // Open the AI chat panel and populate the input with selected lines
        Task { @MainActor in
            showingAIAnalysis = true
            
            // Add the selected code to the AI manager's current input
            // This should populate the chat input field for the user to add context
            aiManager.prepareCodeForChat(code: codeText, context: "Selected \(selectedLines.count) disassembly lines")
        }
    }
    
    private func sendLineToAI(_ line: DisassemblyLine) {
        // Show loading state immediately
        Task { @MainActor in
            showingAIAnalysis = true
        }
        
        // Process AI analysis on background thread to prevent GUI freezing
        Task.detached { [weak aiManager] in
            print("🔍 Analyzing single line: \(line.formattedAddress)")
            
            guard let aiManager = aiManager else {
                print("🔍 AI manager is nil")
                return
            }
            
            let suggestion = await aiManager.analyzeCodeWithContext(
                code: "\(line.formattedAddress) \(line.instruction) \(line.operands)",
                question: "Explain what this assembly instruction does:",
                context: "Single disassembly line analysis"
            )
            
            // Update UI on main thread
            await MainActor.run {
                aiManager.addSuggestion(suggestion)
                print("🔍 Single line analysis added successfully")
            }
        }
    }
    
    private func toggleAIChat() {
        showingAIAnalysis.toggle()
    }
    
    // MARK: - x64dbg-style Context Menu Functions
    
    private func copySelection() {
        let selectedLines = debugger.disassembly
            .filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address }
        
        let textToCopy = selectedLines.map { line in
            "\(line.formattedAddress) \(line.bytes.padding(toLength: 24, withPad: " ", startingAt: 0)) \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        print("🔍 Copied \(selectedLines.count) lines to clipboard")
    }
    
    private func copySelectionToFile() {
        let selectedLines = debugger.disassembly
            .filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address }
        
        let textToCopy = selectedLines.map { line in
            "\(line.formattedAddress) \(line.bytes.padding(toLength: 24, withPad: " ", startingAt: 0)) \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "disassembly_selection.txt"
        savePanel.title = "Save Selection to File"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try textToCopy.write(to: url, atomically: true, encoding: .utf8)
                print("🔍 Saved \(selectedLines.count) lines to \(url.path)")
            } catch {
                print("🔍 Failed to save: \(error.localizedDescription)")
            }
        }
    }
    
    private func copySelectionBytesOnly() {
        let selectedLines = debugger.disassembly
            .filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address }
        
        let textToCopy = selectedLines.map { line in
            line.bytes
        }.joined(separator: " ")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        print("🔍 Copied bytes only for \(selectedLines.count) lines")
    }
    
    private func copySelectionNoBytes() {
        let selectedLines = debugger.disassembly
            .filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address }
        
        let textToCopy = selectedLines.map { line in
            "\(line.formattedAddress) \(line.instruction) \(line.operands)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        print("🔍 Copied \(selectedLines.count) lines without bytes")
    }
    
    private func copyLine(_ line: DisassemblyLine) {
        let textToCopy = "\(line.formattedAddress) \(line.bytes.padding(toLength: 24, withPad: " ", startingAt: 0)) \(line.instruction) \(line.operands)"
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        print("🔍 Copied single line to clipboard")
    }
    
    private func followInDump(_ line: DisassemblyLine) {
        // Extract address from operands if it's a memory reference
        // This would typically switch to memory view and highlight the address
        print("🔍 Follow in Dump - switching to memory view for \(line.formattedAddress)")
        // TODO: Implement memory view navigation
    }
    
    private func followInMemoryMap(_ line: DisassemblyLine) {
        // Show memory map and highlight this address
        print("🔍 Follow in Memory Map for \(line.formattedAddress)")
        // TODO: Implement memory map navigation
    }
    
    private func addLabel(to line: DisassemblyLine) {
        // Show dialog to add label to this address
        let alert = NSAlert()
        alert.messageText = "Add Label"
        alert.informativeText = "Enter label for address \(line.formattedAddress):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = ""
        alert.accessoryView = textField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let label = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                // TODO: Store label in debugger
                print("🔍 Added label '\(label)' to \(line.formattedAddress)")
            }
        }
    }
    
    private func addComment(to line: DisassemblyLine) {
        // Show dialog to add comment to this address
        let alert = NSAlert()
        alert.messageText = "Add Comment"
        alert.informativeText = "Enter comment for address \(line.formattedAddress):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        textField.stringValue = ""
        alert.accessoryView = textField
        
        if alert.runModal() == .alertFirstButtonReturn {
            let comment = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !comment.isEmpty {
                // TODO: Store comment in debugger
                print("🔍 Added comment '\(comment)' to \(line.formattedAddress)")
            }
        }
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

// Original row view (kept for compatibility)
struct DisassemblyRowView: View {
    let line: DisassemblyLine
    let isActive: Bool
    let isSelected: Bool
    let hasSelectedLines: Bool
    let onTap: () -> Void
    let onContextMenu: () -> Void
    let onSendSelected: () -> Void
    
    var body: some View {
        OptimizedDisassemblyRowView(
            line: line,
            isActive: isActive,
            isSelected: isSelected,
            hasSelectedLines: hasSelectedLines,
            onTap: onTap,
            onTapWithModifiers: { _, _ in }, // Default: no modifier handling
            onContextMenu: onContextMenu,
            onSendSelected: onSendSelected,
            onCopySelection: { }, // Default: no action
            onCopyLine: { }, // Default: no action
            onFollowInDump: { }, // Default: no action
            onFollowInMemoryMap: { }, // Default: no action
            onAddLabel: { }, // Default: no action
            onAddComment: { } // Default: no action
        )
    }
}

// High-performance row view optimized like x64dbg
struct OptimizedDisassemblyRowView: View {
    let line: DisassemblyLine
    let isActive: Bool
    let isSelected: Bool
    let hasSelectedLines: Bool
    let onTap: () -> Void
    let onTapWithModifiers: (Bool, Bool) -> Void
    let onContextMenu: () -> Void
    let onSendSelected: () -> Void
    let onCopySelection: () -> Void
    let onCopyLine: () -> Void
    let onFollowInDump: () -> Void
    let onFollowInMemoryMap: () -> Void
    let onAddLabel: () -> Void
    let onAddComment: () -> Void
    
    // Cache expensive computations
    private static let monospacedFont = Font.system(.caption, design: .monospaced)
    private static let rowHeight: CGFloat = 20
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Address (fixed width for alignment)
            Text(line.formattedAddress)
                .font(Self.monospacedFont)
                .foregroundColor(.secondary)
                .frame(width: 85, alignment: .leading)
            
            // Bytes (limited width)
            Text(line.bytes.prefix(24))
                .font(Self.monospacedFont)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            
            // Instruction (color-coded)
            Text(line.instruction)
                .font(Self.monospacedFont)
                .foregroundColor(instructionColor)
                .frame(width: 65, alignment: .leading)
            
            // Operands (flexible width)
            Text(line.operands)
                .font(Self.monospacedFont)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .frame(height: Self.rowHeight)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .contentShape(Rectangle()) // Optimize hit testing
        .onTapGesture {
            // Check for modifier keys using NSEvent
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            let isCommandPressed = NSEvent.modifierFlags.contains(.command)
            
            if isShiftPressed || isCommandPressed {
                onTapWithModifiers(isShiftPressed, isCommandPressed)
            } else {
                onTap()
            }
        }
        .contextMenu {
            contextMenuContent
        }
    }
    
    // Pre-computed background color
    private var backgroundColor: Color {
        if isActive {
            return Color.blue.opacity(0.25)
        } else if isSelected {
            return Color.blue.opacity(0.12)
        } else {
            return Color.clear
        }
    }
    
    // Ultra-fast instruction color with minimal string operations
    private var instructionColor: Color {
        // Use first character only to avoid expensive string operations
        guard let firstChar = line.instruction.first else { return .primary }
        
        switch firstChar {
        case "j", "J": // Jump instructions
            return line.instruction.count == 3 && line.instruction.hasPrefix("jmp") ? .primary : .blue
        case "c", "C": // Call instructions
            return .green
        case "r", "R": // Return instructions  
            return .orange
        case "m", "M": // Move instructions
            return .purple
        case "p", "P": // Push/Pop
            return .cyan
        default:
            return .primary
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // AI Features Section
        if hasSelectedLines {
            Button("🤖 Send Selected to AI") {
                print("🔍 Context menu: Send Selected to AI clicked!")
                onSendSelected()
            }
        } else {
            Button("🤖 Send to AI Chat") {
                print("🔍 Context menu: Send to AI Chat clicked!")
                onContextMenu()
            }
        }
        
        Divider()
        
        // Copy Options (like x64dbg)
        if hasSelectedLines {
            Button("📋 Copy Selection") {
                onCopySelection()
            }
        } else {
            Button("📋 Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.formattedAddress, forType: .string)
            }
            
            Button("📄 Copy Line") {
                onCopyLine()
            }
        }
        
        Divider()
        
        // Navigation Options (like x64dbg)
        Button("📊 Follow in Dump") {
            onFollowInDump()
        }
        
        Button("🏷️ Label") {
            onAddLabel()
        }
        
        Button("💬 Comment") {
            onAddComment()
        }
    }
}
