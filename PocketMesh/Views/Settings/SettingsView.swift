import PocketMeshKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @AppStorage("autoAddContacts") private var autoAddContacts = true
    @AppStorage("messageNotifications") private var messageNotifications = true
    @AppStorage("lowBatteryWarnings") private var lowBatteryWarnings = true

    @State private var isSyncingTime = false
    @State private var timeSyncAlert: AlertInfo?

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

                if coordinator.connectedDevice != nil {
                    Section("Device Time") {
                        Button {
                            Task {
                                await syncDeviceTime()
                            }
                        } label: {
                            HStack {
                                Text("Sync Time to Device")
                                if isSyncingTime {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isSyncingTime)
                    }
                }

                Section("Contacts") {
                    Toggle("Auto-add new contacts", isOn: $autoAddContacts)
                }

                Section("Notifications") {
                    Toggle("Message notifications", isOn: $messageNotifications)
                    Toggle("Low battery warnings", isOn: $lowBatteryWarnings)
                }

                Section("Messaging") {
                    NavigationLink("Message Delivery") {
                        if let messageService = coordinator.messageService {
                            AdvancedMessagingSettingsView(messageService: messageService)
                        }
                    }
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
            .alert(item: $timeSyncAlert) { alert in
                Alert(
                    title: alert.title,
                    message: alert.message,
                    dismissButton: alert.dismissButton,
                )
            }
        }
    }

    private func syncDeviceTime() async {
        guard let meshProtocol = coordinator.meshProtocol else {
            timeSyncAlert = AlertInfo(
                title: Text("Error"),
                message: Text("No protocol handler available"),
                dismissButton: .default(Text("OK")),
            )
            return
        }

        isSyncingTime = true
        defer { isSyncingTime = false }

        do {
            try await meshProtocol.syncDeviceTime()
            timeSyncAlert = AlertInfo(
                title: Text("Success"),
                message: Text("Device time synchronized successfully"),
                dismissButton: .default(Text("OK")),
            )
        } catch {
            timeSyncAlert = AlertInfo(
                title: Text("Error"),
                message: Text("Failed to sync device time: \(error.localizedDescription)"),
                dismissButton: .default(Text("OK")),
            )
        }
    }
}

// Helper for alert management
struct AlertInfo: Identifiable {
    let id = UUID()
    let title: Text
    let message: Text
    let dismissButton: Alert.Button
}
