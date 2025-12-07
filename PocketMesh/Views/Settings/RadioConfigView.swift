import SwiftUI
import PocketMeshKit

/// Radio configuration screen for adjusting LoRa parameters
struct RadioConfigView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var frequency: Double = 915.0
    @State private var bandwidth: Int = 250
    @State private var spreadingFactor: Int = 10
    @State private var codingRate: Int = 5
    @State private var txPower: Int = 20
    @State private var hasChanges: Bool = false
    @State private var isSaving: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var saveError: String?

    // Standard frequency bands
    private let frequencyBands: [(String, ClosedRange<Double>)] = [
        ("US 915 MHz", 902.0...928.0),
        ("EU 868 MHz", 863.0...870.0),
        ("AU 915 MHz", 915.0...928.0),
        ("KR 920 MHz", 920.0...923.0),
        ("JP 920 MHz", 920.0...928.0)
    ]

    // Standard bandwidth options (kHz)
    private let bandwidthOptions = [125, 250, 500]

    // Spreading factor range
    private let spreadingFactorRange = 5...12

    // Coding rate range
    private let codingRateRange = 5...8

    var body: some View {
        Form {
            // Current settings (read-only display)
            if let device = appState.connectedDevice {
                Section {
                    currentSettingRow("Current Frequency", formatFrequency(device.frequency))
                    currentSettingRow("Current Bandwidth", "\(device.bandwidth / 1000) kHz")
                    currentSettingRow("Current SF", "SF\(device.spreadingFactor)")
                    currentSettingRow("Current CR", "4/\(device.codingRate)")
                    currentSettingRow("Current TX Power", "\(device.txPower) dBm")
                } header: {
                    Text("Current Settings")
                } footer: {
                    Text("These are the settings currently active on the device")
                }
            }

            // Frequency section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Frequency")
                        Spacer()
                        Text(frequency, format: .number.precision(.fractionLength(3)))
                            .foregroundStyle(.secondary)
                        Text("MHz")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $frequency, in: 862.0...928.0, step: 0.025)
                        .onChange(of: frequency) { _, _ in hasChanges = true }
                }

                Picker("Frequency Band", selection: .constant(0)) {
                    ForEach(0..<frequencyBands.count, id: \.self) { index in
                        Text(frequencyBands[index].0).tag(index)
                    }
                }
                .disabled(true) // Read-only reference
            } header: {
                Text("Frequency")
            } footer: {
                Text("Ensure this matches your local regulations and other mesh devices")
            }

            // Bandwidth section
            Section {
                Picker("Bandwidth", selection: $bandwidth) {
                    ForEach(bandwidthOptions, id: \.self) { bw in
                        Text("\(bw) kHz").tag(bw)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: bandwidth) { _, _ in hasChanges = true }
            } header: {
                Text("Bandwidth")
            } footer: {
                Text("Lower bandwidth = longer range but slower. Higher bandwidth = faster but shorter range.")
            }

            // Spreading Factor section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Spreading Factor")
                        Spacer()
                        Text("SF\(spreadingFactor)")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: Binding(
                        get: { Double(spreadingFactor) },
                        set: { spreadingFactor = Int($0) }
                    ), in: 5...12, step: 1)
                    .onChange(of: spreadingFactor) { _, _ in hasChanges = true }

                    HStack {
                        Text("Fast/Short")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Slow/Long")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Spreading Factor")
            } footer: {
                Text("Higher SF = longer range but slower data rate. SF7-8 for short range, SF10-12 for long range.")
            }

            // Coding Rate section
            Section {
                Picker("Coding Rate", selection: $codingRate) {
                    ForEach(5...8, id: \.self) { cr in
                        Text("4/\(cr)").tag(cr)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: codingRate) { _, _ in hasChanges = true }
            } header: {
                Text("Coding Rate")
            } footer: {
                Text("Higher coding rate = more error correction but slower. 4/5 for good conditions, 4/8 for noisy environments.")
            }

            // TX Power section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TX Power")
                        Spacer()
                        Text("\(txPower) dBm")
                            .foregroundStyle(.secondary)
                    }

                    let maxPower = Int(appState.connectedDevice?.maxTxPower ?? 20)
                    Slider(value: Binding(
                        get: { Double(txPower) },
                        set: { txPower = Int($0) }
                    ), in: 1...Double(maxPower), step: 1)
                    .onChange(of: txPower) { _, _ in hasChanges = true }

                    HStack {
                        Text("Low Power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Max Power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Transmit Power")
            } footer: {
                Text("Higher power = longer range but more battery drain. Use minimum power needed for your range.")
            }

            // Airtime estimate
            Section {
                AirtimeEstimate(
                    bandwidth: bandwidth,
                    spreadingFactor: spreadingFactor,
                    codingRate: codingRate
                )
            } header: {
                Text("Estimated Performance")
            }
        }
        .navigationTitle("Radio Config")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    showingSaveAlert = true
                }
                .disabled(!hasChanges || isSaving)
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
        .alert("Apply Radio Settings", isPresented: $showingSaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Apply") {
                saveSettings()
            }
        } message: {
            Text("This will update the radio parameters on your device. Make sure other devices in your mesh use the same settings.")
        }
        .alert("Error", isPresented: .constant(saveError != nil)) {
            Button("OK") {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func currentSettingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func formatFrequency(_ freqKHz: UInt32) -> String {
        let freqMHz = Double(freqKHz) / 1000.0
        return String(format: "%.3f MHz", freqMHz)
    }

    private func loadCurrentSettings() {
        guard let device = appState.connectedDevice else { return }

        frequency = Double(device.frequency) / 1000.0
        bandwidth = Int(device.bandwidth / 1000)
        spreadingFactor = Int(device.spreadingFactor)
        codingRate = Int(device.codingRate)
        txPower = Int(device.txPower)
        hasChanges = false
    }

    private func saveSettings() {
        isSaving = true

        Task {
            do {
                // TODO: Implement actual save via BLE
                // let radioParams = RadioParams(
                //     frequency: UInt32(frequency * 1000),
                //     bandwidth: UInt32(bandwidth * 1000),
                //     spreadingFactor: UInt8(spreadingFactor),
                //     codingRate: UInt8(codingRate)
                // )
                // try await appState.bleService.setRadioParams(radioParams)
                // try await appState.bleService.setTxPower(UInt8(txPower))

                // Simulate save for now
                try await Task.sleep(for: .seconds(1))

                hasChanges = false
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }

            isSaving = false
        }
    }
}

// MARK: - Airtime Estimate

private struct AirtimeEstimate: View {
    let bandwidth: Int
    let spreadingFactor: Int
    let codingRate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Data Rate", systemImage: "speedometer")
                Spacer()
                Text(estimatedDataRate)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("160-char Message", systemImage: "clock")
                Spacer()
                Text(estimatedAirtime)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Range Estimate", systemImage: "ruler")
                Spacer()
                Text(estimatedRange)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var estimatedDataRate: String {
        // Simplified LoRa data rate calculation
        // DR = SF * (BW / 2^SF) * CR
        let bw = Double(bandwidth * 1000) // Hz
        let sf = Double(spreadingFactor)
        let cr = 4.0 / Double(codingRate)

        let symbolRate = bw / pow(2, sf)
        let dataRate = sf * symbolRate * cr

        if dataRate < 1000 {
            return String(format: "%.0f bps", dataRate)
        } else {
            return String(format: "%.1f kbps", dataRate / 1000)
        }
    }

    private var estimatedAirtime: String {
        // Approximate airtime for 160 byte message
        let messageBytes = 160
        let bw = Double(bandwidth * 1000)
        let sf = Double(spreadingFactor)
        let cr = Double(codingRate)

        // Symbol time
        let symbolTime = pow(2, sf) / bw

        // Preamble symbols (typically 8)
        let preambleTime = 8 * symbolTime

        // Payload symbols (simplified)
        let payloadBits = Double(messageBytes * 8)
        let bitsPerSymbol = sf * (4.0 / cr)
        let payloadSymbols = ceil(payloadBits / bitsPerSymbol)
        let payloadTime = payloadSymbols * symbolTime

        let totalTime = (preambleTime + payloadTime) * 1000 // ms

        if totalTime < 1000 {
            return String(format: "%.0f ms", totalTime)
        } else {
            return String(format: "%.1f s", totalTime / 1000)
        }
    }

    private var estimatedRange: String {
        // Very rough estimate based on SF
        switch spreadingFactor {
        case 5...6: return "< 1 km"
        case 7...8: return "1-3 km"
        case 9...10: return "3-8 km"
        case 11...12: return "8-15+ km"
        default: return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        RadioConfigView()
            .environment(AppState())
    }
}
