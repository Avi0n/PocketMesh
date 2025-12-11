import SwiftUI
import PocketMeshKit

/// Bluetooth PIN configuration
struct BluetoothSection: View {
    @Environment(AppState.self) private var appState
    @State private var pinType: BluetoothPinType = .random
    @State private var customPin: String = ""
    @State private var showingPinEntry = false
    @State private var showingChangePinEntry = false
    @State private var showingRemoveConfirmation = false
    @State private var isChangingPin = false
    @State private var showError: String?
    @State private var hasInitialized = false

    // Track what the user intended before confirmation dialogs
    @State private var pendingPinType: BluetoothPinType?

    enum BluetoothPinType: String, CaseIterable {
        case random = "Random (Screen Required)"
        case `default` = "Default (123456)"
        case custom = "Custom PIN"
    }

    private var currentPinType: BluetoothPinType {
        guard let device = appState.connectedDevice else { return .random }
        if device.blePin == 0 {
            return .random
        } else if device.blePin == 123456 {
            return .default
        } else {
            return .custom
        }
    }

    var body: some View {
        Section {
            Picker("PIN Type", selection: $pinType) {
                ForEach(BluetoothPinType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .onChange(of: pinType) { oldValue, newValue in
                guard hasInitialized else { return }
                handlePinTypeChange(from: oldValue, to: newValue)
            }
            .disabled(isChangingPin)

            if pinType == .custom, let device = appState.connectedDevice, device.blePin > 0 {
                HStack {
                    Text("Current PIN")
                    Spacer()
                    Text(device.blePin, format: .number.grouping(.never))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button("Change PIN") {
                    customPin = ""
                    showingChangePinEntry = true
                }
            }
        } header: {
            Text("Bluetooth")
        } footer: {
            Text(pinTypeFooter)
        }
        .onAppear {
            pinType = currentPinType
            Task { @MainActor in
                hasInitialized = true
            }
        }
        .alert("Set Custom PIN", isPresented: $showingPinEntry) {
            TextField("6-digit PIN", text: $customPin)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                // Revert to previous pin type without triggering onChange loop
                hasInitialized = false
                pinType = currentPinType
                Task { @MainActor in
                    hasInitialized = true
                }
            }
            Button("Set PIN") {
                setCustomPin()
            }
        } message: {
            Text("Enter a 6-digit PIN. You will need to remove and re-pair the device after this change.")
        }
        .alert("Change Custom PIN", isPresented: $showingChangePinEntry) {
            TextField("6-digit PIN", text: $customPin)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Change PIN") {
                setCustomPin()
            }
        } message: {
            Text("Enter a new 6-digit PIN. You will need to remove and re-pair the device after this change.")
        }
        .alert("Change PIN Type?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                // Revert to previous pin type without triggering onChange loop
                hasInitialized = false
                pinType = currentPinType
                Task { @MainActor in
                    hasInitialized = true
                }
            }
            Button("Change", role: .destructive) {
                applyPendingPinType()
            }
        } message: {
            Text("You'll need to remove and re-pair the device after this change.")
        }
        .errorAlert($showError)
    }

    private var pinTypeFooter: String {
        switch pinType {
        case .random:
            return "A random PIN will be displayed on the device screen during pairing."
        case .default:
            return "Use the default PIN of 123456."
        case .custom:
            return "Use a custom fixed PIN."
        }
    }

    private func handlePinTypeChange(from oldValue: BluetoothPinType, to newValue: BluetoothPinType) {
        // If changing TO custom, show PIN entry
        if newValue == .custom && oldValue != .custom {
            showingPinEntry = true
            return
        }

        // If changing FROM custom to something else, show confirmation
        if oldValue == .custom && newValue != .custom {
            pendingPinType = newValue
            showingRemoveConfirmation = true
            return
        }

        // If changing between random and default, show confirmation
        if (oldValue == .random && newValue == .default) || (oldValue == .default && newValue == .random) {
            pendingPinType = newValue
            showingRemoveConfirmation = true
            return
        }
    }

    private func applyPendingPinType() {
        guard let pending = pendingPinType else { return }
        pendingPinType = nil

        let pinValue: UInt32 = pending == .default ? 123456 : 0

        isChangingPin = true
        Task {
            do {
                try await appState.settingsService.setBlePin(pinValue)
                await triggerRepairingFlow()
            } catch {
                showError = error.localizedDescription
                // Revert
                hasInitialized = false
                pinType = currentPinType
                Task { @MainActor in
                    hasInitialized = true
                }
            }
            isChangingPin = false
        }
    }

    private func setCustomPin() {
        guard let pin = UInt32(customPin), pin >= 100000, pin <= 999999 else {
            showError = "PIN must be a 6-digit number between 100000 and 999999"
            customPin = ""
            // Revert
            hasInitialized = false
            pinType = currentPinType
            Task { @MainActor in
                hasInitialized = true
            }
            return
        }

        isChangingPin = true
        Task {
            do {
                try await appState.settingsService.setBlePin(pin)
                await triggerRepairingFlow()
            } catch {
                showError = error.localizedDescription
                // Revert
                hasInitialized = false
                pinType = currentPinType
                Task { @MainActor in
                    hasInitialized = true
                }
            }
            isChangingPin = false
            customPin = ""
        }
    }

    private func triggerRepairingFlow() async {
        guard let deviceID = appState.connectedDevice?.id,
              let accessory = appState.accessorySetupKit.accessory(for: deviceID) else {
            return
        }

        do {
            try await appState.accessorySetupKit.removeAccessory(accessory)
            await appState.disconnect()
            try await Task.sleep(for: .milliseconds(500))
            try await appState.pairNewDevice()
        } catch {
            showError = "Re-pairing failed: \(error.localizedDescription)"
        }
    }
}
