import SwiftUI

struct MinimalContentView: View {
    @StateObject private var debugger = MinimalDebuggerController()
    
    var body: some View {
        VStack {
            Text("MacDBG - Minimal Version")
                .font(.title)
                .padding()
            
            Text("Status: \(debugger.status)")
                .padding()
            
            Button("Test Attach") {
                Task {
                    await debugger.attach(to: 1234)
                }
            }
            .padding()
            
            Button("Test Detach") {
                debugger.detach()
            }
            .padding()
            
            Button("Add Log") {
                debugger.addManualLog("Test log entry")
            }
            .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(debugger.logs.enumerated()), id: \.offset) { index, log in
                        Text(log)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 200)
            .border(Color.gray)
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}

struct MinimalContentView_Previews: PreviewProvider {
    static var previews: some View {
        MinimalContentView()
    }
}
