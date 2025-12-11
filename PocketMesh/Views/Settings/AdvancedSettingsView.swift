import SwiftUI
import PocketMeshKit

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

                // Danger Zone
                DangerZoneSection()
            }
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
