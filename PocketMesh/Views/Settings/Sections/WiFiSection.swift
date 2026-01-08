import SwiftUI
import PocketMeshServices

/// WiFi connection settings - shown when connected via WiFi instead of Bluetooth.
struct WiFiSection: View {
    @Environment(AppState.self) private var appState
    @Binding var showingEditSheet: Bool

    private var currentConnection: ConnectionMethod? {
        appState.connectedDevice?.connectionMethods.first { $0.isWiFi }
    }

    var body: some View {
        Section {
            if case .wifi(let host, let port, _) = currentConnection {
                LabeledContent("Address", value: host)
                LabeledContent("Port", value: "\(port)")
            }

            Button("Edit Connection") {
                showingEditSheet = true
            }
        } header: {
            Text("WiFi")
        } footer: {
            Text("Your device's local network address")
        }
    }
}

#Preview {
    @Previewable @State var showingEditSheet = false
    List {
        WiFiSection(showingEditSheet: $showingEditSheet)
    }
    .environment(AppState())
}
