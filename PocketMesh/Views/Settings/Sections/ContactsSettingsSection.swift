import SwiftUI
import PocketMeshServices

/// Auto-add contacts toggle
struct ContactsSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var autoAddContacts = true
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    var body: some View {
        Section {
            Toggle(isOn: $autoAddContacts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Add Contacts")
                    Text("Automatically add contacts from received advertisements")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: autoAddContacts) { _, newValue in
                updateAutoAdd(newValue)
            }
            .disabled(isSaving)
        } header: {
            Text("Contacts")
        }
        .onAppear {
            if let device = appState.connectedDevice {
                // manualAddContacts is inverted
                autoAddContacts = !device.manualAddContacts
            }
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private func updateAutoAdd(_ enabled: Bool) {
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
                    autoAddContacts: enabled,
                    telemetryModes: telemetryModes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                autoAddContacts = !enabled // Revert
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { updateAutoAdd(enabled) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                autoAddContacts = !enabled // Revert
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
