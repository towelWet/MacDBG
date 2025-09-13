import SwiftUI

struct ProcessListView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var searchText = ""
    @State private var showUserProcessesOnly = false
    @State private var showingFilePicker = false
    @State private var filteredProcesses: [ProcessInfo] = []
    
    private let logger = LoggingSystem.shared
    
    private func updateFilteredProcesses() {
        do {
            logger.log("🔍 updateFilteredProcesses called - searchText: '\(searchText)', showUserProcessesOnly: \(showUserProcessesOnly)", category: .ui)
            
        let allProcesses = debugger.processes
        logger.log("📊 Total processes available: \(allProcesses.count)", category: .ui)
        
        // Debug: Log first few process names for debugging
        if allProcesses.count > 0 {
            let firstFew = allProcesses.prefix(5).map { $0.name }.joined(separator: ", ")
            logger.log("🔍 First few processes: \(firstFew)", category: .ui)
        }
            
            // If searching, filter by search term
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let searchTerm = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                logger.log("🔍 Searching for: '\(searchTerm)'", category: .ui)
                
                
                let filtered = allProcesses.filter { process in
                    let nameMatch = process.name.lowercased().contains(searchTerm)
                    let pidMatch = String(process.pid).contains(searchTerm)
                    return nameMatch || pidMatch
                }
                
                logger.log("✅ Search completed - found \(filtered.count) matches", category: .ui)
                filteredProcesses = filtered
                logger.log("✅ filteredProcesses updated successfully", category: .ui)
                return
            }
            
            // If user processes only is checked, filter out some system processes
            if showUserProcessesOnly {
                logger.log("👤 Filtering for user processes only", category: .ui)
                let filtered = allProcesses.filter { process in
                    !process.name.hasPrefix("kernel") && 
                    !process.name.hasPrefix("com.apple.")
                }
                logger.log("✅ User filter completed - found \(filtered.count) user processes", category: .ui)
                filteredProcesses = filtered
                logger.log("✅ filteredProcesses updated successfully", category: .ui)
                return
            }
            
            // Otherwise return all processes
            logger.log("📋 Returning all \(allProcesses.count) processes", category: .ui)
            filteredProcesses = allProcesses
            logger.log("✅ filteredProcesses updated successfully", category: .ui)
            
        } catch {
            logger.log("❌ ERROR in updateFilteredProcesses: \(error.localizedDescription)", category: .error)
            logger.logCrash(error, context: "ProcessListView.updateFilteredProcesses")
            filteredProcesses = []
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Processes")
                    .font(.headline)
                Spacer()
                Button("🚀 Launch Binary") {
                    showingFilePicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Launch binary file (safe - original file untouched)")
                Button("Refresh") {
                    debugger.refreshProcessList()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            TextField("Search processes...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { newValue in
                    logger.log("🔍 Search text changed to '\(newValue)'", category: .ui)
                    // Debounce the search to prevent excessive calls
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        updateFilteredProcesses()
                    }
                }
            
            Toggle("User processes only", isOn: $showUserProcessesOnly)
                .font(.caption)
                .onChange(of: showUserProcessesOnly) { _ in
                    updateFilteredProcesses()
                }
            
            if filteredProcesses.isEmpty {
                VStack {
                    Text("No processes found")
                        .foregroundColor(.secondary)
                    Text("Total processes: \(debugger.processes.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Clear Search") {
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxHeight: 300)
            } else {
                if filteredProcesses.isEmpty {
                    VStack {
                        Text("No processes found")
                            .foregroundColor(.secondary)
                        Text("Total processes: \(debugger.processes.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Clear Search") {
                            searchText = ""
                            updateFilteredProcesses()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxHeight: 300)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredProcesses) { process in
                                ProcessRowView(process: process, debugger: debugger)
                                    .onAppear {
                                        logger.log("📋 Process row appeared: \(process.name)", category: .ui)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onAppear {
                        logger.log("📋 ScrollView appeared with \(filteredProcesses.count) processes", category: .ui)
                    }
                }
            }
        }
        .onAppear {
            logger.log("📋 ProcessListView appeared", category: .ui)
            updateFilteredProcesses()
        }
        .onChange(of: debugger.processes) { _ in
            logger.log("📋 Process list changed, updating filtered processes", category: .ui)
            updateFilteredProcesses()
        }
        .task {
            logger.log("📋 ProcessListView task started", category: .ui)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.executable, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await debugger.launchBinary(path: url.path)
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }
}

struct ProcessRowView: View {
    let process: ProcessInfo
    @ObservedObject var debugger: DebuggerController
    
    private let logger = LoggingSystem.shared
    
    var isCurrentTarget: Bool {
        debugger.currentPID == process.pid
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isCurrentTarget ? .blue : .primary)
                
                Text("PID: \(process.pid)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCurrentTarget {
                Image(systemName: "target")
                    .foregroundColor(.blue)
            } else {
                Button("Attach") {
                    logger.log("🔗 Attach button clicked for process: \(process.name) (PID: \(process.pid))", category: .ui)
                    Task {
                        await debugger.attach(to: process.pid)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(debugger.isAttached)
            }
        }
        .padding(.vertical, 2)
    }
}
