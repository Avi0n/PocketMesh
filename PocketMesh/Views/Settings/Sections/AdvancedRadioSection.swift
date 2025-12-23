import SwiftUI
import PocketMeshServices

/// Manual radio parameter configuration
struct AdvancedRadioSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var frequency: String = ""
    @State private var bandwidth: UInt32 = 250_000  // Hz
    @State private var spreadingFactor: Int = 10
    @State private var codingRate: Int = 5
    @State private var txPower: String = ""
    @State private var isApplying = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @FocusState private var focusedField: RadioField?

    private enum RadioField: Hashable {
        case frequency
        case txPower
    }

    var body: some View {
        Section {
            HStack {
                Text("Frequency (MHz)")
                Spacer()
                TextField("MHz", text: $frequency)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($focusedField, equals: .frequency)
            }

            Picker("Bandwidth (kHz)", selection: $bandwidth) {
                ForEach(RadioOptions.bandwidthsHz, id: \.self) { bwHz in
                    Text("\(RadioOptions.formatBandwidth(bwHz)) kHz")
                        .tag(bwHz)
                        .accessibilityLabel("\(RadioOptions.formatBandwidth(bwHz)) kilohertz")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Lower values increase range but decrease speed")

            Picker("Spreading Factor", selection: $spreadingFactor) {
                ForEach(RadioOptions.spreadingFactors, id: \.self) { sf in
                    Text("SF\(sf)")
                        .tag(sf)
                        .accessibilityLabel("Spreading factor \(sf)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values increase range but decrease speed")

            Picker("Coding Rate", selection: $codingRate) {
                ForEach(RadioOptions.codingRates, id: \.self) { cr in
                    Text("\(cr)")
                        .tag(cr)
                        .accessibilityLabel("Coding rate \(cr)")
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .accessibilityHint("Higher values add error correction but decrease speed")

            HStack {
                Text("TX Power (dBm)")
                Spacer()
                TextField("dBm", text: $txPower)
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
                    } else {
                        Text("Apply Radio Settings")
                    }
                    Spacer()
                }
            }
            .disabled(isApplying)
        } header: {
            Text("Radio Configuration")
        } footer: {
            Text("Warning: Incorrect settings may prevent communication with other mesh devices.")
        }
        .onAppear {
            loadCurrentSettings()
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }
        frequency = (Double(device.frequency) / 1000.0).formatted(.number.precision(.fractionLength(3)))
        // Use nearestBandwidth to handle devices with non-standard bandwidth values
        // or firmware float precision issues (e.g., 7799 Hz instead of 7800 Hz)
        bandwidth = RadioOptions.nearestBandwidth(to: device.bandwidth)
        spreadingFactor = Int(device.spreadingFactor)
        codingRate = Int(device.codingRate)
        txPower = "\(device.txPower)"
    }

    private func applySettings() {
        guard let freqMHz = Double(frequency),
              let power = UInt8(txPower),
              let settingsService = appState.services?.settingsService else {
            showError = "Invalid input values or device not connected"
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
                    // bandwidth is already UInt32 Hz from the picker, pass directly.
                    bandwidthKHz: bandwidth,
                    spreadingFactor: UInt8(spreadingFactor),
                    codingRate: UInt8(codingRate)
                )

                // Then set TX power
                _ = try await settingsService.setTxPowerVerified(power)

                focusedField = nil  // Dismiss keyboard on success
                retryAlert.reset()
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
