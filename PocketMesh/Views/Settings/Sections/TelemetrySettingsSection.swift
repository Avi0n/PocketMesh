import SwiftUI
import PocketMeshServices

/// Telemetry sharing configuration
struct TelemetrySettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var filterByTrusted = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    private var device: DeviceDTO? { appState.connectedDevice }

    var body: some View {
        Section {
            Toggle(isOn: telemetryEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Telemetry Requests")
                    Text("Required for other users to manually trace a path to you. Shares battery level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

            if device?.telemetryModeBase ?? 0 > 0 {
                Toggle(isOn: locationEnabledBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Location")
                        Text("Share GPS coordinates in telemetry")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .radioDisabled(for: appState.connectionState, or: isSaving)

                Toggle(isOn: environmentEnabledBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Environment Sensors")
                        Text("Share temperature, humidity, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .radioDisabled(for: appState.connectionState, or: isSaving)

                Toggle(isOn: $filterByTrusted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only Share with Trusted Contacts")
                        Text("Limit telemetry to selected contacts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .radioDisabled(for: appState.connectionState, or: isSaving)

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
            Text("When enabled, other nodes can request your device's telemetry data.")
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    // MARK: - Bindings

    private var telemetryEnabledBinding: Binding<Bool> {
        Binding(
            get: { device?.telemetryModeBase ?? 0 > 0 },
            set: { saveTelemetry(base: $0 ? 2 : 0) }
        )
    }

    private var locationEnabledBinding: Binding<Bool> {
        Binding(
            get: { device?.telemetryModeLoc ?? 0 > 0 },
            set: { saveTelemetry(location: $0 ? 2 : 0) }
        )
    }

    private var environmentEnabledBinding: Binding<Bool> {
        Binding(
            get: { device?.telemetryModeEnv ?? 0 > 0 },
            set: { saveTelemetry(environment: $0 ? 2 : 0) }
        )
    }

    // MARK: - Save

    private func saveTelemetry(
        base: UInt8? = nil,
        location: UInt8? = nil,
        environment: UInt8? = nil
    ) {
        guard let device, let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                let modes = TelemetryModes(
                    base: base ?? device.telemetryModeBase,
                    location: location ?? device.telemetryModeLoc,
                    environment: environment ?? device.telemetryModeEnv
                )
                _ = try await settingsService.setOtherParamsVerified(
                    autoAddContacts: !device.manualAddContacts,
                    telemetryModes: modes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? "Connection error",
                    onRetry: { saveTelemetry(base: base, location: location, environment: environment) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
