import SwiftUI
import PocketMeshServices

/// Auto-add nodes toggle
struct ContactsSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    private var device: DeviceDTO? { appState.connectedDevice }

    var body: some View {
        Section {
            Toggle(isOn: autoAddNodesBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Add Nodes")
                    Text("Automatically add nodes from received advertisements")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)
        } header: {
            Text("Nodes")
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    // MARK: - Binding

    private var autoAddNodesBinding: Binding<Bool> {
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
