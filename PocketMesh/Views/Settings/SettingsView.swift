import SwiftUI
import PocketMeshKit
import MapKit
#if DEBUG
import DataScoutCompanion
#endif

/// Main settings screen prioritizing new user experience
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAdvancedSettings = false
    @State private var showingDeviceSelection = false
    @State private var showingLocationPicker = false
    #if DEBUG
    @State private var showingDatabaseBrowser = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                if let device = appState.connectedDevice {
                    // Device Info Header (read-only)
                    DeviceInfoSection(device: device)

                    // Radio Preset
                    RadioPresetSection()

                    // Node Settings
                    NodeSettingsSection(showingLocationPicker: $showingLocationPicker)

                    // Bluetooth
                    BluetoothSection()

                    // Notifications
                    NotificationSettingsSection()

                    // Advanced Settings Link
                    Section {
                        Button {
                            showingAdvancedSettings = true
                        } label: {
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
                        .foregroundStyle(.primary)
                    } footer: {
                        Text("Radio tuning, telemetry, contact settings, and device management")
                    }

                    // About
                    AboutSection()

                } else {
                    NoDeviceSection(showingDeviceSelection: $showingDeviceSelection)
                }

                #if DEBUG
                // Debug section
                Section {
                    Button {
                        showingDatabaseBrowser = true
                    } label: {
                        Label("Database Browser", systemImage: "tablecells")
                    }

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
            .sheet(isPresented: $showingAdvancedSettings) {
                AdvancedSettingsView()
            }
            .sheet(isPresented: $showingDeviceSelection) {
                DeviceSelectionSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView()
            }
            #if DEBUG
            .sheet(isPresented: $showingDatabaseBrowser) {
                DatabaseBrowser()
            }
            #endif
        }
    }
}

// MARK: - Appearance Settings (Preserved for separate access)

struct AppearanceSettingsView: View {
    @AppStorage("colorScheme") private var colorScheme = 0

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $colorScheme) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Appearance")
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

            Section {
                Link("Privacy Policy", destination: URL(string: "https://meshcore.co.uk/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://meshcore.co.uk/terms")!)
                Link("Open Source Licenses", destination: URL(string: "https://meshcore.co.uk/licenses")!)
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
