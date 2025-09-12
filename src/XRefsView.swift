import SwiftUI

/// Cross-References View that mimics Ghidra's XRef window exactly
struct XRefsView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var selectedReference: StringReference? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (like Ghidra's XRef window)
            HStack {
                Text("Cross-References")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if debugger.selectedStringAddress != nil {
                    Text("to 0x\(String(format: "%llx", debugger.selectedStringAddress!))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No string selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Refresh") {
                    if let stringAddr = debugger.selectedStringAddress {
                        debugger.findStringReferences(stringAddr)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(debugger.selectedStringAddress == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Cross-references list (exactly like Ghidra's XRef display)
            if debugger.stringReferences.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        if debugger.selectedStringAddress != nil {
                            Text("No string references found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Click on a string to view its cross-references")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No string selected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Click on a string to view its cross-references")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            } else {
                List {
                    ForEach(debugger.stringReferences, id: \.address) { reference in
                        XRefRowView(
                            reference: reference,
                            isSelected: selectedReference?.address == reference.address,
                            onTap: { handleReferenceTap(reference) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Ghidra-style Reference Navigation
    
    /// Navigate to the code location that references the string (like Ghidra)
    private func handleReferenceTap(_ reference: StringReference) {
        print("🎯 XRef TAP: Navigating to code reference at 0x\(String(format: "%llx", reference.address))")
        print("🎯 Instruction: \(reference.instruction)")
        print("🎯 Module: \(reference.module)")
        
        selectedReference = reference
        Task {
            await debugger.navigateToAddress(reference.address)
        }
    }
}

/// Individual cross-reference row that mimics Ghidra's XRef display
struct XRefRowView: View {
    let reference: StringReference
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Reference type icon (like Ghidra)
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            // Address column (like Ghidra)
            Text("0x\(String(format: "%llx", reference.address))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .leading)
            
            // Instruction column (like Ghidra)
            Text(reference.instruction)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // Module column (like Ghidra)
            Text(reference.module)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Go to Reference") {
                onTap()
            }
            Divider()
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("0x\(String(format: "%llx", reference.address))", forType: .string)
            }
            Button("Copy Instruction") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reference.instruction, forType: .string)
            }
        }
    }
}

// Preview removed for compatibility
