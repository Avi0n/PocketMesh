import SwiftUI
import PocketMeshServices

/// WiFi connection settings - shown when connected via WiFi instead of Bluetooth.
struct WiFiSection: View {
    @Environment(AppState.self) private var appState
    @State private var showingEditSheet = false
    @State private var isRenaming = false

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

            Button {
                renameDevice()
            } label: {
                HStack {
                    Text("Change Display Name")
                    Spacer()
                    if isRenaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRenaming)
        } header: {
            Text("WiFi")
        } footer: {
            Text("Your device's local network address")
        }
        .sheet(isPresented: $showingEditSheet) {
            WiFiEditSheet()
        }
    }

    private func renameDevice() {
        isRenaming = true
        Task { @MainActor in
            defer { isRenaming = false }
            // WiFi devices don't use AccessorySetupKit for naming.
            // Display name is stored in the connection method itself.
            // TODO: Implement rename dialog for WiFi devices when needed.
        }
    }
}

#Preview {
    List {
        WiFiSection()
    }
    .environment(AppState())
}
