import SwiftUI
import PocketMeshServices

/// Third screen of onboarding - pairs MeshCore device via AccessorySetupKit
struct DeviceScanView: View {
    @Environment(AppState.self) private var appState
    @State private var isPairing = false
    @State private var showTroubleshooting = false
    @State private var errorMessage: String?
    @State private var pairingSuccessTrigger = false

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

                Text("Make sure your MeshCore device is powered on and nearby")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Instructions
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: 1, text: "Power on your MeshCore device")
                instructionRow(number: 2, text: "Tap \"Add Device\" below")
                instructionRow(number: 3, text: "Select your device from the list")
                instructionRow(number: 4, text: "Enter the PIN when prompted")
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            // Error message
            if let error = errorMessage {
                VStack(spacing: 4) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text("Please try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 8))
                .padding(.horizontal)
            }

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    startPairing()
                } label: {
                    HStack(spacing: 8) {
                        if isPairing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
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
                .buttonStyle(.borderedProminent)
                .disabled(isPairing)

                Button("Device not appearing?") {
                    showTroubleshooting = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    appState.onboardingPath.removeLast()
                } label: {
                    Text("Back")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sensoryFeedback(.success, trigger: pairingSuccessTrigger)
        .sheet(isPresented: $showTroubleshooting) {
            TroubleshootingSheet()
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
        isPairing = true
        errorMessage = nil

        Task {
            defer { isPairing = false }

            do {
                try await appState.connectionManager.pairNewDevice()
                await appState.wireServicesIfConnected()
                pairingSuccessTrigger.toggle()
                appState.onboardingPath.append(.radioPreset)
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error to show
            } catch AccessorySetupKitError.pickerRestricted {
                // CBCentralManager was initialized before ASK - should not happen with correct implementation
                errorMessage = "Cannot show device picker. Please restart the app and try again."
            } catch AccessorySetupKitError.pickerAlreadyActive {
                // Picker is already showing - ignore
            } catch AccessorySetupKitError.pairingFailed(let reason) {
                errorMessage = "Pairing failed: \(reason). Please try again."
            } catch AccessorySetupKitError.discoveryTimeout {
                errorMessage = "No devices found. Make sure your device is powered on and nearby."
            } catch AccessorySetupKitError.connectionFailed {
                errorMessage = "Could not connect to the device. Please try again."
            } catch {
                errorMessage = error.localizedDescription
            }
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
                        Text("If you factory-reset your MeshCore device, iOS may still have the old pairing stored. Clearing this allows the device to appear again.")
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
