import SwiftUI
import PocketMeshServices
import os

/// Third screen of onboarding - pairs MeshCore device via AccessorySetupKit
struct DeviceScanView: View {
    @Environment(AppState.self) private var appState
    @State private var showTroubleshooting = false
    @State private var showingWiFiConnection = false
    @State private var pairingSuccessTrigger = false
    @State private var demoModeUnlockTrigger = false
    @State private var didInitiatePairing = false
    @State private var tapTimes: [Date] = []
    @State private var showDemoModeAlert = false
    private var demoModeManager = DemoModeManager.shared

    private var hasConnectedDevice: Bool {
        appState.connectionState == .ready
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 50))
                    .foregroundStyle(.tint)
                    .frame(height: 120)

                Text("Pair Your Device")
                    .font(.largeTitle)
                    .bold()
                    .onTapGesture {
                        handleTitleTap()
                    }

                if !hasConnectedDevice {
                    Text("Make sure your MeshCore device is powered on and nearby")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            if hasConnectedDevice && !didInitiatePairing {
                VStack(spacing: 12) {
                    Text("Your device is already paired 🎉")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if !hasConnectedDevice {
                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    instructionRow(number: 1, text: "Power on your MeshCore device")
                    instructionRow(number: 2, text: "Tap \"Add Device\" below")
                    instructionRow(number: 3, text: "Select your device from the list")
                    instructionRow(number: 4, text: "Enter the PIN when prompted")
                }
                .padding()
                .liquidGlass(in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                if hasConnectedDevice {
                    Button {
                        appState.onboardingPath.append(.radioPreset)
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .liquidGlassProminentButtonStyle()
                } else {
                    Button("Using WiFi instead?") {
                        showingWiFiConnection = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    #if targetEnvironment(simulator)
                    // Simulator build - always show Connect Simulator
                    Button {
                        connectSimulator()
                    } label: {
                        HStack(spacing: 8) {
                            if appState.isPairing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            } else {
                                Image(systemName: "laptopcomputer.and.iphone")
                                Text("Connect Simulator")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .liquidGlassProminentButtonStyle()
                    .disabled(appState.isPairing)
                    #else
                    // Device build - show demo mode button if enabled, otherwise Add Device
                    if demoModeManager.isEnabled {
                        Button {
                            connectSimulator()
                        } label: {
                            HStack(spacing: 8) {
                                if appState.isPairing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Connecting...")
                                } else {
                                    Image(systemName: "play.circle.fill")
                                    Text("Continue in Demo Mode")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .liquidGlassProminentButtonStyle()
                        .disabled(appState.isPairing)
                    } else {
                        Button {
                            startPairing()
                        } label: {
                            HStack(spacing: 8) {
                                if appState.isPairing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Connecting...")
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Device")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .liquidGlassProminentButtonStyle()
                        .disabled(appState.isPairing)
                    }
                    #endif

                    Button("Device not appearing?") {
                        showTroubleshooting = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sensoryFeedback(.success, trigger: pairingSuccessTrigger)
        .sensoryFeedback(.success, trigger: demoModeUnlockTrigger)
        .sheet(isPresented: $showTroubleshooting) {
            TroubleshootingSheet()
        }
        .sheet(isPresented: $showingWiFiConnection) {
            WiFiConnectionSheet()
        }
        .alert("Demo Mode Unlocked", isPresented: $showDemoModeAlert) {
            Button("OK") { }
        } message: {
            Text("You can now continue without a device. Toggle demo mode in Settings anytime.")
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint, in: .circle)

            Text(text)
                .font(.subheadline)
        }
    }

    private func startPairing() {
        appState.isPairing = true
        didInitiatePairing = true
        // Clear any previous pairing failure state
        appState.failedPairingDeviceID = nil

        Task { @MainActor in
            defer { appState.isPairing = false }

            do {
                try await appState.connectionManager.pairNewDevice()
                await appState.wireServicesIfConnected()
                pairingSuccessTrigger.toggle()
                appState.onboardingPath.append(.radioPreset)
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error to show
            } catch AccessorySetupKitError.pickerAlreadyActive {
                // Picker is already showing - ignore
            } catch let pairingError as PairingError {
                // ASK pairing succeeded but BLE connection failed (e.g., wrong PIN)
                // Use AppState's alert mechanism for consistent UX
                appState.failedPairingDeviceID = pairingError.deviceID
                appState.connectionFailedMessage = "Authentication failed. The device was added but couldn't connect — this usually means the wrong PIN was entered."
                appState.showingConnectionFailedAlert = true
            } catch {
                // Other errors - show via AppState's alert
                appState.connectionFailedMessage = error.localizedDescription
                appState.showingConnectionFailedAlert = true
            }
        }
    }

    private func connectSimulator() {
        appState.isPairing = true
        didInitiatePairing = true

        Task {
            defer { appState.isPairing = false }

            do {
                try await appState.connectionManager.simulatorConnect()
                await appState.wireServicesIfConnected()
                pairingSuccessTrigger.toggle()
                appState.onboardingPath.append(.radioPreset)
            } catch {
                appState.connectionFailedMessage = "Simulator connection failed: \(error.localizedDescription)"
                appState.showingConnectionFailedAlert = true
            }
        }
    }

    private func handleTitleTap() {
        let now = Date()
        tapTimes.append(now)

        // Keep only taps within last 1 second
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) <= 1.0 }

        // Check if we have 3 taps within 1 second
        if tapTimes.count >= 3 {
            tapTimes.removeAll()
            demoModeManager.unlock()
            demoModeUnlockTrigger.toggle()
            showDemoModeAlert = true
        }
    }
}

/// Troubleshooting sheet for when devices don't appear in the ASK picker
/// Per Apple Developer Forums: Factory-reset devices won't appear until the stale
/// system pairing is removed via removeAccessory()
private struct TroubleshootingSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isClearing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Make sure your device is powered on", systemImage: "power")
                    Label("Move the device closer to your phone", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Restart the MeshCore device", systemImage: "arrow.clockwise")
                } header: {
                    Text("Basic Checks")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you factory-reset your MeshCore device, iOS may still have the old pairing stored. Clearing this in system Settings allows the device to appear again.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Tapping below will ask you to confirm removing the old pairing. This is normal — it allows your reset device to appear again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            clearStalePairings()
                        } label: {
                            HStack {
                                if isClearing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "trash")
                                }
                                Text("Clear Previous Pairing")
                            }
                        }
                        .disabled(isClearing || appState.connectionManager.pairedAccessoriesCount == 0)
                    }
                } header: {
                    Text("Factory Reset Device?")
                } footer: {
                    if appState.connectionManager.pairedAccessoriesCount == 0 {
                        Text("No previous pairings found.")
                    } else {
                        Text("Found \(appState.connectionManager.pairedAccessoriesCount) previous pairing(s).")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can also manage Bluetooth accessories in:")
                            .font(.subheadline)
                        Text("Settings → Privacy & Security → Accessories")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("System Settings")
                }
            }
            .navigationTitle("Troubleshooting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func clearStalePairings() {
        isClearing = true

        Task {
            defer { isClearing = false }

            // Remove all stale pairings via ConnectionManager
            // Note: iOS 26 shows a confirmation dialog for each removal
            await appState.connectionManager.clearStalePairings()

            dismiss()
        }
    }
}

#Preview {
    DeviceScanView()
        .environment(AppState())
}
