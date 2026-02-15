import SwiftUI
import PocketMeshServices

/// Main settings screen prioritizing new user experience
struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingAdvancedSettings = false
    @State private var showingDeviceSelection = false
    @State private var showingLocationPicker = false
    @State private var showingWiFiEditSheet = false
    private var demoModeManager = DemoModeManager.shared

    private var shouldUseSplitView: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        if shouldUseSplitView {
            NavigationSplitView {
                settingsListContent
            } detail: {
                ContentUnavailableView(L10n.Settings.selectSetting, systemImage: "gear")
            }
        } else {
            NavigationStack {
                settingsListContent
            }
            .sheet(isPresented: $showingAdvancedSettings) {
                AdvancedSettingsView()
            }
        }
    }

    private var settingsListContent: some View {
        List {
            if let device = appState.connectedDevice {
                DeviceInfoSection(device: device)

                RadioPresetSection()

                NodeSettingsSection()

                LocationSettingsSection(showingLocationPicker: $showingLocationPicker)

                if appState.currentTransportType == .wifi {
                    WiFiSection(showingEditSheet: $showingWiFiEditSheet)
                } else {
                    BluetoothSection()
                }

                NotificationSettingsSection()

                LinkPreviewSettingsSection()

                BlockingSection()

                Section {
                    if shouldUseSplitView {
                        NavigationLink {
                            AdvancedSettingsView()
                        } label: {
                            advancedSettingsRowLabel
                        }
                        .foregroundStyle(.primary)
                    } else {
                        Button {
                            showingAdvancedSettings = true
                        } label: {
                            advancedSettingsRowLabel
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text(L10n.Settings.AdvancedSettings.footer)
                }

                AboutSection()

            } else {
                NoDeviceSection(showingDeviceSelection: $showingDeviceSelection)
            }

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
                    appState.resetOnboarding()
                } label: {
                    Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
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
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView.forLocalDevice(appState: appState)
        }
        .sheet(isPresented: $showingWiFiEditSheet) {
            WiFiEditSheet()
        }
    }

    private var advancedSettingsRowLabel: some View {
        HStack {
            Label {
                Text(L10n.Settings.AdvancedSettings.title)
            } icon: {
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.tint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
}
