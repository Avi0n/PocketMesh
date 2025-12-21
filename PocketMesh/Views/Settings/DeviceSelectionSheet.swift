import SwiftUI
import PocketMeshServices

/// Represents a device that can be selected for connection
private enum SelectableDevice: Identifiable, Equatable {
    case saved(DeviceDTO)
    case accessory(id: UUID, name: String)

    var id: UUID {
        switch self {
        case .saved(let device): device.id
        case .accessory(let id, _): id
        }
    }

    var name: String {
        switch self {
        case .saved(let device): device.nodeName
        case .accessory(_, let name): name
        }
    }

    var lastConnected: Date? {
        switch self {
        case .saved(let device): device.lastConnected
        case .accessory: nil
        }
    }
}

/// Sheet for selecting and reconnecting to previously paired devices
struct DeviceSelectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [SelectableDevice] = []
    @State private var selectedDevice: SelectableDevice?

    var body: some View {
        NavigationStack {
            Group {
                if devices.isEmpty {
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
                ForEach(devices) { device in
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
        // Try to load from SwiftData first
        do {
            let savedDevices = try await appState.connectionManager.fetchSavedDevices()
            if !savedDevices.isEmpty {
                devices = savedDevices.map { .saved($0) }
                return
            }
        } catch {
            print("DeviceSelectionSheet: Failed to load devices: \(error)")
        }

        // Fall back to ASK accessories when database is empty
        let accessories = appState.connectionManager.pairedAccessoryInfos
        devices = accessories.map { .accessory(id: $0.id, name: $0.name) }
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
    let device: SelectableDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)

                if let lastConnected = device.lastConnected {
                    Text("Last connected \(lastConnected, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Paired via Bluetooth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
