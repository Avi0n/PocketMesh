import SwiftUI
import PocketMeshServices

/// Auto-add mode and type settings for node discovery
struct NodesSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isApplying = false
    @State private var showSuccess = false

    // Local state for editing
    @State private var autoAddMode: AutoAddMode = .manual
    @State private var autoAddContacts = false
    @State private var autoAddRepeaters = false
    @State private var autoAddRoomServers = false
    @State private var overwriteOldest = false

    private var device: DeviceDTO? { appState.connectedDevice }

    /// Whether the device supports v1.12+ auto-add config features
    private var supportsAutoAddConfig: Bool {
        device?.supportsAutoAddConfig ?? false
    }

    private var settingsModified: Bool {
        guard let device else { return false }
        if device.supportsAutoAddConfig {
            return autoAddMode != device.autoAddMode ||
                autoAddContacts != device.autoAddContacts ||
                autoAddRepeaters != device.autoAddRepeaters ||
                autoAddRoomServers != device.autoAddRoomServers ||
                overwriteOldest != device.overwriteOldest
        } else {
            let deviceMode: AutoAddMode = device.manualAddContacts ? .manual : .all
            return autoAddMode != deviceMode
        }
    }

    private var canApply: Bool {
        appState.connectionState == .ready && settingsModified && !isApplying && !showSuccess
    }

    /// Combined hash of all node settings for change detection
    private var deviceNodeSettingsHash: Int {
        var hasher = Hasher()
        hasher.combine(appState.connectedDevice?.autoAddMode)
        hasher.combine(appState.connectedDevice?.autoAddContacts)
        hasher.combine(appState.connectedDevice?.autoAddRepeaters)
        hasher.combine(appState.connectedDevice?.autoAddRoomServers)
        hasher.combine(appState.connectedDevice?.overwriteOldest)
        hasher.combine(appState.connectedDevice?.supportsAutoAddConfig)
        return hasher.finalize()
    }

    var body: some View {
        Section {
            Picker(L10n.Settings.Nodes.autoAddMode, selection: $autoAddMode) {
                Text(L10n.Settings.Nodes.AutoAddMode.manual).tag(AutoAddMode.manual)
                if supportsAutoAddConfig {
                    Text(L10n.Settings.Nodes.AutoAddMode.selectedTypes).tag(AutoAddMode.selectedTypes)
                }
                Text(L10n.Settings.Nodes.AutoAddMode.all).tag(AutoAddMode.all)
            }
            .onChange(of: autoAddMode) { _, newValue in
                if newValue == .selectedTypes {
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
            }

            if supportsAutoAddConfig && autoAddMode == .selectedTypes {
                Toggle(L10n.Settings.Nodes.autoAddContacts, isOn: $autoAddContacts)
                Toggle(L10n.Settings.Nodes.autoAddRepeaters, isOn: $autoAddRepeaters)
                Toggle(L10n.Settings.Nodes.autoAddRoomServers, isOn: $autoAddRoomServers)
            }

            if supportsAutoAddConfig {
                Toggle(isOn: $overwriteOldest) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Settings.Nodes.overwriteOldest)
                        Text(L10n.Settings.Nodes.overwriteOldestDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                applySettings()
            } label: {
                HStack {
                    Spacer()
                    if isApplying {
                        ProgressView()
                    } else if showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(L10n.Settings.AdvancedRadio.apply)
                            .foregroundStyle(canApply ? Color.accentColor : .secondary)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: showSuccess)
            }
            .radioDisabled(for: appState.connectionState, or: isApplying || showSuccess || !settingsModified)
        } header: {
            Text(L10n.Settings.Nodes.header)
        } footer: {
            Text(autoAddModeDescription)
        }
        .radioDisabled(for: appState.connectionState, or: isApplying)
        .onAppear {
            loadFromDevice()
        }
        .onChange(of: deviceNodeSettingsHash) { _, _ in
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

        if device.supportsAutoAddConfig {
            autoAddMode = device.autoAddMode
            autoAddContacts = device.autoAddContacts
            autoAddRepeaters = device.autoAddRepeaters
            autoAddRoomServers = device.autoAddRoomServers
            overwriteOldest = device.overwriteOldest
        } else {
            // Older firmware only supports manual/all toggle via manualAddContacts
            autoAddMode = device.manualAddContacts ? .manual : .all
            autoAddContacts = false
            autoAddRepeaters = false
            autoAddRoomServers = false
            overwriteOldest = false
        }
    }

    private func applySettings() {
        guard !isApplying else { return }
        guard let device, let settingsService = appState.services?.settingsService else { return }

        isApplying = true
        Task {
            do {
                // Protocol: manualAddContacts=true for .manual and .selectedTypes, false only for .all
                let manualAdd = autoAddMode != .all

                // Save manualAddContacts (works on all firmware versions)
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

                // Save autoAddConfig only on v1.12+ firmware
                if device.supportsAutoAddConfig {
                    var config: UInt8 = 0
                    if overwriteOldest { config |= 0x01 }

                    switch autoAddMode {
                    case .manual:
                        break
                    case .selectedTypes:
                        if autoAddContacts { config |= 0x02 }
                        if autoAddRepeaters { config |= 0x04 }
                        if autoAddRoomServers { config |= 0x08 }
                    case .all:
                        break
                    }

                    _ = try await settingsService.setAutoAddConfigVerified(config)
                }

                retryAlert.reset()
                isApplying = false

                withAnimation {
                    showSuccess = true
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation {
                    showSuccess = false
                }
                return
            } catch let error as SettingsServiceError where error.isRetryable {
                loadFromDevice()
                retryAlert.show(
                    message: error.errorDescription ?? L10n.Localizable.Common.Error.connectionError,
                    onRetry: { applySettings() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                loadFromDevice()
                showError = error.localizedDescription
            }
            isApplying = false
        }
    }
}
