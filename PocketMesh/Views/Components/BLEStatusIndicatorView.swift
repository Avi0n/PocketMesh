import SwiftUI
import PocketMeshKit

/// BLE connection status indicator for toolbar display
/// Shows connection state via color-coded icon with menu details
struct BLEStatusIndicatorView: View {
    @Environment(AppState.self) private var appState
    @State private var showingDeviceSelection = false

    var body: some View {
        Menu {
            // Device info section (informational)
            if let device = appState.connectedDevice {
                Section {
                    Label(device.nodeName, systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            // Actions
            Section {
                Button {
                    showingDeviceSelection = true
                } label: {
                    Label(
                        appState.connectedDevice != nil ? "Change Device" : "Connect Device",
                        systemImage: "gearshape"
                    )
                }

                if appState.connectedDevice != nil {
                    Button(role: .destructive) {
                        Task {
                            await appState.disconnect()
                        }
                    } label: {
                        Label("Disconnect", systemImage: "eject")
                    }
                }
            }
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isAnimating)
        }
        .accessibilityLabel("Bluetooth connection status")
        .accessibilityValue(statusTitle)
        .accessibilityHint("Shows device connection options")
        .sheet(isPresented: $showingDeviceSelection) {
            DeviceSelectionSheet()
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch appState.connectionState {
        case .disconnected, .scanning:
            "antenna.radiowaves.left.and.right.slash"
        case .connecting, .connected, .ready:
            "antenna.radiowaves.left.and.right"
        }
    }

    private var iconColor: Color {
        switch appState.connectionState {
        case .disconnected, .scanning:
            .secondary
        case .connecting, .connected:
            .blue
        case .ready:
            .green
        }
    }

    private var isAnimating: Bool {
        appState.connectionState == .connecting || appState.connectionState == .scanning
    }

    private var statusTitle: String {
        switch appState.connectionState {
        case .disconnected:
            "Disconnected"
        case .scanning:
            "Scanning..."
        case .connecting:
            "Connecting..."
        case .connected:
            "Connected"
        case .ready:
            "Ready"
        }
    }
}

#Preview("Disconnected") {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
            }
    }
    .environment(AppState())
}
