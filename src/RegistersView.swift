import SwiftUI

struct RegistersView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var selectedCategory = "GPR"
    
    private let categories = ["GPR", "FPU", "MMX", "Memory", "Application Output"]
    
    var body: some View {
        HSplitView {
            categorySidebar
            mainContentArea
        }
    }
    
    @ViewBuilder
    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Categories")
                .font(.headline)
                .padding()
            
            Divider()
            
            List(categories, id: \.self) { category in
                Button(action: {
                    selectedCategory = category
                }) {
                    HStack {
                        Image(systemName: iconForCategory(category))
                            .foregroundColor(colorForCategory(category))
                            .frame(width: 16)
                        Text(category)
                            .font(.system(.body))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .background(selectedCategory == category ? Color.accentColor : Color.clear)
                .cornerRadius(4)
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 180, maxWidth: 220)
    }
    
    @ViewBuilder
    private var mainContentArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with category name and refresh
            HStack {
                Text(selectedCategory)
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                if debugger.isAttached && (selectedCategory == "GPR" || selectedCategory == "FPU") {
                    Button("Refresh") {
                        Task { await debugger.refreshRegisters() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.trailing)
                }
            }
            .padding(.vertical, 8)
            
            Divider()
            
            // Content based on selected category
            Group {
                switch selectedCategory {
                case "GPR":
                    GPRView(debugger: debugger)
                case "FPU":
                    FPUView(debugger: debugger)
                case "MMX":
                    MMXView(debugger: debugger)
                case "Memory":
                    MemoryConsoleView(debugger: debugger)
                case "Application Output":
                    ApplicationOutputView(debugger: debugger)
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "GPR": return "cpu"
        case "FPU": return "function"
        case "MMX": return "square.grid.3x3"
        case "Memory": return "memorychip"
        case "Application Output": return "doc.text"
        default: return "questionmark"
        }
    }
    
    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "GPR": return .blue
        case "FPU": return .green
        case "MMX": return .orange
        case "Memory": return .purple
        case "Application Output": return .gray
        default: return .primary
        }
    }
}

// MARK: - Individual Category Views

struct GPRView: View {
    @ObservedObject var debugger: DebuggerController
    
    private var gprRegisters: [(String, String)] {
        let gprNames = ["RAX", "RBX", "RCX", "RDX", "RSI", "RDI", "RSP", "RBP", "R8", "R9", "R10", "R11", "R12", "R13", "R14", "R15", "RIP", "RFLAGS"]
        return gprNames.compactMap { name in
            if let value = debugger.registers[name.lowercased()] ?? debugger.registers[name], !value.isEmpty {
                return (name, value)
            }
            // Only show registers with real data
            return nil
        }
    }
    
    var body: some View {
        if debugger.isAttached {
            if gprRegisters.isEmpty {
                VStack {
                    Spacer()
                    Text("No register data available")
                        .foregroundColor(.secondary)
                    Text("Process must be stopped to read registers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(gprRegisters, id: \.0) { register, value in
                            HStack {
                                Text(register)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .frame(width: 50, alignment: .leading)
                                    .foregroundColor(.secondary)
                                
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                    .padding()
                }
            }
        } else {
            VStack {
                Spacer()
                Text("Attach to a process to view registers")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

struct FPUView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "function")
                .font(.largeTitle)
                .foregroundColor(.green)
            Text("FPU Registers")
                .font(.headline)
            Text("Floating Point Unit registers will be displayed here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

struct MMXView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "square.grid.3x3")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("MMX Registers")
                .font(.headline)
            Text("MMX/SSE vector registers will be displayed here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

struct MemoryConsoleView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Memory dump area (simplified for now)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(stride(from: 0, to: min(debugger.memory.count, 20), by: 1)), id: \.self) { index in
                        if index < debugger.memory.count {
                            let line = debugger.memory[index]
                            HStack(spacing: 8) {
                                Text(line.address)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                
                                Text(line.bytes)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                                
                                Text(line.ascii)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            
            if debugger.memory.isEmpty && debugger.isAttached {
                VStack {
                    Spacer()
                    Text("No memory data available")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !debugger.isAttached {
                VStack {
                    Spacer()
                    Text("Attach to a process to view memory")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

struct DebuggerConsoleView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var commandInput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Console output
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(debugger.logs.enumerated()), id: \.offset) { index, log in
                            HStack {
                                Text("[\(index)]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .leading)
                                
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .onChange(of: debugger.logs.count) { _ in
                        if !debugger.logs.isEmpty {
                            proxy.scrollTo(debugger.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Command input
            HStack {
                TextField("Enter debugger command...", text: $commandInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        executeCommand()
                    }
                
                Button("Execute") {
                    executeCommand()
                }
                .buttonStyle(.borderedProminent)
                .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }
    
    private func executeCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        
        debugger.addLog("$ \(command)")
        
        // Handle basic commands
        switch command.lowercased() {
        case "help":
            debugger.addLog("Available commands: help, clear, registers, memory, disasm, continue, step")
        case "clear":
            // Would need to add a clear logs method to debugger
            debugger.addLog("Console cleared")
        case "registers", "reg":
            Task { await debugger.refreshRegisters() }
            debugger.addLog("Refreshing registers...")
        case "memory", "mem":
            debugger.addLog("Memory view updated")
        case "disasm":
            Task { await debugger.refreshDisassembly() }
            debugger.addLog("Refreshing disassembly...")
        default:
            debugger.addLog("Unknown command: \(command). Type 'help' for available commands.")
        }
        
        commandInput = ""
    }
}

struct ApplicationOutputView: View {
    @ObservedObject var debugger: DebuggerController
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Application Output")
                    .font(.headline)
                    .padding(.horizontal)
                
                Divider()
                
                if debugger.isAttached {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STDOUT:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Text("Application standard output will appear here...")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal)
                            .foregroundColor(.primary)
                        
                        Spacer(minLength: 20)
                        
                        Text("STDERR:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Text("Application error output will appear here...")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal)
                            .foregroundColor(.red)
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("Attach to a process to view application output")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}
