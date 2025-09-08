import SwiftUI

struct ProcessListView: View {
    @ObservedObject var debugger: DebuggerController
    @State private var searchText = ""
    @State private var showUserProcessesOnly = false
    @State private var showingFilePicker = false
    
    var filteredProcesses: [ProcessInfo] {
        // If searching, don't hide anything via the user-only toggle
        let base = (searchText.isEmpty && showUserProcessesOnly) ?
            debugger.processes.filter { $0.name != "kernel_task" && !$0.name.hasPrefix("com.apple.") } :
            debugger.processes

        if searchText.isEmpty {
            return base
        } else {
            return base.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                String($0.pid).contains(searchText)
            }
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
            
            Toggle("User processes only", isOn: $showUserProcessesOnly)
                .font(.caption)
            
            List(filteredProcesses) { process in
                ProcessRowView(process: process, debugger: debugger)
            }
            .listStyle(.sidebar)
            .frame(maxHeight: 300)
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
