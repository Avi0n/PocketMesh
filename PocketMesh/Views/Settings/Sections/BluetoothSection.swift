import SwiftUI
import PocketMeshServices

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
    @State private var isPinVisible = false

    // Track what the user intended before confirmation dialogs
    @State private var pendingPinType: BluetoothPinType?
    @State private var isRenaming = false

    enum BluetoothPinType: String, CaseIterable {
        case `default` = "Default (123456)"
        case random = "Random (Screen Required)"
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
                Button {
                    isPinVisible.toggle()
                } label: {
                    HStack {
                        Text("Current PIN")
                        Spacer()
                        Group {
                            if isPinVisible {
                                Text(device.blePin, format: .number.grouping(.never))
                            } else {
                                Text("••••••")
                            }
                        }
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Image(systemName: isPinVisible ? "eye" : "eye.slash")
                            .foregroundStyle(.tertiary)
                            .imageScale(.small)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button("Change PIN") {
                    customPin = ""
                    showingChangePinEntry = true
                }
            }

            if appState.connectionState == .ready,
               let deviceID = appState.connectedDevice?.id,
               appState.connectionManager.hasAccessory(for: deviceID) {
                Button {
                    renameDevice()
                } label: {
                    HStack {
                        Text("Rename Device")
                        Spacer()
                        if isRenaming {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRenaming)
            }
        } header: {
            Text("Bluetooth")
        } footer: {
            if appState.connectionState == .ready,
               let deviceID = appState.connectedDevice?.id,
               appState.connectionManager.hasAccessory(for: deviceID) {
                Text("Renaming only changes how iOS displays this device.")
            }
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

    private func handlePinTypeChange(from oldValue: BluetoothPinType, to newValue: BluetoothPinType) {
        // Skip if picker is being synced to device's current state (handles initialization race condition)
        guard newValue != currentPinType else { return }

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
                guard let settingsService = appState.services?.settingsService else {
                    throw ConnectionError.notConnected
                }

                // Send PIN change command (written to RAM until reboot)
                try await settingsService.setBlePin(pinValue)

                // Reboot device to apply PIN change
                try await settingsService.reboot()

                // Wait for device to start rebooting
                try await Task.sleep(for: .milliseconds(500))

                // Trigger re-pairing flow
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
                guard let settingsService = appState.services?.settingsService else {
                    throw ConnectionError.notConnected
                }

                // Send PIN change command (written to RAM until reboot)
                try await settingsService.setBlePin(pin)

                // Reboot device to apply PIN change
                try await settingsService.reboot()

                // Wait for device to start rebooting
                try await Task.sleep(for: .milliseconds(500))

                // Trigger re-pairing flow
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
        do {
            try await appState.connectionManager.forgetDevice()
            try await Task.sleep(for: .milliseconds(500))
            try await appState.connectionManager.pairNewDevice()
        } catch let pairingError as PairingError {
            // Wrong PIN during re-pairing - use AppState's recovery flow
            appState.failedPairingDeviceID = pairingError.deviceID
            appState.connectionFailedMessage = "Authentication failed. The device was added but couldn't connect — this usually means the wrong PIN was entered."
            appState.showingConnectionFailedAlert = true
        } catch {
            showError = "Re-pairing failed: \(error.localizedDescription)"
        }
    }

    private func renameDevice() {
        isRenaming = true
        Task { @MainActor in
            defer { isRenaming = false }

            do {
                try await appState.connectionManager.renameCurrentDevice()
            } catch {
                // User cancelled or rename failed - no error to show
                // Rename is optional and user can try again
            }
        }
    }
}
