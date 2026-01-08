import os
import SwiftUI
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "DeviceSelectionSheet")

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

    /// The primary connection method for display purposes.
    /// WiFi methods are preferred over Bluetooth when available.
    var primaryConnectionMethod: ConnectionMethod? {
        switch self {
        case .saved(let device):
            // Prefer WiFi if available
            device.connectionMethods.first { $0.isWiFi } ?? device.connectionMethods.first
        case .accessory:
            nil
        }
    }
}

/// Sheet for selecting and reconnecting to previously paired devices
struct DeviceSelectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [SelectableDevice] = []
    @State private var selectedDevice: SelectableDevice?
    @State private var showingWiFiConnection = false

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
                            if case .wifi(let host, let port, _) = device.primaryConnectionMethod {
                                try? await appState.connectViaWiFi(host: host, port: port)
                            } else {
                                try? await appState.connectionManager.connect(to: device.id)
                            }
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteDevice(device)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Previously Paired")
            } footer: {
                Text("Select a device to reconnect")
            }

            Section {
                Button {
                    showingWiFiConnection = true
                } label: {
                    Label("Connect via WiFi", systemImage: "wifi.circle")
                }

                Button {
                    scanForNewDevice()
                } label: {
                    Label("Scan for New Device", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .sheet(isPresented: $showingWiFiConnection) {
            WiFiConnectionSheet()
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Paired Devices", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            VStack(spacing: 20) {
                Text("You haven't paired any devices yet.")

                VStack(spacing: 12) {
                    Button("Connect via WiFi", systemImage: "wifi.circle") {
                        showingWiFiConnection = true
                    }
                    .liquidGlassProminentButtonStyle()

                    Button("Scan for Devices", systemImage: "antenna.radiowaves.left.and.right") {
                        scanForNewDevice()
                    }
                    .liquidGlassProminentButtonStyle()
                }
            }
        }
        .sheet(isPresented: $showingWiFiConnection) {
            WiFiConnectionSheet()
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
            logger.error("Failed to load devices: \(error)")
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

    private func deleteDevice(_ device: SelectableDevice) {
        guard case .saved(let deviceDTO) = device else { return }

        Task {
            do {
                try await appState.connectionManager.deleteDevice(id: deviceDTO.id)
                // Remove from local list
                devices.removeAll { $0.id == device.id }
                // Clear selection if deleted device was selected
                if selectedDevice?.id == device.id {
                    selectedDevice = nil
                }
            } catch {
                logger.error("Failed to delete device: \(error)")
            }
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: SelectableDevice
    let isSelected: Bool

    private var transportIcon: String {
        guard let method = device.primaryConnectionMethod else {
            return "antenna.radiowaves.left.and.right"
        }
        return method.isWiFi ? "wifi" : "antenna.radiowaves.left.and.right"
    }

    private var transportColor: Color {
        guard let method = device.primaryConnectionMethod else {
            return .green
        }
        return method.isWiFi ? .blue : .green
    }

    private var connectionDescription: String {
        if let method = device.primaryConnectionMethod {
            return method.shortDescription
        }
        return "Bluetooth"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transportIcon)
                .font(.title2)
                .foregroundStyle(transportColor)
                .frame(width: 40, height: 40)
                .background(transportColor.opacity(0.1), in: .circle)
                .accessibilityLabel(device.primaryConnectionMethod?.isWiFi == true ? "WiFi connection" : "Bluetooth connection")

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(connectionDescription)
                    if let lastConnected = device.lastConnected {
                        Text("·")
                        Text(lastConnected, format: .relative(presentation: .named))
                    }
                }
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
