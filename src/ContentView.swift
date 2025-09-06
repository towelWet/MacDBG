import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var debugger = DebuggerController()
    @State private var showingExportDialog = false
    
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
                
                Spacer()
                
                StatusView(debugger: debugger)
            }
            .frame(minWidth: 220, maxWidth: 280)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            
            // Main workspace with 4 panels (original layout)
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
                        
                        DisassemblyView(debugger: debugger)
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