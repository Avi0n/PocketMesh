import SwiftUI
import PocketMeshServices

/// Sheet for selecting and reconnecting to previously paired devices
struct DeviceSelectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var savedDevices: [DeviceDTO] = []
    @State private var selectedDevice: DeviceDTO?

    var body: some View {
        NavigationStack {
            Group {
                if savedDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Connect Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        guard let device = selectedDevice else { return }
                        dismiss()
                        Task {
                            try? await appState.connectionManager.connect(to: device.id)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedDevice == nil)
                }
            }
            .task {
                await loadDevices()
            }
        }
    }

    // MARK: - Subviews

    private var deviceListView: some View {
        List {
            Section {
                ForEach(savedDevices) { device in
                    DeviceRow(device: device, isSelected: selectedDevice?.id == device.id)
                        .contentShape(.rect)
                        .onTapGesture {
                            selectedDevice = device
                        }
                }
            } header: {
                Text("Previously Paired")
            } footer: {
                Text("Select a device to reconnect")
            }

            Section {
                Button {
                    scanForNewDevice()
                } label: {
                    Label("Scan for New Device", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Paired Devices", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("You haven't paired any devices yet.")
        } actions: {
            Button("Scan for Devices") {
                scanForNewDevice()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func loadDevices() async {
        guard let dataStore = appState.services?.dataStore else {
            savedDevices = []
            return
        }
        do {
            savedDevices = try await dataStore.fetchDevices()
        } catch {
            savedDevices = []
        }
    }

    private func scanForNewDevice() {
        dismiss()
        Task {
            await appState.disconnect()
            // Trigger ASK picker flow via AppState
            appState.startDeviceScan()
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: DeviceDTO
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.nodeName)
                    .font(.headline)

                Text("Last connected \(device.lastConnected, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
