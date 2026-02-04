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
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [SelectableDevice] = []
    @State private var selectedDevice: SelectableDevice?
    @State private var showingWiFiConnection = false
    @State private var editingWiFiDevice: SelectableDevice?
    @State private var devicesConnectedElsewhere: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if devices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle(L10n.Settings.DeviceSelection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Localizable.Common.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Settings.DeviceSelection.connect) {
                        guard let device = selectedDevice else { return }
                        dismiss()
                        Task {
                            do {
                                if case .wifi(let host, let port, _) = device.primaryConnectionMethod {
                                    try await appState.connectViaWiFi(host: host, port: port, forceFullSync: true)
                                } else {
                                    try await appState.connectionManager.connect(to: device.id, forceFullSync: true)
                                }
                            } catch BLEError.deviceConnectedToOtherApp {
                                appState.otherAppWarningDeviceID = device.id
                            } catch {
                                appState.connectionFailedMessage = error.localizedDescription
                                appState.showingConnectionFailedAlert = true
                            }
                        }
                    }
                    .bold()
                    .tint(.blue)
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
                    DeviceRow(
                        device: device,
                        isSelected: selectedDevice?.id == device.id,
                        isConnectedElsewhere: devicesConnectedElsewhere.contains(device.id)
                    )
                        .contentShape(.rect)
                        .onTapGesture {
                            selectedDevice = device
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteDevice(device)
                            } label: {
                                Label(L10n.Localizable.Common.delete, systemImage: "trash")
                            }

                            if device.primaryConnectionMethod?.isWiFi == true {
                                Button {
                                    editingWiFiDevice = device
                                } label: {
                                    Label(L10n.Localizable.Common.edit, systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                }
            } header: {
                Text(L10n.Settings.DeviceSelection.previouslyPaired)
            } footer: {
                Text(L10n.Settings.DeviceSelection.selectToReconnect)
            }

            Section {
                Button {
                    showingWiFiConnection = true
                } label: {
                    Label(L10n.Settings.DeviceSelection.connectViaWifi, systemImage: "wifi.circle")
                }

                Button {
                    scanForNewDevice()
                } label: {
                    Label(L10n.Settings.DeviceSelection.scanBluetooth, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .sheet(isPresented: $showingWiFiConnection) {
            WiFiConnectionSheet()
        }
        .sheet(item: $editingWiFiDevice) { device in
            if case .wifi(let host, let port, _) = device.primaryConnectionMethod {
                WiFiEditSheet(initialHost: host, initialPort: port)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(L10n.Settings.DeviceSelection.noPairedDevices, systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            VStack(spacing: 20) {
                Text(L10n.Settings.DeviceSelection.noPairedDescription)

                VStack(spacing: 12) {
                    Button(L10n.Settings.DeviceSelection.connectViaWifi, systemImage: "wifi.circle") {
                        showingWiFiConnection = true
                    }
                    .liquidGlassProminentButtonStyle()

                    Button(
                        L10n.Settings.DeviceSelection.scanForDevices,
                        systemImage: "antenna.radiowaves.left.and.right"
                    ) {
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

                // Check which devices are connected elsewhere (BLE only)
                var connectedElsewhere: Set<UUID> = []
                for device in savedDevices {
                    // Skip WiFi-only devices
                    let hasBluetooth = device.connectionMethods.isEmpty ||
                        device.connectionMethods.contains { !$0.isWiFi }
                    if hasBluetooth {
                        if await appState.connectionManager.isDeviceConnectedToOtherApp(device.id) {
                            connectedElsewhere.insert(device.id)
                        }
                    }
                }
                devicesConnectedElsewhere = connectedElsewhere
                return
            }
        } catch {
            logger.error("Failed to load devices: \(error)")
        }

        // Fall back to ASK accessories when database is empty
        let accessories = appState.connectionManager.pairedAccessoryInfos
        devices = accessories.map { .accessory(id: $0.id, name: $0.name) }

        // Check which accessories are connected elsewhere
        var connectedElsewhere: Set<UUID> = []
        for accessory in accessories where await appState.connectionManager.isDeviceConnectedToOtherApp(accessory.id) {
            connectedElsewhere.insert(accessory.id)
        }
        devicesConnectedElsewhere = connectedElsewhere
    }

    private func scanForNewDevice() {
        dismiss()
        Task {
            await appState.disconnect(reason: .switchingDevice)
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
    let isConnectedElsewhere: Bool

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
        return L10n.Settings.DeviceSelection.bluetooth
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transportIcon)
                .font(.title2)
                .foregroundStyle(transportColor)
                .frame(width: 40, height: 40)
                .background(transportColor.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)

                if isConnectedElsewhere {
                    Label(
                        L10n.Settings.DeviceSelection.connectedElsewhere,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(connectionDescription)
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
        .opacity(isConnectedElsewhere ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isConnectedElsewhere
            ? "\(device.name), connected to another app"
            : "\(device.name), \(connectionDescription)")
        .accessibilityHint(isConnectedElsewhere
            ? "This device is in use by another app. Connecting may cause communication issues."
            : "Double tap to select")
    }
}
