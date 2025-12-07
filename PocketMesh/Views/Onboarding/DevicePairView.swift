import SwiftUI
import PocketMeshKit

/// Fourth screen of onboarding - pairs with selected device
struct DevicePairView: View {
    @Environment(AppState.self) private var appState
    @State private var pinCode: String = ""
    @State private var isPairing: Bool = false
    @State private var pairingError: String?
    @State private var pairingSuccess: Bool = false
    @FocusState private var pinFieldFocused: Bool

    private let pinLength = 6

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    if isPairing {
                        ProgressView()
                            .scaleEffect(2)
                    } else if pairingSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: pairingSuccess)
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.tint)
                    }
                }
                .frame(height: 80)

                Text(pairingSuccess ? "Connected!" : "Enter PIN")
                    .font(.largeTitle)
                    .bold()

                if pairingSuccess {
                    if let device = appState.connectedDevice {
                        Text("Successfully connected to \(device.nodeName)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Enter the PIN shown on your device, or leave blank if no PIN is set")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.top, 40)

            if !pairingSuccess {
                Spacer()

                // PIN entry
                VStack(spacing: 20) {
                    // PIN boxes
                    HStack(spacing: 12) {
                        ForEach(0..<pinLength, id: \.self) { index in
                            PINDigitBox(
                                digit: digit(at: index),
                                isActive: index == pinCode.count
                            )
                        }
                    }

                    // Hidden text field for keyboard input
                    TextField("", text: $pinCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($pinFieldFocused)
                        .opacity(0)
                        .frame(height: 1)
                        .onChange(of: pinCode) { _, newValue in
                            // Limit to digits only and max length
                            let filtered = newValue.filter(\.isNumber)
                            let limited = filtered.count <= pinLength ? filtered : String(filtered.prefix(pinLength))
                            if limited != newValue {
                                pinCode = limited
                            }
                        }

                    Text("Tap to enter PIN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
                .onTapGesture {
                    pinFieldFocused = true
                }

                // Skip PIN option
                Button {
                    pinCode = ""
                    startPairing()
                } label: {
                    Text("No PIN set on device")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                Spacer()
            } else {
                Spacer()

                // Device info summary
                if let device = appState.connectedDevice {
                    DeviceInfoCard(device: device)
                        .padding(.horizontal)
                }

                Spacer()
            }

            // Error message
            if let error = pairingError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Navigation buttons
            VStack(spacing: 12) {
                if pairingSuccess {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        startPairing()
                    } label: {
                        if isPairing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Connect")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPairing)
                }

                if !pairingSuccess {
                    Button {
                        withAnimation {
                            appState.onboardingStep = .deviceScan
                        }
                    } label: {
                        Text("Back")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isPairing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .task {
            // Delay focus to allow view hierarchy to settle and avoid gesture gate timeout
            try? await Task.sleep(for: .milliseconds(300))
            pinFieldFocused = true
        }
    }

    private func digit(at index: Int) -> Character? {
        guard index < pinCode.count else { return nil }
        return pinCode[pinCode.index(pinCode.startIndex, offsetBy: index)]
    }

    private func startPairing() {
        guard !isPairing else { return }

        isPairing = true
        pairingError = nil
        pinFieldFocused = false

        Task {
            do {
                // Get the first discovered device (the one user selected)
                guard let device = appState.discoveredDevices.first else {
                    pairingError = "No device selected"
                    isPairing = false
                    return
                }

                try await appState.connect(to: device)

                withAnimation {
                    pairingSuccess = true
                }
            } catch {
                pairingError = "Connection failed: \(error.localizedDescription)"
            }

            isPairing = false
        }
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

// MARK: - PIN Digit Box

private struct PINDigitBox: View {
    let digit: Character?
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .frame(width: 44, height: 56)

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
                .frame(width: 44, height: 56)

            if let digit {
                Text(String(digit))
                    .font(.title)
                    .bold()
            } else if isActive {
                // Cursor animation
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: 24)
                    .opacity(0.5)
            }
        }
    }
}

// MARK: - Device Info Card

private struct DeviceInfoCard: View {
    let device: DeviceDTO

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text(device.nodeName)
                        .font(.headline)

                    Text("MeshCore Device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(spacing: 8) {
                InfoRow(label: "Firmware", value: device.firmwareVersionString)
                InfoRow(label: "Frequency", value: formatFrequency(device.frequency))
                InfoRow(label: "TX Power", value: "\(device.txPower) dBm")
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func formatFrequency(_ freqKHz: UInt32) -> String {
        let freqMHz = Double(freqKHz) / 1000.0
        return String(format: "%.3f MHz", freqMHz)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    DevicePairView()
        .environment(AppState())
}
