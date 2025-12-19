import SwiftUI
import PocketMeshServices
import MeshCore

/// Detailed device information screen
struct DeviceInfoView: View {
    @Environment(AppState.self) private var appState
    @State private var batteryInfo: MeshCore.BatteryInfo?
    @State private var isLoadingBattery: Bool = false
    @State private var lastRefresh: Date?

    var body: some View {
        List {
            if let device = appState.connectedDevice {
                // Device identity
                Section {
                    DeviceIdentityHeader(device: device)
                } header: {
                    Text("Device")
                }

                // Connection status
                Section {
                    HStack {
                        Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Label("Last Connected", systemImage: "clock")
                        Spacer()
                        Text(device.lastConnected, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Connection")
                }

                // Battery and storage
                Section {
                    if let battery = batteryInfo {
                        BatteryRow(millivolts: UInt16(clamping: battery.level))

                        HStack {
                            Label("Storage Used", systemImage: "internaldrive")
                            Spacer()
                            Text(formatStorage(used: battery.usedStorageKB ?? 0, total: battery.totalStorageKB ?? 0))
                                .foregroundStyle(.secondary)
                        }

                        StorageBar(used: battery.usedStorageKB ?? 0, total: battery.totalStorageKB ?? 0)
                    } else {
                        HStack {
                            Label("Battery & Storage", systemImage: "battery.100")
                            Spacer()
                            if isLoadingBattery {
                                ProgressView()
                            } else {
                                Button("Refresh") {
                                    refreshBatteryInfo()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Power & Storage")
                } footer: {
                    if let lastRefresh {
                        Text("Last updated: \(lastRefresh, format: .relative(presentation: .named))")
                    }
                }

                // Firmware info
                Section {
                    HStack {
                        Label("Firmware Version", systemImage: "memorychip")
                        Spacer()
                        Text(device.firmwareVersionString.isEmpty ? "v\(device.firmwareVersion)" : device.firmwareVersionString)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Protocol Version", systemImage: "number")
                        Spacer()
                        Text("\(device.firmwareVersion)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Build Date", systemImage: "calendar")
                        Spacer()
                        Text(device.buildDate.isEmpty ? "Unknown" : device.buildDate)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Manufacturer", systemImage: "building.2")
                        Spacer()
                        Text(device.manufacturerName.isEmpty ? "Unknown" : device.manufacturerName)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Firmware")
                }

                // Capabilities
                Section {
                    HStack {
                        Label("Max Contacts", systemImage: "person.2")
                        Spacer()
                        Text("\(device.maxContacts)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Max Channels", systemImage: "person.3")
                        Spacer()
                        Text("\(device.maxChannels)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Max TX Power", systemImage: "bolt")
                        Spacer()
                        Text("\(device.maxTxPower) dBm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Capabilities")
                }

                // Security
                Section {
                    HStack {
                        Label("BLE PIN", systemImage: "lock")
                        Spacer()
                        Text(device.blePin == 0 ? "Disabled" : "Enabled")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        PublicKeyView(publicKey: device.publicKey)
                    } label: {
                        Label("Public Key", systemImage: "key")
                    }
                } header: {
                    Text("Security")
                }

                // Identifier
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(device.id.uuidString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Identifier")
                }
            } else {
                ContentUnavailableView(
                    "No Device Connected",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Connect to a MeshCore device to view its information")
                )
            }
        }
        .navigationTitle("Device Info")
        .refreshable {
            refreshBatteryInfo()
        }
        .onAppear {
            refreshBatteryInfo()
        }
    }

    private func formatStorage(used: Int, total: Int) -> String {
        "\(used) / \(total) KB"
    }

    private func refreshBatteryInfo() {
        guard !isLoadingBattery,
              let settingsService = appState.services?.settingsService else { return }

        isLoadingBattery = true

        Task {
            do {
                batteryInfo = try await settingsService.getBattery()
                lastRefresh = Date()
            } catch {
                // Leave batteryInfo as nil to show refresh button
            }

            isLoadingBattery = false
        }
    }
}

// MARK: - Device Identity Header

private struct DeviceIdentityHeader: View {
    let device: DeviceDTO

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .background(.tint.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.nodeName)
                    .font(.title2)
                    .bold()

                Text(device.manufacturerName.isEmpty ? "MeshCore Device" : device.manufacturerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Battery Row

private struct BatteryRow: View {
    let millivolts: UInt16

    var body: some View {
        HStack {
            Label("Battery", systemImage: batteryIcon)
                .symbolRenderingMode(.multicolor)

            Spacer()

            Text(batteryPercentage)
                .foregroundStyle(batteryColor)

            Text(voltageString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var batteryIcon: String {
        let percent = estimatedPercentage
        switch percent {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    private var batteryPercentage: String {
        "\(estimatedPercentage)%"
    }

    private var voltageString: String {
        let volts = Double(millivolts) / 1000.0
        return "(\(volts.formatted(.number.precision(.fractionLength(2))))V)"
    }

    private var batteryColor: Color {
        let percent = estimatedPercentage
        switch percent {
        case 20...100: return .primary
        case 10..<20: return .orange
        default: return .red
        }
    }

    private var estimatedPercentage: Int {
        // LiPo voltage to percentage (approximate)
        // 4.2V = 100%, 3.0V = 0%
        let voltage = Double(millivolts) / 1000.0
        let minV = 3.0
        let maxV = 4.2

        let percent = ((voltage - minV) / (maxV - minV)) * 100
        return Int(min(100, max(0, percent)))
    }
}

// MARK: - Storage Bar

private struct StorageBar: View {
    let used: Int
    let total: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(usageColor)
                    .frame(width: geometry.size.width * usageRatio)
            }
        }
        .frame(height: 8)
    }

    private var usageRatio: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(used) / CGFloat(total)
    }

    private var usageColor: Color {
        switch usageRatio {
        case 0..<0.7: return .green
        case 0.7..<0.9: return .orange
        default: return .red
        }
    }
}

// MARK: - Public Key View

private struct PublicKeyView: View {
    let publicKey: Data

    var body: some View {
        List {
            Section {
                Text(publicKey.hexString(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("32-byte Ed25519 Public Key")
            } footer: {
                Text("This key uniquely identifies your device on the mesh network")
            }

            Section {
                Button {
                    UIPasteboard.general.string = publicKey.hexString()
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }

                // Base64 representation
                Text(publicKey.base64EncodedString())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Base64")
            }
        }
        .navigationTitle("Public Key")
    }
}

#Preview {
    NavigationStack {
        DeviceInfoView()
            .environment(AppState())
    }
}
