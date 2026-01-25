import SwiftUI
import MapKit
import PocketMeshServices

/// Node name and location settings
struct NodeSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var showingLocationPicker: Bool
    @State private var nodeName: String = ""
    @State private var isEditingName = false
    @State private var shareLocation = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false
    @State private var copyHapticTrigger = 0

    var body: some View {
        Section {
            // Node Name
            HStack {
                Label(L10n.Settings.Node.name, systemImage: "person.text.rectangle")
                Spacer()
                Button(appState.connectedDevice?.nodeName ?? L10n.Settings.Node.unknown) {
                    nodeName = appState.connectedDevice?.nodeName ?? ""
                    isEditingName = true
                }
                .foregroundStyle(.secondary)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

            // Public Key (copy)
            if let device = appState.connectedDevice {
                Button {
                    copyHapticTrigger += 1
                    let hex = device.publicKey.map { String(format: "%02X", $0) }.joined()
                    UIPasteboard.general.string = hex
                } label: {
                    HStack {
                        Label {
                            Text(L10n.Settings.DeviceInfo.publicKey)
                        } icon: {
                            Image(systemName: "key")
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Text(L10n.Settings.Node.copy)
                            .foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            }

            // Location
            Button {
                showingLocationPicker = true
            } label: {
                HStack {
                    Label {
                        Text(L10n.Settings.Node.setLocation)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    if let device = appState.connectedDevice,
                       device.latitude != 0 || device.longitude != 0 {
                        Text(L10n.Settings.Node.locationSet)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.Settings.Node.locationNotSet)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .radioDisabled(for: appState.connectionState, or: isSaving)

            // Share Location Toggle
            Toggle(isOn: $shareLocation) {
                Label(L10n.Settings.Node.shareLocationPublicly, systemImage: "location")
            }
            .onChange(of: shareLocation) { _, newValue in
                updateShareLocation(newValue)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

        } header: {
            Text(L10n.Settings.Node.header)
        } footer: {
            Text(L10n.Settings.Node.footer)
        }
        .onAppear {
            if let device = appState.connectedDevice {
                shareLocation = device.advertLocationPolicy == 1
            }
        }
        .alert(L10n.Settings.Node.Alert.EditName.title, isPresented: $isEditingName) {
            TextField(L10n.Settings.Node.name, text: $nodeName)
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
            Button(L10n.Localizable.Common.save) {
                saveNodeName()
            }
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
    }

    private func saveNodeName() {
        let name = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                _ = try await settingsService.setNodeNameVerified(name)
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { saveNodeName() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func updateShareLocation(_ share: Bool) {
        guard let device = appState.connectedDevice,
              let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                let telemetryModes = TelemetryModes(
                    base: device.telemetryModeBase,
                    location: device.telemetryModeLoc,
                    environment: device.telemetryModeEnv
                )
                _ = try await settingsService.setOtherParamsVerified(
                    autoAddContacts: !device.manualAddContacts,
                    telemetryModes: telemetryModes,
                    shareLocationPublicly: share,
                    multiAcks: device.multiAcks
                )
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                shareLocation = !share // Revert
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { updateShareLocation(share) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                shareLocation = !share // Revert
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
