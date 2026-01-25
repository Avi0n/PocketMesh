import SwiftUI
import PocketMeshServices
import MeshCore
import OSLog

private let deviceInfoLogger = Logger(subsystem: "com.pocketmesh", category: "DeviceInfoView")

/// Detailed device information screen
struct DeviceInfoView: View {
    @Environment(\.appState) private var appState
    @State private var showShareSheet = false

    var body: some View {
        List {
            if let device = appState.connectedDevice {
                // Device identity
                Section {
                    DeviceIdentityHeader(device: device)
                } header: {
                    Text(L10n.Settings.Device.header)
                }

                // Connection status
                Section {
                    HStack {
                        Label(
                            L10n.Settings.DeviceInfo.Connection.status,
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text(L10n.Settings.Device.connected)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.Settings.DeviceInfo.Connection.header)
                }

                // Battery and storage
                Section {
                    if let battery = appState.deviceBattery {
                        HStack {
                            Label(
                            L10n.Settings.DeviceInfo.battery,
                            systemImage: battery.iconName(using: appState.activeBatteryOCVArray)
                        )
                                .symbolRenderingMode(.multicolor)
                            Spacer()
                            Text("\(battery.percentage(using: appState.activeBatteryOCVArray))%")
                                .foregroundStyle(battery.levelColor(using: appState.activeBatteryOCVArray))
                            Text("(\(battery.voltage, format: .number.precision(.fractionLength(2)))V)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label(L10n.Settings.DeviceInfo.storageUsed, systemImage: "internaldrive")
                            Spacer()
                            Text(formatStorage(used: battery.usedStorageKB ?? 0, total: battery.totalStorageKB ?? 0))
                                .foregroundStyle(.secondary)
                        }

                        StorageBar(used: battery.usedStorageKB ?? 0, total: battery.totalStorageKB ?? 0)
                    } else {
                        HStack {
                            Label(L10n.Settings.DeviceInfo.batteryAndStorage, systemImage: "battery.100")
                            Spacer()
                            ProgressView()
                        }
                    }
                } header: {
                    Text(L10n.Settings.DeviceInfo.PowerStorage.header)
                }

                // Firmware info
                Section {
                    HStack {
                        Label(L10n.Settings.DeviceInfo.firmwareVersion, systemImage: "memorychip")
                        Spacer()
                        Text(
                            device.firmwareVersionString.isEmpty
                                ? "v\(device.firmwareVersion)"
                                : device.firmwareVersionString
                        )
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(L10n.Settings.DeviceInfo.buildDate, systemImage: "calendar")
                        Spacer()
                        Text(
                            device.buildDate.isEmpty
                                ? L10n.Settings.DeviceInfo.unknown
                                : device.buildDate
                        )
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(L10n.Settings.DeviceInfo.manufacturer, systemImage: "building.2")
                        Spacer()
                        Text(
                            device.manufacturerName.isEmpty
                                ? L10n.Settings.DeviceInfo.unknown
                                : device.manufacturerName
                        )
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.Settings.DeviceInfo.Firmware.header)
                }

                // Capabilities
                Section {
                    HStack {
                        Label(L10n.Settings.DeviceInfo.maxNodes, systemImage: "person.2")
                        Spacer()
                        Text("\(device.maxContacts)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(L10n.Settings.DeviceInfo.maxChannels, systemImage: "person.3")
                        Spacer()
                        Text("\(device.maxChannels)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label(L10n.Settings.DeviceInfo.maxTxPower, systemImage: "bolt")
                        Spacer()
                        Text(L10n.Settings.DeviceInfo.txPowerFormat(device.maxTxPower))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.Settings.DeviceInfo.Capabilities.header)
                }

                // Identity
                Section {
                    NavigationLink {
                        PublicKeyView(publicKey: device.publicKey)
                    } label: {
                        Label(L10n.Settings.DeviceInfo.publicKey, systemImage: "key")
                    }

                    Button {
                        showShareSheet = true
                    } label: {
                        Label(L10n.Settings.DeviceInfo.shareContact, systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text(L10n.Settings.DeviceInfo.Identity.header)
                }

            } else {
                ContentUnavailableView(
                    L10n.Settings.DeviceInfo.NoDevice.title,
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text(L10n.Settings.DeviceInfo.NoDevice.description)
                )
            }
        }
        .navigationTitle(L10n.Settings.DeviceInfo.title)
        .refreshable {
            await appState.fetchDeviceBattery()
        }
        .onAppear {
            deviceInfoLogger.info("DeviceInfoView: appeared, connectedDevice=\(appState.connectedDevice != nil)")
            Task { await appState.fetchDeviceBattery() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let device = appState.connectedDevice {
                ContactQRShareSheet(
                    contactName: device.nodeName,
                    publicKey: device.publicKey,
                    contactType: .chat
                )
            }
        }
    }

    private func formatStorage(used: Int, total: Int) -> String {
        "\(used) / \(total) KB"
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

                Text(
                    device.manufacturerName.isEmpty
                        ? L10n.Settings.DeviceInfo.defaultManufacturer
                        : device.manufacturerName
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
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

    @State private var copyHapticTrigger = 0

    var body: some View {
        List {
            Section {
                Text(publicKey.hexString(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text(L10n.Settings.PublicKey.header)
            } footer: {
                Text(L10n.Settings.PublicKey.footer)
            }

            Section {
                Button {
                    copyHapticTrigger += 1
                    UIPasteboard.general.string = publicKey.hexString()
                } label: {
                    Label(L10n.Settings.PublicKey.copy, systemImage: "doc.on.doc")
                }

                // Base64 representation
                Text(publicKey.base64EncodedString())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text(L10n.Settings.PublicKey.Base64.header)
            }
        }
        .navigationTitle(L10n.Settings.PublicKey.title)
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
    }
}

#Preview {
    NavigationStack {
        DeviceInfoView()
            .environment(\.appState, AppState())
    }
}
