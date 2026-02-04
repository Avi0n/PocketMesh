import SwiftUI
import PocketMeshServices

/// Radio preset selector with region-based filtering
struct RadioPresetSection: View {
    @Environment(\.appState) private var appState
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
            Picker(L10n.Settings.Radio.preset, selection: $selectedPresetID) {
                // Only show Custom when device is not using a preset
                if currentPreset == nil {
                    Text(L10n.Settings.BatteryCurve.custom).tag(nil as String?)
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
            .radioDisabled(for: appState.connectionState, or: isApplying)

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
            Text(L10n.Settings.Radio.header)
        } footer: {
            Text(L10n.Settings.Radio.footer)
        }
        .onAppear {
            selectedPresetID = currentPreset?.id
            // Mark as initialized after setting initial value
            // Using task to defer to next run loop, after onChange processes
            Task { @MainActor in
                hasInitialized = true
            }
        }
        .onChange(of: currentPreset?.id) { _, newPresetID in
            // Sync picker when device settings change externally (e.g., from Advanced Settings)
            hasInitialized = false
            selectedPresetID = newPresetID
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
                    message: error.errorDescription ?? L10n.Settings.Alert.Retry.fallbackMessage,
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
