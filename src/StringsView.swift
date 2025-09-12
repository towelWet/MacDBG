import SwiftUI

/// StringsView that mimics Ghidra's string analysis behavior exactly
struct StringsView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var searchText = ""
    @State private var selectedStringAddress: UInt64? = nil
    @State private var lastTapTime: Date? = nil
    
    // Filter strings based on search text
    private var filteredStrings: [StringData] {
        if searchText.isEmpty {
            return debugger.strings
        } else {
            return debugger.strings.filter { string in
                string.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Ghidra-style controls
            HStack {
                Text("Strings")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(filteredStrings.count) strings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Refresh") {
                    Task {
                        await debugger.extractStrings()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!debugger.isAttached)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Search bar (like Ghidra)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search strings...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            Divider()
            
            // Strings list (exactly like Ghidra's string window)
            if filteredStrings.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "text.cursor")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        if debugger.isAttached {
                            Text("No strings found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Try refreshing or check the target binary")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No process attached")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Attach to a process to view strings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredStrings, id: \.address) { string in
                        StringRowView(
                            string: string,
                            isSelected: selectedStringAddress == string.address,
                            onTap: { handleStringTap(string) },
                            onDoubleClick: { handleStringDoubleClick(string) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if debugger.isAttached && debugger.strings.isEmpty {
                Task {
                    await debugger.extractStrings()
                }
            }
        }
    }
    
    // MARK: - Ghidra-style String Navigation
    
    /// Single click: Navigate to FIRST code reference (like Ghidra's "Go To" functionality)
    private func handleStringTap(_ string: StringData) {
        print("🎯🎯🎯 STRING TAP: Address: 0x\(String(format: "%llx", string.address))")
        print("🎯 String content: '\(string.content)'")
        print("🎯 String length: \(string.length)")
        print("🎯 CRITICAL: Navigating to CODE that references this string, NOT the string data itself")
        
        selectedStringAddress = string.address
        debugger.navigateToStringReference(string.address)
    }
    
    /// Double click: Find ALL references and show in XRef panel (like Ghidra's XRef window)
    private func handleStringDoubleClick(_ string: StringData) {
        print("🎯 Double-click: Finding ALL references to string 0x\(String(format: "%llx", string.address))")
        selectedStringAddress = string.address
        debugger.findStringReferences(string.address)
    }
}

/// Individual string row that mimics Ghidra's string display format
struct StringRowView: View {
    let string: StringData
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleClick: () -> Void
    
    @State private var lastTapTime: Date? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            // Address column (like Ghidra)
            Text("0x\(String(format: "%llx", string.address))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Length column (like Ghidra)
            Text("\(string.length)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            // Type indicator (like Ghidra)
            HStack(spacing: 4) {
                Image(systemName: string.length > 1 ? "textformat" : "character")
                    .font(.caption2)
                    .foregroundColor(.blue)
                Text(string.length > 10 ? "STRING" : "str")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(3)
            }
            .frame(width: 60, alignment: .leading)
            
            // String content (like Ghidra's string display)
            Text(displayString)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < 0.4 {
                // Double-click detected
                onDoubleClick()
                lastTapTime = nil
            } else {
                // Single click
                onTap()
            }
            lastTapTime = now
        }
        .contextMenu {
            Button("Go to String Reference") {
                onTap()
            }
            Button("Find All References") {
                onDoubleClick()
            }
            Divider()
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("0x\(String(format: "%llx", string.address))", forType: .string)
            }
            Button("Copy String") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string.content, forType: .string)
            }
        }
    }
    
    /// Format string for display (like Ghidra does)
    private var displayString: String {
        let content = string.content
        
        // Escape special characters for display (like Ghidra)
        let escaped = content
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        // Add quotes around the string (like Ghidra)
        return "\"\(escaped)\""
    }
}

// Preview removed for compatibility
