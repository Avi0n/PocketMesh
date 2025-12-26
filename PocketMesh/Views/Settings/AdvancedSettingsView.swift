import SwiftUI
import PocketMeshServices

/// Advanced settings sheet for power users
struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOCVPreset: OCVPreset = .liIon
    @State private var ocvValues: [Int] = OCVPreset.liIon.ocvArray

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
                BatteryCurveSection(
                    availablePresets: OCVPreset.selectablePresets,
                    headerText: "Battery Curve",
                    footerText: "Configure the voltage-to-percentage curve for your device's battery.",
                    selectedPreset: $selectedOCVPreset,
                    voltageValues: $ocvValues,
                    onSave: saveOCVToDevice
                )

                // Danger Zone
                DangerZoneSection()
            }
            .scrollDismissesKeyboard(.interactively)
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
        .task(id: appState.connectedDevice?.id) {
            loadOCVFromDevice()
        }
    }

    /// Fetch fresh device settings to ensure cache is up-to-date
    private func refreshDeviceSettings() async {
        guard let settingsService = appState.services?.settingsService else { return }
        _ = try? await settingsService.getSelfInfo()
    }

    private func loadOCVFromDevice() {
        guard let device = appState.connectedDevice else { return }

        if let presetName = device.ocvPreset {
            if presetName == OCVPreset.custom.rawValue, let customString = device.customOCVArrayString {
                let parsed = customString.split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parsed.count == 11 {
                    ocvValues = parsed
                    selectedOCVPreset = .custom
                    return
                }
            }
            if let preset = OCVPreset(rawValue: presetName) {
                selectedOCVPreset = preset
                ocvValues = preset.ocvArray
                return
            }
        }

        selectedOCVPreset = .liIon
        ocvValues = OCVPreset.liIon.ocvArray
    }

    private func saveOCVToDevice(preset: OCVPreset, values: [Int]) async {
        guard let deviceService = appState.services?.deviceService,
              let deviceID = appState.connectedDevice?.id else { return }

        if preset == .custom {
            let customString = values.map(String.init).joined(separator: ",")
            try? await deviceService.updateOCVSettings(
                deviceID: deviceID,
                preset: OCVPreset.custom.rawValue,
                customArray: customString
            )
        } else {
            try? await deviceService.updateOCVSettings(
                deviceID: deviceID,
                preset: preset.rawValue,
                customArray: nil
            )
        }
    }
}
