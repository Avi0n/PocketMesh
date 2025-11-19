import SwiftUI
import PocketMeshKit

struct SettingsView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    @AppStorage("autoAddContacts") private var autoAddContacts = true
    @AppStorage("messageNotifications") private var messageNotifications = true
    @AppStorage("lowBatteryWarnings") private var lowBatteryWarnings = true

    var body: some View {
        NavigationStack {
            List {
                Section("Connected Device") {
                    if let device = coordinator.connectedDevice {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(device.name)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Firmware")
                            Spacer()
                            Text(device.firmwareVersion)
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink("Radio Configuration") {
                            RadioConfigView(device: device)
                        }
                    } else {
                        Text("No device connected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Contacts") {
                    Toggle("Auto-add new contacts", isOn: $autoAddContacts)
                }

                Section("Notifications") {
                    Toggle("Message notifications", isOn: $messageNotifications)
                    Toggle("Low battery warnings", isOn: $lowBatteryWarnings)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
