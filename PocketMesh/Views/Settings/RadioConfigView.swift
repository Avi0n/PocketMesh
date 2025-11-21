import PocketMeshKit
import SwiftUI

struct RadioConfigView: View {
    let device: Device

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isSaving = false

    // Radio parameters (local state for editing)
    @State private var frequency: Double
    @State private var bandwidth: Double
    @State private var spreadingFactor: Int
    @State private var codingRate: Int
    @State private var txPower: Int

    init(device: Device) {
        self.device = device

        _frequency = State(initialValue: Double(device.radioFrequency) / 1000.0 / 1000.0) // Hz to MHz
        _bandwidth = State(initialValue: Double(device.radioBandwidth) / 1000.0 / 1000.0) // Hz to kHz
        _spreadingFactor = State(initialValue: Int(device.radioSpreadingFactor))
        _codingRate = State(initialValue: Int(device.radioCodingRate))
        _txPower = State(initialValue: Int(device.txPower))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("\(frequency, specifier: "%.3f") MHz")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Slider(value: $frequency, in: 902.0 ... 928.0, step: 0.125)
            } header: {
                Text("Frequency")
            } footer: {
                Text("US ISM band: 902-928 MHz")
            }

            Section {
                Picker("Bandwidth", selection: $bandwidth) {
                    Text("125 kHz").tag(125.0)
                    Text("250 kHz").tag(250.0)
                    Text("500 kHz").tag(500.0)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Bandwidth")
            }

            Section {
                Picker("SF", selection: $spreadingFactor) {
                    ForEach(7 ... 12, id: \.self) { spreadFactor in
                        Text("SF\(spreadFactor)").tag(spreadFactor)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Spreading Factor")
            } footer: {
                Text("Higher SF = longer range but slower speed")
            }

            Section {
                Picker("CR", selection: $codingRate) {
                    Text("4/5").tag(5)
                    Text("4/6").tag(6)
                    Text("4/7").tag(7)
                    Text("4/8").tag(8)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Coding Rate")
            }

            Section {
                HStack {
                    Text("\(txPower) dBm")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Slider(value: Binding(
                    get: { Double(txPower) },
                    set: { txPower = Int($0) },
                ), in: 2 ... 20, step: 1)
            } header: {
                Text("Transmit Power")
            } footer: {
                Text("Higher power = better range but more battery drain")
            }

            Section {
                Button(action: saveConfiguration) {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            Text("Save Configuration")
                            Spacer()
                        }
                    }
                }
                .disabled(isSaving || !hasChanges)
            }
        }
        .navigationTitle("Radio Configuration")
    }

    private var hasChanges: Bool {
        let freqHz = UInt32(frequency * 1_000_000) // MHz to Hz
        let bwHz = UInt32(bandwidth * 1000) // kHz to Hz

        return device.radioFrequency != freqHz ||
            device.radioBandwidth != bwHz ||
            Int(device.radioSpreadingFactor) != spreadingFactor ||
            Int(device.radioCodingRate) != codingRate ||
            Int(device.txPower) != txPower
    }

    private func saveConfiguration() {
        guard let meshProtocol = coordinator.meshProtocol else { return }

        isSaving = true

        Task {
            do {
                // Convert to protocol units
                let freqHz = UInt32(frequency * 1_000_000) // MHz to Hz
                let bwHz = UInt32(bandwidth * 1000) // kHz to Hz

                // Send radio params command
                try await meshProtocol.setRadioParameters(
                    frequency: freqHz,
                    bandwidth: bwHz,
                    spreadingFactor: UInt8(spreadingFactor),
                    codingRate: UInt8(codingRate),
                )

                // Send TX power command
                try await meshProtocol.setRadioTxPower(Int8(txPower))

                // Update local model
                await MainActor.run {
                    device.radioFrequency = freqHz
                    device.radioBandwidth = bwHz
                    device.radioSpreadingFactor = UInt8(spreadingFactor)
                    device.radioCodingRate = UInt8(codingRate)
                    device.txPower = Int8(txPower)

                    isSaving = false
                }

            } catch {
                print("Failed to save configuration: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}
