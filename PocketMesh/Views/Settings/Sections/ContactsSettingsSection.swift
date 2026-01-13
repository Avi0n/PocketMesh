import SwiftUI
import PocketMeshServices

/// Auto-add contacts toggle
struct ContactsSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    private var device: DeviceDTO? { appState.connectedDevice }

    var body: some View {
        Section {
            Toggle(isOn: autoAddContactsBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Add Contacts")
                    Text("Automatically add contacts from received advertisements")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isSaving)
        } header: {
            Text("Contacts")
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    // MARK: - Binding

    private var autoAddContactsBinding: Binding<Bool> {
        Binding(
            get: { !(device?.manualAddContacts ?? true) },
            set: { saveAutoAdd(enabled: $0) }
        )
    }

    // MARK: - Save

    private func saveAutoAdd(enabled: Bool) {
        guard let device, let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                let modes = TelemetryModes(
                    base: device.telemetryModeBase,
                    location: device.telemetryModeLoc,
                    environment: device.telemetryModeEnv
                )
                _ = try await settingsService.setOtherParamsVerified(
                    autoAddContacts: enabled,
                    telemetryModes: modes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? "Connection error",
                    onRetry: { saveAutoAdd(enabled: enabled) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
