import SwiftUI

/// Container view for diagnostic and analysis tools
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    TracePathView()
                } label: {
                    Label("Trace Path", systemImage: "point.3.connected.trianglepath.dotted")
                }

                NavigationLink {
                    LineOfSightView()
                } label: {
                    Label("Line of Sight", systemImage: "eye")
                }

                NavigationLink {
                    RxLogView()
                } label: {
                    Label("RX Log", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            .navigationTitle("Tools")
        }
    }
}

#Preview {
    ToolsView()
        .environment(AppState())
}
