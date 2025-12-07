import SwiftUI
import PocketMeshKit

/// Third screen of onboarding - scans for MeshCore devices
struct DeviceScanView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDevice: DiscoveredDevice?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    // Scanning animation rings
                    if appState.isScanning {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(lineWidth: 2)
                                .foregroundStyle(.tint.opacity(0.3))
                                .scaleEffect(appState.isScanning ? 2 : 1)
                                .opacity(appState.isScanning ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 2)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.5),
                                    value: appState.isScanning
                                )
                        }
                        .frame(width: 60, height: 60)
                    }

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 50))
                        .foregroundStyle(.tint)
                }
                .frame(height: 120)

                Text("Find Your Device")
                    .font(.largeTitle)
                    .bold()

                Text("Make sure your MeshCore device is powered on and nearby")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Device list
            if appState.discoveredDevices.isEmpty && !appState.isScanning {
                // Empty state
                ContentUnavailableView {
                    Label("No Devices Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Tap Scan to search for nearby MeshCore devices")
                } actions: {
                    Button("Scan for Devices") {
                        startScanning()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    if appState.isScanning {
                        HStack {
                            ProgressView()
                            Text("Scanning...")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(appState.discoveredDevices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: selectedDevice?.id == device.id
                        )
                        .contentShape(.rect)
                        .onTapGesture {
                            selectedDevice = device
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            // Error message
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Navigation buttons
            VStack(spacing: 12) {
                if selectedDevice != nil {
                    Button {
                        proceedWithDevice()
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                } else if !appState.discoveredDevices.isEmpty || appState.isScanning {
                    Button {
                        if appState.isScanning {
                            stopScanning()
                        } else {
                            startScanning()
                        }
                    } label: {
                        Text(appState.isScanning ? "Stop Scanning" : "Scan Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    withAnimation {
                        appState.onboardingStep = .permissions
                    }
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
        .onAppear {
            Task {
                // Ensure any stale BLE connection is disconnected before scanning
                await appState.disconnectForNewConnection()
                startScanning()
            }
        }
        .onDisappear {
            stopScanning()
        }
    }

    private func startScanning() {
        scanTask?.cancel()
        scanTask = Task {
            await appState.startScanning()
        }
    }

    private func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        Task {
            await appState.stopScanning()
        }
    }

    private func proceedWithDevice() {
        guard let device = selectedDevice else { return }

        // Stop scanning and proceed to pairing
        stopScanning()

        // Store the selected device and move to pair screen
        withAnimation {
            appState.onboardingStep = .devicePair
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: DiscoveredDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.1), in: .circle)

            // Device info
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)

                Text(device.id.uuidString.prefix(8) + "...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Signal strength
            SignalStrengthIndicator(rssi: device.rssi)

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Signal Strength Indicator

private struct SignalStrengthIndicator: View {
    let rssi: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < signalBars ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + index * 3))
            }
        }
    }

    private var signalBars: Int {
        switch rssi {
        case -50...0: return 4    // Excellent
        case -60..<(-50): return 3  // Good
        case -70..<(-60): return 2  // Fair
        case -80..<(-70): return 1  // Poor
        default: return 0           // Very poor
        }
    }
}

#Preview {
    DeviceScanView()
        .environment(AppState())
}
