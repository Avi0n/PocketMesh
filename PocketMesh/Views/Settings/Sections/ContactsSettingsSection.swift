import SwiftUI
import PocketMeshKit

/// Auto-add contacts toggle
struct ContactsSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var autoAddContacts = true
    @State private var showError: String?

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
    }

    private func updateAutoAdd(_ enabled: Bool) {
        guard let device = appState.connectedDevice else { return }

        Task {
            do {
                let telemetryModes = TelemetryModes(
                    base: TelemetryMode(rawValue: device.telemetryModeBase) ?? .deny,
                    location: TelemetryMode(rawValue: device.telemetryModeLoc) ?? .deny,
                    environment: TelemetryMode(rawValue: device.telemetryModeEnv) ?? .deny
                )
                try await appState.settingsService.setOtherParams(
                    autoAddContacts: enabled,
                    telemetryModes: telemetryModes,
                    shareLocationPublicly: device.advertLocationPolicy == 1,
                    multiAcks: device.multiAcks
                )
                await appState.refreshDeviceInfo()
            } catch {
                autoAddContacts = !enabled // Revert
                showError = error.localizedDescription
            }
        }
    }
}
