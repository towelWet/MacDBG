import SwiftUI

struct DebuggerToolbar: View {
    @EnvironmentObject var engine: DebugEngine

    var body: some View {
        HStack {
            Button(action: { NotificationCenter.default.post(name: .startDebug, object: nil) }) {
                Image(systemName: "play.fill")
            }
            .help("Start Debugging (⇧⌘R)")
            .disabled(engine.executablePath == nil || engine.isDebugging)

            Divider()

            Button(action: { NotificationCenter.default.post(name: .stepInto, object: nil) }) {
                Image(systemName: "arrow.down.to.line.compact")
            }
            .help("Step Into (F7)")
            .disabled(!engine.isDebugging || engine.isRunning)

            Button(action: { NotificationCenter.default.post(name: .stepOver, object: nil) }) {
                Image(systemName: "arrow.right.to.line.compact")
            }
            .help("Step Over (F8)")
            .disabled(!engine.isDebugging || engine.isRunning)
            
            Button(action: { NotificationCenter.default.post(name: .continueExecution, object: nil) }) {
                Image(systemName: "play.circle.fill")
            }
            .help("Continue (F9)")
            .disabled(!engine.isDebugging || engine.isRunning)

            Spacer()
            
            Text(engine.isDebugging ? "Debugging" : "Not Debugging")
                .font(.headline)
                .foregroundColor(engine.isDebugging ? .green : .red)
        }
        .padding()
    }
}

struct DebuggerSidebar: View {
    @EnvironmentObject var engine: DebugEngine

    var body: some View {
        VStack(alignment: .leading) {
            Text("Registers")
                .font(.headline)
            RegisterView()
            Divider()
            Text("Executable")
                .font(.headline)
            Text(engine.executablePath ?? "None")
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding()
    }
}

struct RegisterView: View {
    @EnvironmentObject var engine: DebugEngine

    var body: some View {
        List(engine.registers) { reg in
            HStack {
                Text(reg.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                Spacer()
                Text(reg.value)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .listStyle(.plain)
    }
}


struct ConsoleView: View {
    @EnvironmentObject var engine: DebugEngine

    var body: some View {
        VStack(alignment: .leading) {
            Text("Console")
                .font(.headline)
                .padding([.leading, .top])
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(engine.consoleLog) { entry in
                        HStack {
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(entry.color)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
