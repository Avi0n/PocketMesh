import SwiftUI
import PocketMeshKit

/// Radio preset selector with region-based filtering
struct RadioPresetSection: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPresetID: String?
    @State private var isApplying = false
    @State private var showError: String?
    @State private var hasInitialized = false

    private var presets: [RadioPreset] {
        RadioPresets.presetsForLocale()
    }

    private var currentPreset: RadioPreset? {
        guard let device = appState.connectedDevice else { return nil }
        return RadioPresets.matchingPreset(
            frequencyKHz: device.frequency,
            bandwidthKHz: device.bandwidth,
            spreadingFactor: device.spreadingFactor,
            codingRate: device.codingRate
        )
    }

    var body: some View {
        Section {
            Picker("Radio Preset", selection: $selectedPresetID) {
                Text("Custom").tag(nil as String?)

                ForEach(RadioRegion.allCases, id: \.self) { region in
                    let regionPresets = presets.filter { $0.region == region }
                    if !regionPresets.isEmpty {
                        Section(region.rawValue) {
                            ForEach(regionPresets) { preset in
                                Text(preset.name).tag(preset.id as String?)
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedPresetID) { _, newValue in
                // Skip the initial value set from onAppear
                guard hasInitialized else { return }
                // Apply if user selected a preset (newValue is non-nil)
                guard let newID = newValue else { return }
                applyPreset(id: newID)
            }
            .disabled(isApplying)

            if let preset = presets.first(where: { $0.id == selectedPresetID }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.frequencyMHz, format: .number.precision(.fractionLength(3)))
                        .font(.caption.monospacedDigit()) +
                    Text(" MHz \u{2022} SF\(preset.spreadingFactor) \u{2022} BW\(preset.bandwidthKHz, format: .number) \u{2022} CR\(preset.codingRate)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Radio")
        } footer: {
            Text("Choose a preset matching your region. All mesh devices must use the same settings.")
        }
        .onAppear {
            selectedPresetID = currentPreset?.id
            // Mark as initialized after setting initial value
            // Using task to defer to next run loop, after onChange processes
            Task { @MainActor in
                hasInitialized = true
            }
        }
        .errorAlert($showError)
    }

    private func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }

        isApplying = true
        Task {
            do {
                try await appState.settingsService.applyRadioPreset(preset)
                await appState.refreshDeviceInfo()
            } catch {
                showError = error.localizedDescription
                selectedPresetID = currentPreset?.id // Revert
            }
            isApplying = false
        }
    }
}
