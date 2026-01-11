import SwiftUI
import PocketMeshServices
import MapKit

/// Main settings screen prioritizing new user experience
struct SettingsView: View {
    @Environment(AppState.self) private var appState
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
                ContentUnavailableView("Select a setting", systemImage: "gear")
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

                NodeSettingsSection(showingLocationPicker: $showingLocationPicker)

                if appState.currentTransportType == .wifi {
                    WiFiSection(showingEditSheet: $showingWiFiEditSheet)
                } else {
                    BluetoothSection()
                }

                NotificationSettingsSection()

                LinkPreviewSettingsSection()

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
                    Text("Radio tuning, telemetry, contact settings, and device management")
                }

                AboutSection()

                DiagnosticsSection()

            } else {
                NoDeviceSection(showingDeviceSelection: $showingDeviceSelection)
            }

            if demoModeManager.isUnlocked {
                Section {
                    Toggle("Enabled", isOn: Binding(
                        get: { demoModeManager.isEnabled },
                        set: { demoModeManager.isEnabled = $0 }
                    ))
                } header: {
                    Text("Demo Mode")
                } footer: {
                    Text("Demo mode allows testing without hardware using mock data.")
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
        }
        .navigationTitle("Settings")
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
                Text("Advanced Settings")
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

// MARK: - About View

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("About")
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
