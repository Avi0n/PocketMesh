import OSLog
import SwiftUI
import TipKit
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "BLEStatus")

/// BLE connection status indicator for toolbar display
/// Shows connection state via color-coded icon with menu details
struct BLEStatusIndicatorView: View {
    @Environment(AppState.self) private var appState
    @State private var showingDeviceSelection = false
    @State private var isSendingAdvert = false
    @State private var successFeedbackTrigger = false
    @State private var errorFeedbackTrigger = false

    private let floodAdvertTip = SendFloodAdvertTip()

    var body: some View {
        Group {
            if appState.connectedDevice != nil {
                // Connected: show menu with device info and actions
                connectedMenu
            } else {
                // Disconnected: button that directly opens device selection
                disconnectedButton
            }
        }
        .sheet(isPresented: $showingDeviceSelection) {
            DeviceSelectionSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - View Components

    /// Button shown when disconnected - tap to open device selection
    private var disconnectedButton: some View {
        Button {
            showingDeviceSelection = true
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isAnimating)
        }
        .accessibilityLabel("Bluetooth connection status")
        .accessibilityValue(statusTitle)
        .accessibilityHint("Double tap to connect device")
    }

    /// Menu shown when connected - tap to show device info and actions
    private var connectedMenu: some View {
        Menu {
            // Device info section
            if let device = appState.connectedDevice {
                Section {
                    VStack(alignment: .leading) {
                        Label(device.nodeName, systemImage: "antenna.radiowaves.left.and.right")
                        if let battery = appState.deviceBattery {
                            Label(
                                "\(battery.percentage(using: appState.activeBatteryOCVArray))% (\(battery.voltage, format: .number.precision(.fractionLength(2)))v)",
                                systemImage: battery.iconName(using: appState.activeBatteryOCVArray)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Advert section
            Section {
                Button {
                    sendAdvert(flood: false)
                } label: {
                    Label("Send Zero-Hop Advert", systemImage: "dot.radiowaves.right")
                }
                .disabled(isSendingAdvert)
                .accessibilityHint("Broadcasts to direct neighbors only")

                Button {
                    sendAdvert(flood: true)
                } label: {
                    Label("Send Flood Advert", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(isSendingAdvert)
                .accessibilityHint("Floods advertisement across entire mesh")
            }

            // Actions
            Section {
                Button {
                    showingDeviceSelection = true
                } label: {
                    Label("Change Device", systemImage: "gearshape")
                }

                Button(role: .destructive) {
                    Task {
                        await appState.disconnect()
                    }
                } label: {
                    Label("Disconnect", systemImage: "eject")
                }
            }
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isAnimating)
        }
        .popoverTip(floodAdvertTip, arrowEdge: .top)
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
        .accessibilityLabel("Bluetooth connection status")
        .accessibilityValue(statusTitle)
        .accessibilityHint("Shows device connection options")
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch appState.connectionState {
        case .disconnected:
            "antenna.radiowaves.left.and.right.slash"
        case .connecting, .connected, .ready:
            "antenna.radiowaves.left.and.right"
        }
    }

    private var iconColor: Color {
        switch appState.connectionState {
        case .disconnected:
            .secondary
        case .connecting, .connected:
            .blue
        case .ready:
            .green
        }
    }

    private var isAnimating: Bool {
        appState.connectionState == .connecting
    }

    private var statusTitle: String {
        switch appState.connectionState {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting..."
        case .connected:
            "Connected"
        case .ready:
            "Ready"
        }
    }

    // MARK: - Actions

    private func sendAdvert(flood: Bool) {
        floodAdvertTip.invalidate(reason: .actionPerformed)
        guard !isSendingAdvert else { return }
        isSendingAdvert = true

        Task {
            do {
                _ = try await appState.services?.advertisementService.sendSelfAdvertisement(flood: flood)
                successFeedbackTrigger.toggle()
            } catch {
                logger.error("Failed to send advert (flood=\(flood)): \(error.localizedDescription)")
                errorFeedbackTrigger.toggle()
            }
            isSendingAdvert = false
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
