import SwiftUI
import PocketMeshKit

/// Telemetry sharing configuration
struct TelemetrySettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var allowTelemetryRequests = false
    @State private var includeLocation = false
    @State private var includeEnvironment = false
    @State private var filterByTrusted = false
    @State private var showError: String?

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

                Toggle(isOn: $filterByTrusted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only Share with Trusted Contacts")
                        Text("Limit telemetry to selected contacts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }
        allowTelemetryRequests = device.telemetryModeBase > 0
        includeLocation = device.telemetryModeLoc > 0
        includeEnvironment = device.telemetryModeEnv > 0
    }

    private func updateTelemetry() {
        guard let device = appState.connectedDevice else { return }

        Task {
            do {
                let modes = TelemetryModes(
                    base: allowTelemetryRequests ? .allowAll : .deny,
                    location: includeLocation ? .allowAll : .deny,
                    environment: includeEnvironment ? .allowAll : .deny
                )
                try await appState.settingsService.setOtherParams(
                    autoAddContacts: !device.manualAddContacts,
                    telemetryModes: modes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )
                await appState.refreshDeviceInfo()
            } catch {
                loadCurrentSettings() // Revert on error
                showError = error.localizedDescription
            }
        }
    }
}
