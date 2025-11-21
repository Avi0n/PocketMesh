import PocketMeshKit
import SwiftUI

struct DeviceScanningView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var isScanning = false

    let onDeviceSelected: (MeshCoreDevice) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Find Your Device")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Scanning for nearby MeshCore radios...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isScanning {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
            }

            List(bleManager.discoveredDevices) { device in
                Button {
                    bleManager.stopScanning()
                    onDeviceSelected(device)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text("RSSI: \(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .listStyle(.insetGrouped)

            Spacer()

            Button {
                bleManager.stopScanning()
                onSkip()
            } label: {
                Text("Skip for Now")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .onAppear {
            isScanning = true
            bleManager.startScanning()
        }
        .onDisappear {
            bleManager.stopScanning()
        }
    }
}
