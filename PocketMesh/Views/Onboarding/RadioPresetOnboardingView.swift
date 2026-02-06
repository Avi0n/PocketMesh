import SwiftUI
import PocketMeshServices

/// Final onboarding step - radio preset selection
struct RadioPresetOnboardingView: View {
    @Environment(\.appState) private var appState

    @State private var selectedPresetID: String?
    @State private var appliedPresetID: String?
    @State private var isApplying = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var presetSuccessTrigger = false

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
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating)

                Text(L10n.Onboarding.RadioPreset.title)
                    .font(.largeTitle)
                    .bold()

                Text(.init(L10n.Onboarding.RadioPreset.subtitle))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)

            Spacer()

            // Preset cards
            VStack(spacing: 16) {
                PresetCardScrollView(
                    selectedPresetID: $selectedPresetID,
                    appliedPresetID: appliedPresetID,
                    currentPreset: currentPreset,
                    presets: presets,
                    device: appState.connectedDevice,
                    isDisabled: isApplying
                )

                PresetDetailsView(
                    selectedPresetID: selectedPresetID,
                    presets: presets,
                    device: appState.connectedDevice
                )

                // Apply button - always in layout to prevent shifting
                Button {
                    if let id = selectedPresetID {
                        applyPreset(id: id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isApplying {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isApplying ? L10n.Onboarding.RadioPreset.applying : L10n.Onboarding.RadioPreset.apply)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || selectedPresetID == appliedPresetID || selectedPresetID == nil)
            }

            Spacer()

            // Footer buttons
            VStack(spacing: 12) {
                Button {
                    completeOnboarding()
                } label: {
                    Text(L10n.Onboarding.RadioPreset.continue)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .liquidGlassProminentButtonStyle()
                .disabled(isApplying)

                Button {
                    completeOnboarding()
                } label: {
                    Text(L10n.Onboarding.RadioPreset.skip)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sensoryFeedback(.success, trigger: presetSuccessTrigger)
        .onAppear {
            selectedPresetID = currentPreset?.id
            appliedPresetID = currentPreset?.id
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    // MARK: - Actions

    private func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }

        isApplying = true
        Task {
            do {
                guard let settingsService = appState.services?.settingsService else {
                    throw ConnectionError.notConnected
                }
                _ = try await settingsService.applyRadioPresetVerified(preset)
                appliedPresetID = id
                retryAlert.reset()
                presetSuccessTrigger.toggle()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? L10n.Settings.Alert.Retry.fallbackMessage,
                    onRetry: { applyPreset(id: id) },
                    onMaxRetriesExceeded: { }
                )
            } catch {
                showError = error.localizedDescription
            }
            isApplying = false
        }
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

// MARK: - Preset Details View

private struct PresetDetailsView: View {
    let selectedPresetID: String?
    let presets: [RadioPreset]
    let device: DeviceDTO?

    var body: some View {
        if let preset = presets.first(where: { $0.id == selectedPresetID }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.frequencyMHz, format: .number.precision(.fractionLength(3)))
                    .font(.caption.monospacedDigit()) +
                // swiftlint:disable:next line_length
                Text(" MHz \u{2022} BW\(preset.bandwidthKHz, format: .number) kHz \u{2022} SF\(preset.spreadingFactor) \u{2022} CR\(preset.codingRate)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        } else if let device {
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
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: RadioPreset?
    let frequency: Double
    let region: RadioRegion?
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Region badge
            HStack {
                Spacer()
                if let region {
                    Text(region.shortCode)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }

            Spacer()

            // Preset name
            Text(preset?.name ?? L10n.Onboarding.RadioPreset.custom)
                .font(.headline)
                .lineLimit(1)

            // Frequency
            Text(frequency, format: .number.precision(.fractionLength(3)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            + Text(" MHz")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 150, height: 100)
        .padding(12)
        .liquidGlass(in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Preset Card Scroll View

private struct PresetCardScrollView: View {
    @Binding var selectedPresetID: String?
    let appliedPresetID: String?
    let currentPreset: RadioPreset?
    let presets: [RadioPreset]
    let device: DeviceDTO?
    let isDisabled: Bool

    var body: some View {
        ScrollView(.horizontal) {
            LiquidGlassContainer(spacing: 16) {
                LazyHStack(spacing: 12) {
                // Custom card (when device has non-preset settings)
                if currentPreset == nil, let device {
                    let freqMHz = Double(device.frequency) / 1000.0
                    Button {
                        selectedPresetID = nil
                    } label: {
                        PresetCard(
                            preset: nil,
                            frequency: freqMHz,
                            region: nil,
                            isSelected: selectedPresetID == nil,
                            isDisabled: isDisabled
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Preset cards
                ForEach(presets) { preset in
                    Button {
                        selectedPresetID = preset.id
                    } label: {
                        PresetCard(
                            preset: preset,
                            frequency: preset.frequencyMHz,
                            region: preset.region,
                            isSelected: selectedPresetID == preset.id,
                            isDisabled: isDisabled
                        )
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(.horizontal)
            }
        }
        .scrollIndicators(.hidden)
        .disabled(isDisabled)
    }
}

#Preview {
    RadioPresetOnboardingView()
        .environment(\.appState, AppState())
}
