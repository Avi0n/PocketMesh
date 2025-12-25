import SwiftUI
import PocketMeshServices

/// Advanced settings sheet for power users
struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Manual Radio Configuration
                AdvancedRadioSection()

                // Contacts Settings
                ContactsSettingsSection()

                // Telemetry Settings
                TelemetrySettingsSection()

                // Battery Curve
                BatteryCurveSection()

                // Danger Zone
                DangerZoneSection()
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        }
        .task {
            await refreshDeviceSettings()
        }
    }

    /// Fetch fresh device settings to ensure cache is up-to-date
    private func refreshDeviceSettings() async {
        guard let settingsService = appState.services?.settingsService else { return }
        _ = try? await settingsService.getSelfInfo()
    }
}
