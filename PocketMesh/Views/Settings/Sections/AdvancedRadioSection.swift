import SwiftUI
import PocketMeshServices

/// Manual radio parameter configuration
struct AdvancedRadioSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var frequency: Double?  // MHz
    @State private var bandwidth: UInt32?  // Hz
    @State private var spreadingFactor: Int?
    @State private var codingRate: Int?
    @State private var txPower: Int?  // dBm
    @State private var isApplying = false
    @State private var showSuccess = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @FocusState private var focusedField: RadioField?

    private enum RadioField: Hashable {
        case frequency
        case txPower
    }

    private var isLoaded: Bool {
        frequency != nil && bandwidth != nil && spreadingFactor != nil && codingRate != nil && txPower != nil
    }

    /// Combined hash of all radio settings for change detection
    private var deviceRadioSettingsHash: Int {
        var hasher = Hasher()
        hasher.combine(appState.connectedDevice?.frequency)
        hasher.combine(appState.connectedDevice?.bandwidth)
        hasher.combine(appState.connectedDevice?.spreadingFactor)
        hasher.combine(appState.connectedDevice?.codingRate)
        hasher.combine(appState.connectedDevice?.txPower)
        return hasher.finalize()
    }

    var body: some View {
        Section {
            if !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
            HStack {
                Text(L10n.Settings.AdvancedRadio.frequency)
                Spacer()
                TextField(
                    L10n.Settings.AdvancedRadio.frequencyPlaceholder,
                    value: $frequency,
                    format: .number.precision(.fractionLength(3))
                )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($focusedField, equals: .frequency)
            }

            Picker(L10n.Settings.AdvancedRadio.bandwidth, selection: $bandwidth) {
                ForEach(RadioOptions.bandwidthsHz, id: \.self) { bwHz in
                    Text(RadioOptions.formatBandwidth(bwHz))
                        .tag(bwHz as UInt32?)
                        .accessibilityLabel("\(RadioOptions.formatBandwidth(bwHz)) kilohertz")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Lower values increase range but decrease speed")

            Picker(L10n.Settings.AdvancedRadio.spreadingFactor, selection: $spreadingFactor) {
                ForEach(RadioOptions.spreadingFactors, id: \.self) { spreadFactorOption in
                    Text(spreadFactorOption, format: .number)
                        .tag(spreadFactorOption as Int?)
                        .accessibilityLabel("Spreading factor \(spreadFactorOption)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values increase range but decrease speed")

            Picker(L10n.Settings.AdvancedRadio.codingRate, selection: $codingRate) {
                ForEach(RadioOptions.codingRates, id: \.self) { codeRateOption in
                    Text("\(codeRateOption)")
                        .tag(codeRateOption as Int?)
                        .accessibilityLabel("Coding rate \(codeRateOption)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values add error correction but decrease speed")

            HStack {
                Text(L10n.Settings.AdvancedRadio.txPower)
                Spacer()
                TextField(L10n.Settings.AdvancedRadio.txPowerPlaceholder, value: $txPower, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($focusedField, equals: .txPower)
            }

            Button {
                applySettings()
            } label: {
                HStack {
                    Spacer()
                    if isApplying {
                        ProgressView()
                    } else if showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(L10n.Settings.AdvancedRadio.apply)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .animation(.default, value: showSuccess)
            }
            .radioDisabled(for: appState.connectionState, or: isApplying || showSuccess)
            }
        } header: {
            Text(L10n.Settings.AdvancedRadio.header)
        } footer: {
            Text(L10n.Settings.AdvancedRadio.footer)
        }
        .onAppear {
            loadCurrentSettings()
        }
        .onChange(of: deviceRadioSettingsHash) { _, _ in
            loadCurrentSettings()
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }
        frequency = Double(device.frequency) / 1000.0
        // Use nearestBandwidth to handle devices with non-standard bandwidth values
        // or firmware float precision issues (e.g., 7799 Hz instead of 7800 Hz)
        bandwidth = RadioOptions.nearestBandwidth(to: device.bandwidth)
        spreadingFactor = Int(device.spreadingFactor)
        codingRate = Int(device.codingRate)
        txPower = Int(device.txPower)
    }

    private func applySettings() {
        guard let freqMHz = frequency,
              let bandwidthHz = bandwidth,
              let spreadFactor = spreadingFactor,
              let codeRate = codingRate,
              let power = txPower,
              let settingsService = appState.services?.settingsService else {
            showError = L10n.Settings.AdvancedRadio.invalidInput
            return
        }

        // Pickers enforce valid values, no range validation needed for bandwidth, SF, CR

        isApplying = true
        Task {
            do {
                // Set radio params first
                _ = try await settingsService.setRadioParamsVerified(
                    frequencyKHz: UInt32((freqMHz * 1000).rounded()),
                    // Note: Parameter is misleadingly named "bandwidthKHz" but expects Hz.
                    // bandwidthHz is already UInt32 Hz from the picker, pass directly.
                    bandwidthKHz: bandwidthHz,
                    spreadingFactor: UInt8(spreadFactor),
                    codingRate: UInt8(codeRate)
                )

                // Then set TX power
                _ = try await settingsService.setTxPowerVerified(UInt8(power))

                focusedField = nil  // Dismiss keyboard on success
                retryAlert.reset()
                isApplying = false  // Clear before showing success

                // Show success checkmark briefly
                withAnimation {
                    showSuccess = true
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation {
                    showSuccess = false
                }
                return  // Skip the isApplying = false at the end
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { applySettings() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isApplying = false
        }
    }
}
