import SwiftUI

struct DisassemblyView: View {
    @ObservedObject var debugger: DebuggerController
    @StateObject private var jumpTracker = JumpTracker()
    @State private var selectedAddresses = Set<UInt64>()
    @State private var showingGotoDialog = false
    @State private var gotoAddress = ""
    @State private var showingCopyAlert = false
    @State private var copyText = ""
    @State private var lastSelectedAddress: UInt64? = nil
    // Removed complex auto-focus logic - using simple direct focus instead
    @State private var lastProgramCounter: UInt64 = 0  // Track PC changes
    @State private var lastUpdateTrigger: Int = 0  // Track UI updates
    
    private let lineHeight: CGFloat = 24
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enhanced toolbar (compact for unified layout)
            HStack {
                Text("Disassembly")
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                if debugger.isAttached {
                    // Range expansion buttons
                    Button("▲") {
                        Task { await debugger.expandDisassemblyRange(direction: .backward) }
                    }
                    .help("Load more instructions before current range")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("▼") {
                        Task { await debugger.expandDisassemblyRange(direction: .forward) }
                    }
                    .help("Load more instructions after current range")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Go To...") {
                        showingGotoDialog = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if !debugger.disassembly.isEmpty {
                        Button("Select All") {
                            selectAllInstructions()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Select all instructions (Cmd+A)")
                    }
                    
                    if !selectedAddresses.isEmpty {
                        Button("Copy (\(selectedAddresses.count))") {
                            copySelectedLines()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Clear") {
                            selectedAddresses.removeAll()
                            lastSelectedAddress = nil
                            print("🗑️ Selection cleared")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button("Refresh") {
                        Task { 
                            await debugger.refreshDisassembly() 
                            // Mark that we should focus on PC after refresh
                            // Removed shouldAutoFocusPC - using direct focus instead
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.trailing)
                }
            }
            .padding(.vertical, 8)
            
            Divider()
            
            // Info bar
            if debugger.isAttached {
                HStack {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Instructions: \(debugger.disassembly.count)")
                    }
                    
                    Spacer()
                    
                    if !selectedAddresses.isEmpty {
                        HStack {
                            Image(systemName: "selection.pin.in.out")
                                .foregroundColor(.green)
                            Text("Selected: \(selectedAddresses.count)")
                            
                            // Show range if more than one line selected
                            if selectedAddresses.count > 1 {
                                let sortedAddresses = selectedAddresses.sorted()
                                if let firstAddr = sortedAddresses.first, let lastAddr = sortedAddresses.last {
                                    Text("(\(String(format: "0x%llx", firstAddr)) - \(String(format: "0x%llx", lastAddr)))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else if selectedAddresses.count == 1, let addr = selectedAddresses.first {
                                // Show single selected instruction details
                                if let selectedLine = debugger.disassembly.first(where: { $0.address == addr }) {
                                    Text("(\(selectedLine.instruction) \(selectedLine.operands))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                    
                    if case .stopped(let reason) = debugger.state {
                        HStack {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(.orange)
                            Text("Stopped: \(reason)")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .font(.caption)
                
                Divider()
            }
            
            if debugger.disassembly.isEmpty {
                VStack {
                    Spacer()
                    Text(debugger.isAttached ? "No disassembly available" : "Attach to a process to view disassembly")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            // Breakpoint dots area (leftmost, like x64dbg)
                            BreakpointDotsView(
                                disassembly: debugger.disassembly,
                                breakpoints: debugger.breakpoints,
                                lineHeight: lineHeight
                            )
                            .frame(width: 20, height: CGFloat(debugger.disassembly.count) * lineHeight)
                            
                            // Jump visualization area (next to breakpoints)
                            JumpVisualizationView(
                                jumpTracker: jumpTracker,
                                lineHeight: lineHeight
                            )
                            .frame(width: 40, height: CGFloat(debugger.disassembly.count) * lineHeight)
                            .offset(x: 20)  // Offset by breakpoint area width
                            
                            // Main disassembly list - custom stack for precise row heights (optimized)
                            LazyVStack(alignment: .leading, spacing: 0) {
                                // Render all instructions for proper scrolling
                                ForEach(debugger.disassembly) { line in
                                                                    SimpleDisassemblyRow(
                                    line: line, 
                                    isActive: line.address == debugger.programCounter,
                                    isSelected: selectedAddresses.contains(line.address),
                                    debugger: debugger,
                                    jumpTracker: jumpTracker,
                                    onClicked: { modifiers in handleLineClick(address: line.address, modifiers: modifiers) },
                                    onDoubleClicked: { handleDoubleClick(address: line.address) },
                                    onAddressClicked: { targetAddress in
                                        // Navigate and then select the target
                                        Task {
                                            await debugger.navigateToAddress(targetAddress)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                // Select the target address once navigation is complete
                                                selectedAddresses.removeAll()
                                                selectedAddresses.insert(targetAddress)
                                                lastSelectedAddress = targetAddress
                                                print("🎯 Selected target address: \(String(format: "0x%llx", targetAddress))")
                                            }
                                        }
                                    },
                                    selectedAddresses: selectedAddresses
                                )
                                    .frame(height: lineHeight)
                                }
                            }
                            .padding(.leading, 60) // space for breakpoint dots + jump area
                        }
                    }
                    .onChange(of: debugger.programCounter) { newPC in
                        // CRITICAL: Debug and force focus
                        if newPC != 0 && newPC != lastProgramCounter {
                            lastProgramCounter = newPC
                            print("🎯 PC CHANGED: \(String(format: "0x%llx", newPC))")
                            
                            // Check if PC exists in current disassembly
                            let pcExists = debugger.disassembly.contains(where: { $0.address == newPC })
                            print("   PC exists in disassembly: \(pcExists)")
                            print("   Total instructions: \(debugger.disassembly.count)")
                            
                            if pcExists {
                                // Try immediate scroll first
                                print("   Attempting immediate scroll...")
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newPC, anchor: .center)
                                }
                            } else {
                                print("   ⚠️ PC not in current view - requesting refresh")
                            }
                        }
                    }
                    .onChange(of: debugger.disassembly) { newDisassembly in
                        print("🔄 Disassembly updated: \(newDisassembly.count) instructions")
                        
                        if newDisassembly.count > 0 {
                            let firstAddr = String(format: "0x%llx", newDisassembly.first!.address)
                            let lastAddr = String(format: "0x%llx", newDisassembly.last!.address)
                            print("   Range: \(firstAddr) to \(lastAddr)")
                        }
                        
                        jumpTracker.analyzeJumps(for: newDisassembly)
                        
                        // FORCE focus to current PC when disassembly updates
                        if debugger.programCounter != 0 {
                            let pcInNew = newDisassembly.contains(where: { $0.address == debugger.programCounter })
                            print("🎯 PC \(String(format: "0x%llx", debugger.programCounter)) in new disassembly: \(pcInNew)")
                            
                            if pcInNew {
                                print("   FORCING scroll to PC...")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(debugger.programCounter, anchor: .center)
                                    }
                                }
                            } else {
                                print("   ❌ PC not found in new disassembly!")
                            }
                        }
                    }
                    .onChange(of: debugger.disassemblyUpdateTrigger) { newTrigger in
                        if newTrigger != lastUpdateTrigger {
                            lastUpdateTrigger = newTrigger
                            print("🔥 FORCED UI UPDATE TRIGGER: \(newTrigger) - FORCING VIEW REFRESH")
                            
                            // Force complete view reconstruction
                            selectedAddresses.removeAll()
                            lastSelectedAddress = nil
                            
                            // Force jump tracker refresh to ensure UI updates
                            jumpTracker.analyzeJumps(for: debugger.disassembly)
                        }
                    }
                    .onChange(of: debugger.navigationTarget) { targetAddress in
                        // Handle navigation requests (e.g., from clicking jump targets)
                        if targetAddress != 0 && debugger.disassembly.contains(where: { $0.address == targetAddress }) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(targetAddress, anchor: .center)
                            }
                            print("🎯 Navigated to target address: \(String(format: "0x%llx", targetAddress))")
                            
                            // Clear the navigation target after use
                            DispatchQueue.main.async {
                                debugger.navigationTarget = 0
                            }
                        }
                    }
                    .onAppear {
                        if !debugger.disassembly.isEmpty {
                            print("🔄 Initial jump analysis on view appear")
                            jumpTracker.analyzeJumps(for: debugger.disassembly)
                            
                            // Focus on current PC if it exists in the view
                            if debugger.programCounter != 0 && 
                               debugger.disassembly.contains(where: { $0.address == debugger.programCounter }) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(debugger.programCounter, anchor: .center)
                                    }
                                    print("🎯 Initial focus to PC on view appear: \(String(format: "0x%llx", debugger.programCounter))")
                                }
                            }
                        }
                    }
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            selectAllInstructions()
        }
    }
    
    private func handleLineClick(address: UInt64, modifiers: NSEvent.ModifierFlags) {
        let isShiftClick = modifiers.contains(.shift)
        print("✅ CLICK: \(String(format: "0x%llx", address)) | Shift: \(isShiftClick)")
        
        if isShiftClick && lastSelectedAddress != nil {
            // Range selection with Shift+Click
            let lastAddr = lastSelectedAddress!
            let startAddr = min(lastAddr, address)
            let endAddr = max(lastAddr, address)
            
            // Select all addresses between start and end
            for line in debugger.disassembly {
                if line.address >= startAddr && line.address <= endAddr {
                    selectedAddresses.insert(line.address)
                }
            }
            print("📊 Range selected: \(String(format: "0x%llx", startAddr)) to \(String(format: "0x%llx", endAddr)) (\(selectedAddresses.count) lines)")
        } else {
            // Single selection (normal click) - just select and highlight jump
            selectedAddresses.removeAll()
            selectedAddresses.insert(address)
            lastSelectedAddress = address
            print("🎯 Single selected: \(String(format: "0x%llx", address))")
            
            // Highlight jump if this instruction has one
            jumpTracker.highlightJump(from: address)
        }
    }
    
    private func handleDoubleClick(address: UInt64) {
        print("🖱️ DOUBLE-CLICK: \(String(format: "0x%llx", address)) - TOGGLING BREAKPOINT (x64dbg style)")
        
        // x64dbg behavior: Double-click toggles breakpoint
        Task {
            await debugger.toggleBreakpoint(at: address)
        }
    }
    
    private func selectAllInstructions() {
        // Select all instructions in the current disassembly
        selectedAddresses.removeAll()
        for line in debugger.disassembly {
            selectedAddresses.insert(line.address)
        }
        if !debugger.disassembly.isEmpty {
            lastSelectedAddress = debugger.disassembly.last?.address
        }
        print("📋 Selected all \(selectedAddresses.count) instructions (Cmd+A)")
    }
    
    private func copySelectedLines() {
        let selectedLines = debugger.disassembly.filter { selectedAddresses.contains($0.address) }
            .sorted { $0.address < $1.address }
        
        var result = ""
        for line in selectedLines {
            let paddedBytes = line.bytes.padding(toLength: 20, withPad: " ", startingAt: 0)
            result += "\(line.formattedAddress) | \(paddedBytes) | \(line.instruction) \(line.operands)\n"
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
        
        showingCopyAlert = true
        print("📋 Copied \(selectedLines.count) lines to clipboard")
    }
}

// MARK: - Breakpoint Dots View (x64dbg style red dots)

struct BreakpointDotsView: View {
    let disassembly: [DisassemblyLine]
    let breakpoints: Set<UInt64>
    let lineHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            // Draw red dots for breakpoints exactly like x64dbg
            for (index, line) in disassembly.enumerated() {
                if breakpoints.contains(line.address) {
                    let centerY = CGFloat(index) * lineHeight + lineHeight / 2
                    let centerX: CGFloat = 10  // Center of the 20pt wide area
                    
                    // Red filled circle (x64dbg style) - enabled breakpoint
                    let circle = Circle()
                        .path(in: CGRect(x: centerX - 6, y: centerY - 6, width: 12, height: 12))
                    
                    // Solid red for enabled breakpoints
                    context.fill(circle, with: .color(.red))
                    
                    // Add a subtle border like x64dbg
                    context.stroke(circle, with: .color(.red.opacity(0.8)), lineWidth: 1)
                    
                    // Optional: Add small highlight for active breakpoint (if hit)
                    // TODO: Add support for disabled breakpoints (hollow red circle)
                }
            }
        }
    }
}

// Simple, reliable row component
private struct SimpleDisassemblyRow: View {
    let line: DisassemblyLine
    let isActive: Bool
    let isSelected: Bool
    @ObservedObject var debugger: DebuggerController
    @ObservedObject var jumpTracker: JumpTracker
    let onClicked: (NSEvent.ModifierFlags) -> Void
    let onDoubleClicked: () -> Void
    let onAddressClicked: (UInt64) -> Void
    let selectedAddresses: Set<UInt64>  // Add this to access selected addresses
    @State private var isEditing = false
    @State private var editedInstruction = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingFillDialog = false
    @State private var showingGoToDialog = false
    @State private var showingCommentDialog = false
    @State private var showingLabelDialog = false
    @State private var fillValue = ""
    @State private var fillCount = "1"
    @State private var gotoAddress = ""
    @State private var commentText = ""
    @State private var labelText = ""

    var body: some View {
        HStack(spacing: 12) {
            // Active pointer only (no checkboxes)
            Text(isActive ? "→" : "  ")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isActive ? .orange : .clear)
                .frame(width: 20)

            // Address
            Text(line.formattedAddress)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Instruction (e.g., jne, nop)", text: $editedInstruction)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))
                            
                            if !editedInstruction.isEmpty {
                                if let assembled = InstructionAssembler.assembleInstruction(editedInstruction) {
                                    Text("→ \(assembled)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                } else {
                                    Text("→ Unknown instruction")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button("Save") {
                            saveEdit()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSaveEdit())
                        
                        Button("Cancel") {
                            cancelEdit()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Original: \(line.instruction) \(line.operands)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                                                 Text("⚡ RUNTIME MEMORY PATCH - Binary file unchanged (like x64dbg)")
                             .font(.system(.caption2, design: .monospaced))
                             .foregroundColor(.green)
                    }
                }
            } else {
                HStack {
                    Text(line.bytes)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)

            Text(line.instruction)
                .font(.system(.body, design: .monospaced))
                .fontWeight(isActive ? .heavy : .bold)
                .foregroundColor(isActive ? .orange : getInstructionColor())
                .frame(width: 80, alignment: .leading)
                .onAppear {
                    // Debug: Print what instruction is being rendered
                    if line.instruction.lowercased().hasPrefix("j") && line.instruction.lowercased() != "jmp" {
                        print("🎨 UI RENDERING: \(line.formattedAddress) → '\(line.instruction)' (bytes: \(line.bytes))")
                    }
                }

            // Make operands clickable if they contain an address
            if let targetAddress = parseAddressFromOperands(line.operands) {
                Button(action: {
                    print("🖱️ OPERAND CLICKED: Navigate to \(String(format: "0x%llx", targetAddress))")
                    onAddressClicked(targetAddress)
                }) {
                    Text(line.operands)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue) // Blue for clickable addresses
                        .underline()
                }
                .buttonStyle(.plain)
                .frame(minWidth: 500, alignment: .leading)
            } else {
                Text(line.operands)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .frame(minWidth: 500, alignment: .leading)
            }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.2) : (isActive ? Color.orange.opacity(0.1) : Color.clear))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            print("🖱️ TAP DETECTED: \(String(format: "0x%llx", line.address))")
            let modifiers = NSEvent.modifierFlags
            onClicked(modifiers)
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    print("🖱️ DOUBLE-TAP DETECTED: \(String(format: "0x%llx", line.address))")
                    onDoubleClicked()
                }
        )
        .onLongPressGesture(minimumDuration: 0.5) {
            print("🖱️ LONG PRESS: \(String(format: "0x%llx", line.address))")
            startEdit()
        }
        .contextMenu {
            contextMenuContent
        }
        .alert("Edit Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingFillDialog) {
            FillDialog(
                fillValue: $fillValue,
                fillCount: $fillCount,
                onFill: performFill
            )
        }
        .sheet(isPresented: $showingGoToDialog) {
            GotoAddressDialog(
                address: $gotoAddress,
                onGoto: { address in
                    Task {
                        await debugger.getDisassemblyAt(address: address)
                    }
                }
            )
        }
        .sheet(isPresented: $showingCommentDialog) {
            CommentDialog(
                comment: $commentText,
                address: line.formattedAddress,
                onSave: { comment in
                    print("💬 Comment added at \(line.formattedAddress): \(comment)")
                    // TODO: Save comment to debugger
                }
            )
        }
        .sheet(isPresented: $showingLabelDialog) {
            LabelDialog(
                label: $labelText,
                address: line.formattedAddress,
                onSave: { label in
                    print("🏷️ Label set at \(line.formattedAddress): \(label)")
                    // TODO: Save label to debugger
                }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    // Helper to parse addresses from operands
    private func parseAddressFromOperands(_ operands: String) -> UInt64? {
        let trimmed = operands.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern 1: 0x followed by hex
        if trimmed.hasPrefix("0x") {
            return UInt64(trimmed.dropFirst(2), radix: 16)
        }
        
        // Pattern 2: Plain hex (8+ chars, likely an address)
        if trimmed.count >= 8, let address = UInt64(trimmed, radix: 16), address >= 0x1000 {
            return address
        }
        
        return nil
    }
    
    private func getInstructionColor() -> Color {
        let instruction = line.instruction.lowercased()
        
        // Check if this instruction has a jump target
        let hasJumpTarget = jumpTracker.getJumpTarget(for: line.address) != nil
        
        if hasJumpTarget {
            if instruction.hasPrefix("j") && instruction != "jmp" {
                return .blue  // Conditional jumps
            } else if instruction == "jmp" {
                return .green  // Unconditional jumps
            } else if instruction == "call" {
                return .purple  // Calls
            }
        }
        
        return Color(NSColor.labelColor)  // Default color
    }
    
    // MARK: - Context Menu Content
    
    @ViewBuilder
    private var contextMenuContent: some View {
                 // Runtime Memory Operations Section (like x64dbg)
         Button("⚡ Edit Instruction (Runtime Memory)") {
             startEdit()
         }
         .disabled(!debugger.isAttached || !isInStoppedState())
        
        // Quick mnemonic change menu for conditional jumps
        if line.instruction.lowercased().hasPrefix("j") && line.instruction.lowercased() != "jmp" {
            Menu("Change Jump Type") {
                Group {
                    Button("je/jz (Jump if Equal/Zero)") {
                        quickChangeJump(to: "je")
                    }
                    Button("jne/jnz (Jump if Not Equal/Zero)") {
                        quickChangeJump(to: "jne")
                    }
                    Button("ja (Jump if Above)") {
                        quickChangeJump(to: "ja")
                    }
                    Button("jb (Jump if Below)") {
                        quickChangeJump(to: "jb")
                    }
                    Button("jae (Jump if Above/Equal)") {
                        quickChangeJump(to: "jae")
                    }
                }
                
                Group {
                    Button("jbe (Jump if Below/Equal)") {
                        quickChangeJump(to: "jbe")
                    }
                    Button("jg (Jump if Greater)") {
                        quickChangeJump(to: "jg")
                    }
                    Button("jl (Jump if Less)") {
                        quickChangeJump(to: "jl")
                    }
                    Button("jge (Jump if Greater/Equal)") {
                        quickChangeJump(to: "jge")
                    }
                    Button("jle (Jump if Less/Equal)") {
                        quickChangeJump(to: "jle")
                    }
                }
                
                Divider()
                
                Button("jmp (Unconditional Jump)") {
                    quickChangeJump(to: "jmp")
                }
                Button("nop (No Operation)") {
                    quickChangeJump(to: "nop")
                }
            }
            .disabled(!debugger.isAttached || !isInStoppedState())
        }
        
                 Button("⚡ Fill Memory...") {
             showFillDialog()
         }
         .disabled(!debugger.isAttached || !isInStoppedState())
        
        Divider()
        
        copyOperationsMenu
        
        Divider()
        
        Group {
            breakpointMenu
            
            Divider()
            
            navigationMenu
            
            Button("Go to") {
                showGoToDialog()
            }
            
            Divider()
        }
        
        Group {
            analysisMenu
            
            Divider()
            
            searchMenu
            
            // Advanced section
            if debugger.isAttached {
                Divider()
                advancedMenu
            }
        }
    }
    
    @ViewBuilder
    private var copyOperationsMenu: some View {
        Menu("Copy") {
            Button("Selection") {
                copySelection()
            }
            
            Button("Address") {
                copyToClipboard(line.formattedAddress)
            }
            
            Button("RVA") {
                copyRVA()
            }
            
            Button("File Offset") {
                copyFileOffset()
            }
            
            Button("Instruction") {
                copyToClipboard("\(line.instruction) \(line.operands)")
            }
            
            Button("Bytes") {
                copyToClipboard(line.bytes)
            }
        }
    }
    
    @ViewBuilder
    private var breakpointMenu: some View {
        Menu("Breakpoint") {
            Button("Toggle Breakpoint") {
                toggleBreakpoint()
            }
            
            Button("Set Breakpoint") {
                setBreakpoint()
            }
            .disabled(hasBreakpoint())
            
            Button("Remove Breakpoint") {
                removeBreakpoint()
            }
            .disabled(!hasBreakpoint())
            
            Button("Enable/Disable Breakpoint") {
                toggleBreakpointEnabled()
            }
            .disabled(!hasBreakpoint())
        }
    }
    
    @ViewBuilder
    private var navigationMenu: some View {
        Menu("Follow in") {
            Button("Dump") {
                followInDump()
            }
            
            Button("Memory Map") {
                followInMemoryMap()
            }
            
            Button("Stack") {
                followInStack()
            }
        }
    }
    
    @ViewBuilder
    private var analysisMenu: some View {
        Menu("Analysis") {
            Button("Assemble") {
                startEdit()
            }
            .disabled(!debugger.isAttached || !isInStoppedState())
            
            Button("Graph") {
                showControlFlowGraph()
            }
            
            Button("Find References") {
                findReferences()
            }
            
            Button("Comment") {
                addComment()
            }
        }
    }
    
    @ViewBuilder
    private var searchMenu: some View {
        Menu("Search") {
            Button("Find Pattern...") {
                showFindDialog()
            }
            
            Button("Find References") {
                findReferences()
            }
            
            Button("Find String References") {
                findStringReferences()
            }
        }
    }
    
    @ViewBuilder
    private var advancedMenu: some View {
        Menu("Advanced") {
            Button("Set New Origin Here") {
                setNewOrigin()
            }
            
            Button("Create Function") {
                createFunction()
            }
            
            Button("Set Label") {
                setLabel()
            }
            
            Button("Set Bookmark") {
                setBookmark()
            }
        }
    }
    
    private func isInStoppedState() -> Bool {
        if case .stopped = debugger.state {
            return true
        }
        return false
    }
    
    private func startEdit() {
        guard debugger.isAttached && isInStoppedState() else {
            alertMessage = "Process must be attached and stopped to edit instructions"
            showingAlert = true
            return
        }
        
        // Initialize with current instruction
        editedInstruction = "\(line.instruction) \(line.operands)".trimmingCharacters(in: .whitespaces)
        isEditing = true
    }
    
    private func cancelEdit() {
        isEditing = false
        editedInstruction = ""
    }
    
    private func canSaveEdit() -> Bool {
        if editedInstruction.isEmpty {
            return false
        }
        
        // Check if it's a simple mnemonic change (like je -> jne)
        let (mnemonic, _) = editedInstruction.parseInstruction()
        
        // Allow any supported instruction
        if InstructionAssembler.isSupported(mnemonic) {
            return true
        }
        
        // Also allow any instruction that can be assembled
        if let assembled = InstructionAssembler.assembleInstruction(editedInstruction) {
            // Don't allow placeholder results like "??"
            return !assembled.contains("??")
        }
        
        return false
    }
    
    private func saveEdit() {
        guard !editedInstruction.isEmpty else {
            alertMessage = "Instruction cannot be empty"
            showingAlert = true
            return
        }
        
        // Try to assemble the instruction to bytes
        guard let assembledBytes = InstructionAssembler.assembleInstruction(editedInstruction) else {
            // Provide helpful error messages
            let (mnemonic, _) = editedInstruction.parseInstruction()
            if mnemonic.hasPrefix("j") {
                alertMessage = "Jump '\(mnemonic)' not recognized. Try: je, jne, jz, jnz, ja, jb, jg, jl, jge, jle, etc."
            } else {
                alertMessage = "Instruction '\(editedInstruction)' not supported. Available: nop, ret, int3, push/pop registers, conditional jumps."
            }
            showingAlert = true
            return
        }
        
        // Parse the assembled hex bytes
        let cleanBytes = assembledBytes.replacingOccurrences(of: " ", with: "")
        
        // Handle placeholder for relative jumps
        if cleanBytes.contains("?") {
            alertMessage = "Relative jumps with explicit targets not yet supported. Use simple mnemonics like 'jne' for now."
            showingAlert = true
            return
        }
        
        guard cleanBytes.count % 2 == 0 else {
            alertMessage = "Invalid assembled bytes format"
            showingAlert = true
            return
        }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: cleanBytes.count, by: 2) {
            let start = cleanBytes.index(cleanBytes.startIndex, offsetBy: i)
            let end = cleanBytes.index(start, offsetBy: 2)
            let byteString = String(cleanBytes[start..<end])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                alertMessage = "Invalid assembled hex byte: \(byteString)"
                showingAlert = true
                return
            }
            bytes.append(byte)
        }
        
        print("🔧 Assembling '\(editedInstruction)' → \(assembledBytes) → \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // Write bytes to memory
        Task {
            await debugger.writeBytes(address: line.address, bytes: bytes)
            // writeBytes now handles refresh internally
        }
        
        isEditing = false
        editedInstruction = ""
    }
    
    // MARK: - Context Menu Actions
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 Copied to clipboard: \(text)")
    }
    
    private func copySelection() {
        if selectedAddresses.isEmpty {
            // If no selection, copy current line
            let fullInstruction = "\(line.formattedAddress) | \(line.bytes.padding(toLength: 20, withPad: " ", startingAt: 0)) | \(line.instruction) \(line.operands)"
            copyToClipboard(fullInstruction)
        } else {
            // Copy all selected lines
            let selectedLines = debugger.disassembly.filter { selectedAddresses.contains($0.address) }
                .sorted { $0.address < $1.address }
            
            var result = ""
            for selectedLine in selectedLines {
                let paddedBytes = selectedLine.bytes.padding(toLength: 20, withPad: " ", startingAt: 0)
                result += "\(selectedLine.formattedAddress) | \(paddedBytes) | \(selectedLine.instruction) \(selectedLine.operands)\n"
            }
            
            copyToClipboard(result.trimmingCharacters(in: .newlines))
            print("📋 Context menu copied \(selectedLines.count) selected lines")
        }
    }
    
    private func copyRVA() {
        // For now, just copy the address - would need base address calculation for real RVA
        copyToClipboard(String(format: "0x%llx", line.address))
    }
    
    private func copyFileOffset() {
        // Would need file mapping information - placeholder for now
        copyToClipboard("File offset: 0x\(String(format: "%llx", line.address))")
    }
    
    // MARK: - Breakpoint Management
    
    private func hasBreakpoint() -> Bool {
        // TODO: Check if breakpoint exists at this address
        return false
    }
    
    private func toggleBreakpoint() {
        if hasBreakpoint() {
            removeBreakpoint()
        } else {
            setBreakpoint()
        }
    }
    
    private func setBreakpoint() {
        Task {
            await debugger.setBreakpoint(at: line.address)
            print("🔴 Breakpoint set at \(line.formattedAddress)")
        }
    }
    
    private func removeBreakpoint() {
        Task {
            await debugger.removeBreakpoint(at: line.address)
            print("⚪ Breakpoint removed at \(line.formattedAddress)")
        }
    }
    
    private func toggleBreakpointEnabled() {
        // TODO: Toggle breakpoint enabled/disabled state
        print("🟡 Toggle breakpoint enabled at \(line.formattedAddress)")
    }
    
    // MARK: - Navigation
    
    private func followInDump() {
        // TODO: Navigate to memory view at this address
        print("📍 Follow in dump: \(line.formattedAddress)")
    }
    
    private func followInMemoryMap() {
        // TODO: Show memory map view at this address
        print("🗺️ Follow in memory map: \(line.formattedAddress)")
    }
    
    private func followInStack() {
        // TODO: Navigate to stack view
        print("📚 Follow in stack: \(line.formattedAddress)")
    }
    
    private func showGoToDialog() {
        gotoAddress = line.formattedAddress
        showingGoToDialog = true
    }
    
    // MARK: - Analysis Tools
    
    private func showControlFlowGraph() {
        // TODO: Show control flow graph
        print("📊 Show control flow graph for \(line.formattedAddress)")
    }
    
    private func findReferences() {
        // TODO: Find all references to this address
        print("🔍 Find references to \(line.formattedAddress)")
    }
    
    private func findStringReferences() {
        // TODO: Find string references
        print("🔤 Find string references near \(line.formattedAddress)")
    }
    
    private func addComment() {
        commentText = ""
        showingCommentDialog = true
    }
    
    // MARK: - Advanced Operations
    
    private func setNewOrigin() {
        // TODO: Set new origin point for disassembly
        print("🎯 Set new origin at \(line.formattedAddress)")
    }
    
    private func createFunction() {
        // TODO: Create function at this address
        print("🏗️ Create function at \(line.formattedAddress)")
    }
    
    private func setLabel() {
        labelText = ""
        showingLabelDialog = true
    }
    
    private func setBookmark() {
        // TODO: Add bookmark at this address
        print("🔖 Bookmark added at \(line.formattedAddress)")
    }
    
    private func showFillDialog() {
        fillValue = "90" // Default to NOP
        fillCount = "1"
        showingFillDialog = true
    }
    
    private func showFindDialog() {
        // TODO: Show find pattern dialog
        print("🔍 Show find dialog starting from \(line.formattedAddress)")
    }
    
    private func performFill() {
        guard !fillValue.isEmpty, let count = Int(fillCount), count > 0 else {
            alertMessage = "Invalid fill parameters"
            showingAlert = true
            return
        }
        
        // Parse fill value as hex
        let cleanValue = fillValue.replacingOccurrences(of: " ", with: "")
        guard cleanValue.count % 2 == 0 else {
            alertMessage = "Fill value must be valid hex (e.g., 90, CCCC)"
            showingAlert = true
            return
        }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: cleanValue.count, by: 2) {
            let start = cleanValue.index(cleanValue.startIndex, offsetBy: i)
            let end = cleanValue.index(start, offsetBy: 2)
            let byteString = String(cleanValue[start..<end])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                alertMessage = "Invalid hex value: \(byteString)"
                showingAlert = true
                return
            }
            bytes.append(byte)
        }
        
        // Repeat the pattern for the specified count
        var fillBytes: [UInt8] = []
        for _ in 0..<count {
            fillBytes.append(contentsOf: bytes)
        }
        
        print("🔧 Filling \(fillBytes.count) bytes at \(line.formattedAddress) with pattern: \(fillValue)")
        
        Task {
            await debugger.writeBytes(address: line.address, bytes: fillBytes)
            // writeBytes now handles refresh internally
        }
    }
    
    /// Quick method to change jump instruction type (e.g., je -> jne)
    private func quickChangeJump(to newMnemonic: String) {
        guard debugger.isAttached && isInStoppedState() else {
            alertMessage = "❌ Process must be attached and stopped to edit instructions"
            showingAlert = true
            return
        }
        
        print("🔄 Starting quick change: '\(line.instruction)' → '\(newMnemonic)' at \(line.formattedAddress)")
        
        // Assemble the new instruction
        guard let assembledBytes = InstructionAssembler.assembleInstruction(newMnemonic) else {
            alertMessage = "❌ Failed to assemble instruction: \(newMnemonic). Supported instructions: je, jne, ja, jb, jae, jbe, jg, jl, jge, jle, jmp, nop"
            showingAlert = true
            print("❌ Assembly failed for: \(newMnemonic)")
            return
        }
        
        print("✅ Assembled '\(newMnemonic)' → \(assembledBytes)")
        
        // Parse the assembled hex bytes
        let cleanBytes = assembledBytes.replacingOccurrences(of: " ", with: "")
        
        guard cleanBytes.count % 2 == 0 else {
            alertMessage = "❌ Invalid assembled bytes format: \(assembledBytes)"
            showingAlert = true
            print("❌ Invalid bytes format: \(assembledBytes)")
            return
        }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: cleanBytes.count, by: 2) {
            let start = cleanBytes.index(cleanBytes.startIndex, offsetBy: i)
            let end = cleanBytes.index(start, offsetBy: 2)
            let byteString = String(cleanBytes[start..<end])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                alertMessage = "❌ Invalid assembled hex byte: \(byteString)"
                showingAlert = true
                print("❌ Invalid hex byte: \(byteString)")
                return
            }
            bytes.append(byte)
        }
        
        let hexString = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                 print("⚡ RUNTIME MEMORY PATCH: '\(line.instruction)' → '\(newMnemonic)' at \(line.formattedAddress)")
         print("   Original bytes: \(line.bytes)")
         print("   New bytes: \(hexString)")
         print("   ✅ TEMPORARY: Process memory only, binary file unchanged (like x64dbg)")
        
        // Write bytes to memory (memory-only, like x64dbg)
        Task {
            await debugger.writeBytes(address: line.address, bytes: bytes)
            // writeBytes now handles refresh internally
        }
    }
}

// Simple goto dialog
private struct GotoAddressDialog: View {
    @Binding var address: String
    let onGoto: (UInt64) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Go to Address")
                .font(.headline)
            
            TextField("Address (0x...)", text: $address)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Go") {
                    if let addr = parseAddress(address) {
                        onGoto(addr)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(parseAddress(address) == nil)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
    
    private func parseAddress(_ str: String) -> UInt64? {
        let clean = str.lowercased().replacingOccurrences(of: "0x", with: "")
        return UInt64(clean, radix: 16)
    }
}

// Fill dialog for memory operations
private struct FillDialog: View {
    @Binding var fillValue: String
    @Binding var fillCount: String
    let onFill: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Fill Memory")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Fill Value (hex):")
                TextField("90", text: $fillValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .help("Hex bytes to fill (e.g., 90 for NOP, CCCC for INT3)")
                
                Text("Count:")
                TextField("1", text: $fillCount)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .help("Number of times to repeat the pattern")
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Fill") {
                    onFill()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(fillValue.isEmpty || fillCount.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

// Comment dialog
private struct CommentDialog: View {
    @Binding var comment: String
    let address: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Comment")
                .font(.headline)
            
            Text("Address: \(address)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if #available(macOS 13.0, *) {
                TextField("Enter comment...", text: $comment, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)
            } else {
                TextField("Enter comment...", text: $comment)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    onSave(comment)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 350)
    }
}

// Label dialog
private struct LabelDialog: View {
    @Binding var label: String
    let address: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Set Label")
                .font(.headline)
            
            Text("Address: \(address)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("Label name...", text: $label)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("Enter a descriptive label for this address")
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    onSave(label)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}