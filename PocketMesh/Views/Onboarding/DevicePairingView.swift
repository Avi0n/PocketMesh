import SwiftUI
import SwiftData
import PocketMeshKit

struct DevicePairingView: View {

    let device: MeshCoreDevice

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var pinInput = ""
    @State private var isConnecting = false
    @State private var connectionError: String?

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Pairing with")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(device.name)
                    .font(.title)
                    .fontWeight(.bold)
            }

            VStack(spacing: 16) {
                Text("Enter Device PIN")
                    .font(.headline)

                TextField("PIN (default: 123456)", text: $pinInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .frame(maxWidth: 200)

                Text("Check your device screen for the PIN, or try default: 123456")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: connectToDevice) {
                if isConnecting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Connect")
                        .font(.headline)
                }
            }
            .disabled(pinInput.isEmpty || isConnecting)
            .frame(maxWidth: .infinity)
            .padding()
            .background(pinInput.isEmpty ? Color.gray : Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .padding(.horizontal, 40)
        }
        .padding()
        .onAppear {
            pinInput = "123456" // Pre-fill default
        }
    }

    private func connectToDevice() {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                // Initialize BLE manager and protocol
                let bleManager = BLEManager()
                coordinator.bleManager = bleManager

                // Connect to device
                bleManager.connect(to: device)

                // Wait for connection
                try await Task.sleep(nanoseconds: 2_000_000_000)

                // Initialize protocol
                let meshProtocol = MeshCoreProtocol(bleManager: bleManager)
                coordinator.meshProtocol = meshProtocol

                // Perform handshake
                let deviceInfo = try await meshProtocol.deviceQuery()
                let selfInfo = try await meshProtocol.appStart()

                // Create/update device record
                let repository = DeviceRepository(modelContext: modelContext)
                let savedDevice = try repository.createOrUpdateDevice(
                    from: selfInfo,
                    name: device.name,
                    firmwareVersion: deviceInfo.firmwareVersion
                )

                try repository.setActiveDevice(savedDevice)
                try modelContext.save()

                // Complete onboarding
                await MainActor.run {
                    coordinator.completeOnboarding(device: savedDevice)
                }

            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
