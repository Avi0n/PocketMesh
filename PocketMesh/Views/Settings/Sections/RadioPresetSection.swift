import SwiftUI
import PocketMeshServices

/// Radio preset selector with region-based filtering
struct RadioPresetSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresetID: String?
    @State private var isApplying = false
    @State private var showError: String?
    @State private var hasInitialized = false
    @State private var retryAlert = RetryAlertState()

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
                // Only show Custom when device is not using a preset
                if currentPreset == nil {
                    Text("Custom").tag(nil as String?)
                }

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
                // Display preset settings
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.frequencyMHz, format: .number.precision(.fractionLength(3)))
                        .font(.caption.monospacedDigit()) +
                    // swiftlint:disable:next line_length
                    Text(" MHz \u{2022} BW\(preset.bandwidthKHz, format: .number) kHz \u{2022} SF\(preset.spreadingFactor) \u{2022} CR\(preset.codingRate)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if let device = appState.connectedDevice {
                // Display device's current custom settings
                let freqMHz = Double(device.frequency) / 1000.0
                let bwKHz = Double(device.bandwidth) / 1000.0
                VStack(alignment: .leading, spacing: 4) {
                    Text(freqMHz, format: .number.precision(.fractionLength(3)))
                        .font(.caption.monospacedDigit()) +
                    // swiftlint:disable:next line_length
                    Text(" MHz \u{2022} BW\(bwKHz, format: .number) kHz \u{2022} SF\(device.spreadingFactor) \u{2022} CR\(device.codingRate)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Radio")
        } footer: {
            Text("Choose a preset matching your region. MeshCore devices must use the same radio settings in order to communicate.")
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
        .retryAlert(retryAlert)
    }

    private func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }

        isApplying = true
        Task {
            do {
                guard let settingsService = appState.services?.settingsService else {
                    throw ConnectionError.notConnected
                }
                _ = try await settingsService.applyRadioPresetVerified(preset)
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                selectedPresetID = currentPreset?.id // Revert
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { applyPreset(id: id) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
                selectedPresetID = currentPreset?.id // Revert
            }
            isApplying = false
        }
    }
}
