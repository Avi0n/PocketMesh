import SwiftUI
import PocketMeshKit

/// Manual radio parameter configuration
struct AdvancedRadioSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var frequency: String = ""
    @State private var bandwidth: String = ""
    @State private var spreadingFactor: String = ""
    @State private var codingRate: String = ""
    @State private var txPower: String = ""
    @State private var isApplying = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @FocusState private var focusedField: RadioField?

    private enum RadioField: Hashable {
        case frequency
        case bandwidth
        case spreadingFactor
        case codingRate
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

            HStack {
                Text("Bandwidth (kHz)")
                Spacer()
                TextField("kHz", text: $bandwidth)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($focusedField, equals: .bandwidth)
            }

            HStack {
                Text("Spreading Factor")
                Spacer()
                TextField("5-12", text: $spreadingFactor)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($focusedField, equals: .spreadingFactor)
            }

            HStack {
                Text("Coding Rate")
                Spacer()
                TextField("5-8", text: $codingRate)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($focusedField, equals: .codingRate)
            }

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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }
        frequency = String(format: "%.3f", Double(device.frequency) / 1000.0)
        bandwidth = String(format: "%.1f", Double(device.bandwidth) / 1000.0)
        spreadingFactor = "\(device.spreadingFactor)"
        codingRate = "\(device.codingRate)"
        txPower = "\(device.txPower)"
    }

    private func applySettings() {
        guard let freqMHz = Double(frequency),
              let bwKHz = Double(bandwidth),
              let sf = UInt8(spreadingFactor),
              let cr = UInt8(codingRate),
              let power = UInt8(txPower) else {
            showError = "Invalid input values"
            return
        }

        guard sf >= 5, sf <= 12 else {
            showError = "Spreading factor must be between 5 and 12"
            return
        }

        guard cr >= 5, cr <= 8 else {
            showError = "Coding rate must be between 5 and 8"
            return
        }

        isApplying = true
        Task {
            do {
                let (deviceInfo, selfInfo) = try await appState.withSyncActivity {
                    // Set radio params first
                    var deviceInfo: DeviceInfo
                    var selfInfo: SelfInfo
                    (deviceInfo, selfInfo) = try await appState.settingsService.setRadioParamsVerified(
                        frequencyKHz: UInt32(freqMHz * 1000),
                        bandwidthKHz: UInt32(bwKHz * 1000),
                        spreadingFactor: sf,
                        codingRate: cr
                    )

                    // Then set TX power
                    (deviceInfo, selfInfo) = try await appState.settingsService.setTxPowerVerified(power)
                    return (deviceInfo, selfInfo)
                }

                appState.updateDeviceInfo(deviceInfo, selfInfo)
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
