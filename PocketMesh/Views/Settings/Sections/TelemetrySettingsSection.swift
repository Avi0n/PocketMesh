import SwiftUI
import PocketMeshKit

/// Telemetry sharing configuration
struct TelemetrySettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var allowTelemetryRequests = false
    @State private var includeLocation = false
    @State private var includeEnvironment = false
    @State private var filterByTrusted = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    var body: some View {
        Section {
            Toggle(isOn: $allowTelemetryRequests) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Telemetry Requests")
                    Text("Share basic device telemetry with other nodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: allowTelemetryRequests) { _, _ in
                updateTelemetry()
            }
            .disabled(isSaving)

            if allowTelemetryRequests {
                Toggle(isOn: $includeLocation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Location")
                        Text("Share GPS coordinates in telemetry")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: includeLocation) { _, _ in
                    updateTelemetry()
                }
                .disabled(isSaving)

                Toggle(isOn: $includeEnvironment) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Environment Sensors")
                        Text("Share temperature, humidity, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: includeEnvironment) { _, _ in
                    updateTelemetry()
                }
                .disabled(isSaving)

                Toggle(isOn: $filterByTrusted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only Share with Trusted Contacts")
                        Text("Limit telemetry to selected contacts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isSaving)

                if filterByTrusted {
                    NavigationLink {
                        TrustedContactsPickerView()
                    } label: {
                        Text("Manage Trusted Contacts")
                    }
                }
            }
        } header: {
            Text("Telemetry")
        } footer: {
            Text("Telemetry data helps other nodes monitor mesh health.")
        }
        .onAppear {
            loadCurrentSettings()
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }
        allowTelemetryRequests = device.telemetryModeBase > 0
        includeLocation = device.telemetryModeLoc > 0
        includeEnvironment = device.telemetryModeEnv > 0
    }

    private func updateTelemetry() {
        guard let device = appState.connectedDevice else { return }

        isSaving = true
        Task {
            do {
                let modes = TelemetryModes(
                    base: allowTelemetryRequests ? .allowAll : .deny,
                    location: includeLocation ? .allowAll : .deny,
                    environment: includeEnvironment ? .allowAll : .deny
                )
                let (deviceInfo, selfInfo) = try await appState.withSyncActivity {
                    try await appState.settingsService.setOtherParamsVerified(
                        autoAddContacts: !device.manualAddContacts,
                        telemetryModes: modes,
                        shareLocationPublicly: device.advertLocationPolicy == 1,
                        multiAcks: device.multiAcks
                    )
                }
                appState.updateDeviceInfo(deviceInfo, selfInfo)
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                loadCurrentSettings() // Revert on error
                retryAlert.show(
                    message: error.localizedDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { updateTelemetry() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                loadCurrentSettings() // Revert on error
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
