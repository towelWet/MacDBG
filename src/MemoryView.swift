import SwiftUI

struct MemoryView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var addressInput = ""
    @State private var bytesToRead = 256
    @State private var selectedLines: Set<String> = []
    @State private var selectionStart: String? = nil
    @State private var showingCopyAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Memory Dump")
                    .font(.headline)
                    .padding(.leading, 8)
                
                Spacer()
                
                if debugger.isAttached {
                    HStack {
                        TextField("Address (0x...)", text: $addressInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        
                        Stepper("Bytes: \(bytesToRead)", value: $bytesToRead, in: 16...2048, step: 16)
                            .frame(width: 120)
                        
                        Button("Read") {
                            Task { await debugger.readMemory(address: addressInput, bytes: bytesToRead) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if !selectedLines.isEmpty {
                            Button("Copy (\(selectedLines.count))") {
                                copySelectedMemory()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("Clear") {
                                selectedLines.removeAll()
                                selectionStart = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.trailing)
                }
            }
            .padding(.vertical, 8)
            
            Divider()
            
            if debugger.memory.isEmpty {
                VStack {
                    Spacer()
                    Text(debugger.isAttached ? "Enter an address to read memory" : "Attach to a process to view memory")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Address")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .frame(width: 140, alignment: .leading)
                            .foregroundColor(.secondary)
                        
                        // Hex offset header
                        HStack(spacing: 16) {
                            ForEach(0..<16, id: \.self) { offset in
                                Text(String(format: "%02X", offset))
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .center)
                            }
                        }
                        
                        Spacer()
                        
                        Text("ASCII")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .center)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    List(debugger.memory) { line in
                        EnhancedMemoryRow(
                            line: line,
                            isSelected: selectedLines.contains(line.address),
                            onSelectionChanged: { address, isSelected in
                                handleMemorySelection(address: address, isSelected: isSelected)
                            }
                        )
                    }
                    .listStyle(.plain)
                }
            }
        }
        .alert("Copied to Clipboard", isPresented: $showingCopyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Selected memory has been copied to clipboard")
        }
    }
    
    private func handleMemorySelection(address: String, isSelected: Bool) {
        if isSelected {
            // Handle range selection with Shift
            if NSEvent.modifierFlags.contains(.shift), let start = selectionStart {
                // Select range from start to current address
                let sortedAddresses = debugger.memory.map { $0.address }
                guard let startIndex = sortedAddresses.firstIndex(of: start),
                      let endIndex = sortedAddresses.firstIndex(of: address) else { return }
                
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                for i in range {
                    selectedLines.insert(sortedAddresses[i])
                }
            } else {
                // Handle multi-selection with Cmd
                if NSEvent.modifierFlags.contains(.command) {
                    selectedLines.insert(address)
                } else {
                    // Single selection
                    selectedLines = [address]
                }
                selectionStart = address
            }
        } else {
            selectedLines.remove(address)
            if selectedLines.isEmpty {
                selectionStart = nil
            }
        }
    }
    
    private func copySelectedMemory() {
        let sortedSelected = selectedLines.sorted { addr1, addr2 in
            // Extract numeric part for proper sorting
            let num1 = UInt64(addr1.dropFirst(2), radix: 16) ?? 0
            let num2 = UInt64(addr2.dropFirst(2), radix: 16) ?? 0
            return num1 < num2
        }
        
        let selectedMemory = debugger.memory.filter { sortedSelected.contains($0.address) }
            .sorted { line1, line2 in
                let num1 = UInt64(line1.address.dropFirst(2), radix: 16) ?? 0
                let num2 = UInt64(line2.address.dropFirst(2), radix: 16) ?? 0
                return num1 < num2
            }
        
        let formattedText = formatMemoryForCopy(selectedMemory)
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedText, forType: .string)
        
        showingCopyAlert = true
    }
    
    private func formatMemoryForCopy(_ lines: [MemoryLine]) -> String {
        var result = "MacDBG Memory Export\n"
        result += "===================\n"
        result += "Range: \(lines.first?.address ?? "N/A") - \(lines.last?.address ?? "N/A")\n"
        result += "Lines: \(lines.count)\n\n"
        
        result += "Address          | Bytes                            | ASCII\n"
        result += "-----------------|----------------------------------|------------------\n"
        
        for line in lines {
            // Safe string formatting without C format specifiers
            let paddedBytes = line.bytes.padding(toLength: 32, withPad: " ", startingAt: 0)
            result += "\(line.address) | \(paddedBytes) | \(line.ascii)\n"
        }
        
        result += "\n--- End of Export ---"
        return result
    }
}

private struct MemoryRow: View {
    let line: MemoryLine
    let isSelected: Bool
    let onSelectionChanged: (String, Bool) -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                onSelectionChanged(line.address, !isSelected)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            
            Text(line.address)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 120, alignment: .leading)
            
            Text(line.bytes)
                .font(.system(.body, design: .monospaced))
                .frame(width: 300, alignment: .leading)
            
            Text(line.ascii)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
                
            Spacer()
        }
        .padding(.vertical, 1)
        .listRowBackground(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contextMenu {
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.address, forType: .string)
            }
            
            Button("Copy Bytes") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.bytes, forType: .string)
            }
            
            Button("Copy ASCII") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.ascii, forType: .string)
            }
        }
    }
}

// Enhanced memory row with proper hex dump formatting like Hopper
private struct EnhancedMemoryRow: View {
    let line: MemoryLine
    let isSelected: Bool
    let onSelectionChanged: (String, Bool) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Selection indicator
            Button(action: {
                onSelectionChanged(line.address, !isSelected)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            
            // Address
            Text(line.address)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 120, alignment: .leading)
            
            // Hex bytes in 16-byte format
            HStack(spacing: 16) {
                let bytesArray = parseHexBytes(line.bytes)
                ForEach(0..<16, id: \.self) { index in
                    Text(index < bytesArray.count ? bytesArray[index] : "  ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(index < bytesArray.count ? .primary : .clear)
                        .frame(width: 24, alignment: .center)
                }
            }
            
            Spacer()
            
            // ASCII representation
            Text(line.ascii)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
                .frame(width: 140, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contextMenu {
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.address, forType: .string)
            }
            
            Button("Copy Hex") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.bytes, forType: .string)
            }
            
            Button("Copy ASCII") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.ascii, forType: .string)
            }
            
            Button("Copy Full Line") {
                let fullLine = "\(line.address) | \(line.bytes) | \(line.ascii)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullLine, forType: .string)
            }
        }
    }
    
    private func parseHexBytes(_ hexString: String) -> [String] {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        var bytes: [String] = []
        
        for i in stride(from: 0, to: cleanHex.count, by: 2) {
            let start = cleanHex.index(cleanHex.startIndex, offsetBy: i)
            let end = cleanHex.index(start, offsetBy: min(2, cleanHex.count - i))
            bytes.append(String(cleanHex[start..<end]).uppercased())
        }
        
        return bytes
    }
}
