import OSLog
import SwiftUI
import TipKit
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "BLEStatus")

/// BLE connection status indicator for toolbar display
/// Shows connection state via color-coded icon with menu details
struct BLEStatusIndicatorView: View {
    @Environment(\.appState) private var appState
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
        .accessibilityLabel(L10n.Settings.BleStatus.accessibilityLabel)
        .accessibilityValue(statusTitle)
        .accessibilityHint(L10n.Settings.BleStatus.AccessibilityHint.disconnected)
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
                    Label(L10n.Settings.BleStatus.sendZeroHopAdvert, systemImage: "dot.radiowaves.right")
                }
                .radioDisabled(for: appState.connectionState, or: isSendingAdvert)
                .accessibilityHint(L10n.Settings.BleStatus.SendZeroHopAdvert.hint)

                Button {
                    sendAdvert(flood: true)
                } label: {
                    Label(L10n.Settings.BleStatus.sendFloodAdvert, systemImage: "dot.radiowaves.left.and.right")
                }
                .radioDisabled(for: appState.connectionState, or: isSendingAdvert)
                .accessibilityHint(L10n.Settings.BleStatus.SendFloodAdvert.hint)
            }

            // Actions
            Section {
                Button {
                    showingDeviceSelection = true
                } label: {
                    Label(L10n.Settings.BleStatus.changeDevice, systemImage: "gearshape")
                }

                Button(role: .destructive) {
                    Task {
                        await appState.disconnect()
                    }
                } label: {
                    Label(L10n.Settings.BleStatus.disconnect, systemImage: "eject")
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
        .accessibilityLabel(L10n.Settings.BleStatus.accessibilityLabel)
        .accessibilityValue(statusTitle)
        .accessibilityHint(L10n.Settings.BleStatus.AccessibilityHint.connected)
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
            L10n.Settings.BleStatus.Status.disconnected
        case .connecting:
            L10n.Settings.BleStatus.Status.connecting
        case .connected:
            L10n.Settings.BleStatus.Status.connected
        case .ready:
            L10n.Settings.BleStatus.Status.ready
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
    .environment(\.appState, AppState())
}
