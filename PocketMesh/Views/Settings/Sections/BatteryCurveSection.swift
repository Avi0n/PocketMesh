import SwiftUI
import PocketMeshServices

/// Battery curve configuration section for Advanced Settings
struct BatteryCurveSection: View {
    @Environment(AppState.self) private var appState

    @State private var selectedPreset: OCVPreset = .liIon
    @State private var voltageValues: [Int] = OCVPreset.liIon.ocvArray
    @State private var isEditingValues = false
    @State private var validationError: String?
    /// Tracks whether voltageValues change is from preset selection (not user edit)
    @State private var isUpdatingFromPreset = false

    var body: some View {
        Section {
            // Preset picker
            Picker("Preset", selection: $selectedPreset) {
                ForEach(OCVPreset.selectablePresets, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
                if selectedPreset == .custom {
                    Text("Custom").tag(OCVPreset.custom)
                }
            }
            .onChange(of: selectedPreset) { _, newValue in
                if newValue != .custom {
                    isUpdatingFromPreset = true
                    voltageValues = newValue.ocvArray
                    isUpdatingFromPreset = false
                    saveToDevice()
                }
            }

            // Chart
            BatteryCurveChart(ocvArray: voltageValues)

            // Edit values disclosure
            DisclosureGroup("Edit Values", isExpanded: $isEditingValues) {
                VoltageFieldsGrid(
                    voltageValues: $voltageValues,
                    validationError: $validationError,
                    onValueChanged: handleValueChanged
                )
            }

            // Validation error
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Battery Curve")
        } footer: {
            Text("Configure the voltage-to-percentage curve for your device's battery.")
        }
        .task(id: appState.connectedDevice?.id) {
            loadFromDevice()
        }
    }

    private func loadFromDevice() {
        guard let device = appState.connectedDevice else { return }

        isUpdatingFromPreset = true
        defer { isUpdatingFromPreset = false }

        if let presetName = device.ocvPreset {
            if presetName == OCVPreset.custom.rawValue, let customString = device.customOCVArrayString {
                let parsed = customString.split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parsed.count == 11 {
                    voltageValues = parsed
                    selectedPreset = .custom
                    return
                }
            }
            if let preset = OCVPreset(rawValue: presetName) {
                selectedPreset = preset
                voltageValues = preset.ocvArray
                return
            }
        }

        // Default
        selectedPreset = .liIon
        voltageValues = OCVPreset.liIon.ocvArray
    }

    private func handleValueChanged() {
        // Ignore if this change came from preset selection
        guard !isUpdatingFromPreset else { return }

        // Validate
        if let error = validateVoltageValues() {
            validationError = error
            return
        }
        validationError = nil

        // Mark as custom (user manually edited a value)
        selectedPreset = .custom
        saveToDevice()
    }

    private func validateVoltageValues() -> String? {
        // Check all values in valid range
        for (index, value) in voltageValues.enumerated() {
            if value < 1000 || value > 5000 {
                return "Value at \((10 - index) * 10)% must be 1000-5000 mV"
            }
        }

        // Check descending order
        for i in 0..<(voltageValues.count - 1) {
            if voltageValues[i] <= voltageValues[i + 1] {
                return "Values must be in descending order"
            }
        }

        return nil
    }

    private func saveToDevice() {
        Task {
            guard let deviceService = appState.services?.deviceService,
                  let deviceID = appState.connectedDevice?.id else { return }

            if selectedPreset == .custom {
                let customString = voltageValues.map(String.init).joined(separator: ",")
                try? await deviceService.updateOCVSettings(
                    deviceID: deviceID,
                    preset: OCVPreset.custom.rawValue,
                    customArray: customString
                )
            } else {
                try? await deviceService.updateOCVSettings(
                    deviceID: deviceID,
                    preset: selectedPreset.rawValue,
                    customArray: nil
                )
            }
        }
    }
}

/// Two-column grid of voltage input fields
private struct VoltageFieldsGrid: View {
    @Binding var voltageValues: [Int]
    @Binding var validationError: String?
    let onValueChanged: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<11, id: \.self) { index in
                VoltageField(
                    percent: (10 - index) * 10,
                    value: $voltageValues[index],
                    hasError: fieldHasError(at: index),
                    onValueChanged: onValueChanged
                )
            }
        }
        .padding(.vertical, 8)
    }

    private func fieldHasError(at index: Int) -> Bool {
        let value = voltageValues[index]
        if value < 1000 || value > 5000 { return true }
        if index > 0 && voltageValues[index - 1] <= value { return true }
        if index < 10 && value <= voltageValues[index + 1] { return true }
        return false
    }
}

/// Individual voltage input field
private struct VoltageField: View {
    let percent: Int
    @Binding var value: Int
    let hasError: Bool
    let onValueChanged: () -> Void

    var body: some View {
        HStack {
            Text("\(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            TextField("", value: $value, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasError ? .red : .clear, lineWidth: 1)
                )
                .onChange(of: value) { _, _ in
                    onValueChanged()
                }
                .accessibilityLabel("Voltage at \(percent) percent")

            Text("mV")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            BatteryCurveSection()
        }
    }
    .environment(AppState())
}
