import SwiftUI
import PocketMeshServices

/// Battery curve configuration section
/// Pure UI component - caller provides data and save callback
struct BatteryCurveSection: View {
    let availablePresets: [OCVPreset]
    let headerText: String
    let footerText: String

    @Binding var selectedPreset: OCVPreset
    @Binding var voltageValues: [Int]

    let onSave: (OCVPreset, [Int]) async -> Void

    @State private var isEditingValues = false
    @State private var validationError: String?
    @State private var isUpdatingFromPreset = false

    var body: some View {
        Section {
            // Preset picker
            Picker("Preset", selection: $selectedPreset) {
                ForEach(availablePresets, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
                if selectedPreset == .custom && !availablePresets.contains(.custom) {
                    Text("Custom").tag(OCVPreset.custom)
                }
            }
            .onChange(of: selectedPreset) { _, newValue in
                if newValue != .custom {
                    isUpdatingFromPreset = true
                    voltageValues = newValue.ocvArray
                    Task { @MainActor in
                        isUpdatingFromPreset = false
                    }
                    Task {
                        await onSave(newValue, newValue.ocvArray)
                    }
                }
            }

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
            if !headerText.isEmpty {
                Text(headerText)
            }
        } footer: {
            if !footerText.isEmpty {
                Text(footerText)
            }
        }
    }

    private func handleValueChanged() {
        guard !isUpdatingFromPreset else { return }

        if let error = validateVoltageValues() {
            validationError = error
            return
        }
        validationError = nil

        selectedPreset = .custom
        Task {
            await onSave(.custom, voltageValues)
        }
    }

    private func validateVoltageValues() -> String? {
        for (index, value) in voltageValues.enumerated() {
            if value < 1000 || value > 5000 {
                return "Value at \((10 - index) * 10)% must be 1000-5000 mV"
            }
        }

        for (current, next) in zip(voltageValues, voltageValues.dropFirst()) where current <= next {
            return "Values must be in descending order"
        }

        return nil
    }
}

/// Two-column grid of voltage input fields
struct VoltageFieldsGrid: View {
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
struct VoltageField: View {
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
                .accessibilityValue("\(value) millivolts")
                .accessibilityHint("Enter the expected voltage at this charge level")

            Text("mV")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var preset: OCVPreset = .liIon
    @Previewable @State var values: [Int] = OCVPreset.liIon.ocvArray

    NavigationStack {
        List {
            BatteryCurveSection(
                availablePresets: OCVPreset.selectablePresets,
                headerText: "Battery Curve",
                footerText: "Configure the voltage-to-percentage curve for your device's battery.",
                selectedPreset: $preset,
                voltageValues: $values,
                onSave: { _, _ in }
            )
        }
    }
}
