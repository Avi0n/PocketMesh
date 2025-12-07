import SwiftUI
import PocketMeshKit

/// Main settings screen for the app
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingDisconnectAlert = false
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Connected device section
                if let device = appState.connectedDevice {
                    Section {
                        NavigationLink {
                            DeviceInfoView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                    .frame(width: 40, height: 40)
                                    .background(.tint.opacity(0.1), in: .circle)

                                VStack(alignment: .leading) {
                                    Text(device.nodeName)
                                        .font(.headline)

                                    Text("Connected")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Device")
                    }

                    // Radio settings
                    Section {
                        NavigationLink {
                            RadioConfigView()
                        } label: {
                            Label("Radio Configuration", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        NavigationLink {
                            NodeSettingsView()
                        } label: {
                            Label("Node Settings", systemImage: "slider.horizontal.3")
                        }

                        NavigationLink {
                            ChannelSettingsView()
                        } label: {
                            Label("Channels", systemImage: "person.3.fill")
                        }
                    } header: {
                        Text("Configuration")
                    }
                } else {
                    // No device connected
                    Section {
                        Button {
                            Task {
                                // Force disconnect any existing connection before scanning
                                await appState.disconnectForNewConnection()
                                appState.resetOnboarding()
                            }
                        } label: {
                            Label("Connect Device", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    } header: {
                        Text("Device")
                    } footer: {
                        Text("No MeshCore device connected")
                    }
                }

                // App settings
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush.fill")
                    }

                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("App Settings")
                }

                // About section
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About PocketMesh", systemImage: "info.circle.fill")
                    }

                    Link(destination: URL(string: "https://meshcore.co")!) {
                        Label("MeshCore Website", systemImage: "globe")
                    }
                } header: {
                    Text("About")
                }

                // Danger zone
                if appState.connectedDevice != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDisconnectAlert = true
                        } label: {
                            Label("Disconnect Device", systemImage: "eject.fill")
                        }

                        Button(role: .destructive) {
                            showingResetAlert = true
                        } label: {
                            Label("Factory Reset Device", systemImage: "exclamationmark.triangle.fill")
                        }
                    } header: {
                        Text("Danger Zone")
                    } footer: {
                        Text("Factory reset will erase all contacts and settings on the device.")
                    }
                }

                #if DEBUG
                // Debug section
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
            .alert("Disconnect Device", isPresented: $showingDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    Task {
                        await appState.disconnect()
                    }
                }
            } message: {
                Text("Are you sure you want to disconnect from this device?")
            }
            .alert("Factory Reset", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    // TODO: Implement factory reset
                }
            } message: {
                Text("This will erase all data on the device including contacts, messages, and settings. This action cannot be undone.")
            }
        }
    }
}

// MARK: - Placeholder Views for Navigation

struct NodeSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            if let device = appState.connectedDevice {
                Section {
                    HStack {
                        Text("Node Name")
                        Spacer()
                        Text(device.nodeName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Manual Contact Add")
                        Spacer()
                        Text(device.manualAddContacts ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Multi-ACK")
                        Spacer()
                        Text(device.multiAcks ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Node")
                }

                Section {
                    HStack {
                        Text("Location Sharing")
                        Spacer()
                        Text(device.advertLocationPolicy == 1 ? "Enabled" : "Disabled")
                            .foregroundStyle(.secondary)
                    }

                    if device.latitude != 0 || device.longitude != 0 {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            Text(device.latitude, format: .number.precision(.fractionLength(6)))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Longitude")
                            Spacer()
                            Text(device.longitude, format: .number.precision(.fractionLength(6)))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Location")
                }
            }
        }
        .navigationTitle("Node Settings")
    }
}

struct ChannelSettingsView: View {
    var body: some View {
        List {
            Section {
                Text("Channel configuration will be available in a future update")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Channels")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("badgeEnabled") private var badgeEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("Sound", isOn: $soundEnabled)
                    .disabled(!notificationsEnabled)
                Toggle("Badge", isOn: $badgeEnabled)
                    .disabled(!notificationsEnabled)
            }
        }
        .navigationTitle("Notifications")
    }
}

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

struct PrivacySettingsView: View {
    @AppStorage("shareLocation") private var shareLocation = false
    @AppStorage("shareReadReceipts") private var shareReadReceipts = true

    var body: some View {
        Form {
            Section {
                Toggle("Share Location", isOn: $shareLocation)
                Toggle("Send Read Receipts", isOn: $shareReadReceipts)
            } footer: {
                Text("Location sharing allows contacts to see your position on the map.")
            }
        }
        .navigationTitle("Privacy")
    }
}

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
                Link("Privacy Policy", destination: URL(string: "https://meshcore.co/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://meshcore.co/terms")!)
                Link("Open Source Licenses", destination: URL(string: "https://meshcore.co/licenses")!)
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
