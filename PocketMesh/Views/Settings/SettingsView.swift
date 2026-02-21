import SwiftUI
import PocketMeshServices

/// Main settings screen — navigation-link rows for device settings, always-visible app settings
struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingDeviceSelection = false
    private var demoModeManager = DemoModeManager.shared

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                settingsListContent
            } detail: {
                ContentUnavailableView(L10n.Settings.selectSetting, systemImage: "gear")
            }
        } else {
            NavigationStack {
                settingsListContent
            }
        }
    }

    private var settingsListContent: some View {
        List {
            if let device = appState.connectedDevice {
                MyDeviceSection(device: device)
            } else {
                NoDeviceSection(showingDeviceSelection: $showingDeviceSelection)
            }

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    TintedLabel(L10n.Settings.Notifications.header, systemImage: "bell.badge")
                }

                NavigationLink {
                    ChatSettingsView()
                } label: {
                    TintedLabel(L10n.Settings.ChatSettings.title, systemImage: "bubble.left.and.bubble.right")
                }
            } header: {
                Text(L10n.Settings.AppSettings.header)
            }

            AboutSection()

            DiagnosticsSection()

            if demoModeManager.isUnlocked {
                Section {
                    Toggle(L10n.Settings.DemoMode.enabled, isOn: Binding(
                        get: { demoModeManager.isEnabled },
                        set: { demoModeManager.isEnabled = $0 }
                    ))
                } header: {
                    Text(L10n.Settings.DemoMode.header)
                } footer: {
                    Text(L10n.Settings.DemoMode.footer)
                }
            }

            #if DEBUG
            Section {
                Button {
                    appState.onboarding.resetOnboarding()
                } label: {
                    TintedLabel("Reset Onboarding", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Debug")
            }
            #endif

            Section {
            } footer: {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                VStack {
                    Text(L10n.Settings.version(version))
                    Text(L10n.Settings.build(build))
                }
                .padding(.top, -8)
                .padding(.bottom)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.Settings.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BLEStatusIndicatorView()
            }
        }
        .sheet(isPresented: $showingDeviceSelection) {
            DeviceSelectionSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

}

// MARK: - My Device Section

private struct MyDeviceSection: View {
    let device: DeviceDTO
    @Environment(\.appState) private var appState

    var body: some View {
        Section {
            NavigationLink {
                DeviceInfoView()
            } label: {
                SettingsRow(L10n.Settings.DeviceInfo.title, systemImage: "cpu", detail: device.nodeName)
            }
            .accessibilityValue(device.nodeName)

            NavigationLink {
                RadioSettingsView()
            } label: {
                SettingsRow(L10n.Settings.Radio.header, systemImage: "antenna.radiowaves.left.and.right", detail: radioDetailText)
            }
            .accessibilityValue(radioDetailText)

            NavigationLink {
                LocationSettingsView()
            } label: {
                SettingsRow(L10n.Settings.Location.header, systemImage: "location", detail: locationDetailText)
            }
            .accessibilityValue(locationDetailText)

            NavigationLink {
                ConnectionSettingsView()
            } label: {
                let isWiFi = appState.connectionManager.currentTransportType == .wifi
                TintedLabel(
                    isWiFi ? L10n.Settings.Wifi.header : L10n.Settings.Bluetooth.header,
                    systemImage: isWiFi ? "wifi" : "wave.3.right"
                )
            }

            NavigationLink {
                AdvancedSettingsView()
            } label: {
                advancedSettingsRowLabel
            }
        } header: {
            Text(L10n.Settings.MyDevice.header)
        }
    }

    private var radioDetailText: String {
        let preset = RadioPresets.matchingPreset(
            frequencyKHz: device.frequency,
            bandwidthKHz: device.bandwidth,
            spreadingFactor: device.spreadingFactor,
            codingRate: device.codingRate
        )
        return preset?.name ?? L10n.Settings.BatteryCurve.custom
    }

    private var locationDetailText: String {
        device.advertLocationPolicy == 1
            ? L10n.Settings.Location.sharingPublicly
            : L10n.Settings.Location.notSharing
    }

    private var advancedSettingsRowLabel: some View {
        TintedLabel(L10n.Settings.AdvancedSettings.title, systemImage: "gearshape.2")
    }
}

// MARK: - Settings Row with Detail Text

private struct SettingsRow: View {
    let title: String
    let systemImage: String
    let detail: String

    init(_ title: String, systemImage: String, detail: String) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack {
            TintedLabel(title, systemImage: systemImage)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
}
