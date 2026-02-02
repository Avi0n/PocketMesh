import SwiftUI
import PocketMeshServices

/// Auto-add mode and type settings for node discovery
struct NodesSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    // Local state for editing
    @State private var autoAddMode: AutoAddMode = .manual
    @State private var autoAddContacts = false
    @State private var autoAddRepeaters = false
    @State private var autoAddRoomServers = false
    @State private var overwriteOldest = false

    private var device: DeviceDTO? { appState.connectedDevice }

    var body: some View {
        Section {
            Picker(L10n.Settings.Nodes.autoAddMode, selection: $autoAddMode) {
                Text(L10n.Settings.Nodes.AutoAddMode.manual).tag(AutoAddMode.manual)
                Text(L10n.Settings.Nodes.AutoAddMode.selectedTypes).tag(AutoAddMode.selectedTypes)
                Text(L10n.Settings.Nodes.AutoAddMode.all).tag(AutoAddMode.all)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)
            .onChange(of: autoAddMode) { _, newValue in
                // Announce for VoiceOver when type toggles appear
                if newValue == .selectedTypes {
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
                saveSettings()
            }
        } header: {
            Text(L10n.Settings.Nodes.header)
        } footer: {
            Text(autoAddModeDescription)
        }

        if autoAddMode == .selectedTypes {
            Section {
                Toggle(L10n.Settings.Nodes.autoAddContacts, isOn: $autoAddContacts)
                    .onChange(of: autoAddContacts) { _, _ in saveSettings() }

                Toggle(L10n.Settings.Nodes.autoAddRepeaters, isOn: $autoAddRepeaters)
                    .onChange(of: autoAddRepeaters) { _, _ in saveSettings() }

                Toggle(L10n.Settings.Nodes.autoAddRoomServers, isOn: $autoAddRoomServers)
                    .onChange(of: autoAddRoomServers) { _, _ in saveSettings() }
            } header: {
                Text(L10n.Settings.Nodes.AutoAddTypes.header)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)
        }

        Section {
            Toggle(isOn: $overwriteOldest) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Settings.Nodes.overwriteOldest)
                    Text(L10n.Settings.Nodes.overwriteOldestDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)
            .onChange(of: overwriteOldest) { _, _ in saveSettings() }
        } header: {
            Text(L10n.Settings.Nodes.Storage.header)
        }
        .onAppear {
            loadFromDevice()
        }
        .onChange(of: device?.autoAddConfig) { _, _ in
            loadFromDevice()
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private var autoAddModeDescription: String {
        switch autoAddMode {
        case .manual:
            return L10n.Settings.Nodes.AutoAddMode.manualDescription
        case .selectedTypes:
            return L10n.Settings.Nodes.AutoAddMode.selectedTypesDescription
        case .all:
            return L10n.Settings.Nodes.AutoAddMode.allDescription
        }
    }

    private func loadFromDevice() {
        guard let device else { return }
        autoAddMode = device.autoAddMode
        autoAddContacts = device.autoAddContacts
        autoAddRepeaters = device.autoAddRepeaters
        autoAddRoomServers = device.autoAddRoomServers
        overwriteOldest = device.overwriteOldest
    }

    private func saveSettings() {
        guard !isSaving else { return }  // Guard against rapid-fire saves
        guard let device, let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                // Build config bitmask
                var config: UInt8 = 0
                if overwriteOldest { config |= 0x01 }

                // Set type bits based on mode
                switch autoAddMode {
                case .manual:
                    // No type bits - user reviews all in Discover
                    break
                case .selectedTypes:
                    // Set only selected type bits
                    if autoAddContacts { config |= 0x02 }
                    if autoAddRepeaters { config |= 0x04 }
                    if autoAddRoomServers { config |= 0x08 }
                case .all:
                    // Type bits ignored by firmware when manualAddContacts=false
                    break
                }

                // Protocol: manualAddContacts=true for .manual and .selectedTypes, false only for .all
                let manualAdd = autoAddMode != .all

                // Save manualAddContacts first
                let modes = TelemetryModes(
                    base: device.telemetryModeBase,
                    location: device.telemetryModeLoc,
                    environment: device.telemetryModeEnv
                )
                _ = try await settingsService.setOtherParamsVerified(
                    autoAddContacts: !manualAdd,
                    telemetryModes: modes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )

                // Save autoAddConfig
                _ = try await settingsService.setAutoAddConfigVerified(config)

                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                // On any error, reload from device to ensure UI matches firmware state
                loadFromDevice()
                retryAlert.show(
                    message: error.errorDescription ?? "Connection error",
                    onRetry: { saveSettings() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                // Reload from device on failure to revert local state
                loadFromDevice()
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
