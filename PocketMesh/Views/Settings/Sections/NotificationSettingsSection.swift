import PocketMeshServices
import SwiftUI

/// Notification toggle settings
struct NotificationSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = NotificationPreferencesStore()

    private var notificationService: NotificationService? {
        appState.services?.notificationService
    }

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            if let service = notificationService {
                switch service.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    Toggle(isOn: $preferences.contactMessagesEnabled) {
                        Label(L10n.Settings.Notifications.contactMessages, systemImage: "message")
                    }
                    Toggle(isOn: $preferences.channelMessagesEnabled) {
                        Label(L10n.Settings.Notifications.channelMessages, systemImage: "person.3")
                    }
                    Toggle(isOn: $preferences.roomMessagesEnabled) {
                        Label(L10n.Settings.Notifications.roomMessages, systemImage: "bubble.left.and.bubble.right")
                    }
                    Toggle(isOn: $preferences.newContactDiscoveredEnabled) {
                        Label(L10n.Settings.Notifications.newContactDiscovered, systemImage: "person.badge.plus")
                    }
                    Toggle(isOn: $preferences.reactionNotificationsEnabled) {
                        Label(L10n.Settings.Notifications.reactions, systemImage: "face.smiling")
                    }
                    Toggle(isOn: $preferences.lowBatteryEnabled) {
                        Label(L10n.Settings.Notifications.lowBattery, systemImage: "battery.25")
                    }

                case .notDetermined:
                    Button {
                        Task {
                            await service.requestAuthorization()
                        }
                    } label: {
                        Label(L10n.Settings.Notifications.enable, systemImage: "bell.badge")
                    }

                case .denied:
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.Settings.Notifications.disabled, systemImage: "bell.slash")
                            .foregroundStyle(.secondary)

                        Button(L10n.Settings.Notifications.openSettings) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(.subheadline)
                    }

                @unknown default:
                    Toggle(isOn: $preferences.contactMessagesEnabled) {
                        Label(L10n.Settings.Notifications.contactMessages, systemImage: "message")
                    }
                    Toggle(isOn: $preferences.channelMessagesEnabled) {
                        Label(L10n.Settings.Notifications.channelMessages, systemImage: "person.3")
                    }
                    Toggle(isOn: $preferences.roomMessagesEnabled) {
                        Label(L10n.Settings.Notifications.roomMessages, systemImage: "bubble.left.and.bubble.right")
                    }
                    Toggle(isOn: $preferences.newContactDiscoveredEnabled) {
                        Label(L10n.Settings.Notifications.newContactDiscovered, systemImage: "person.badge.plus")
                    }
                    Toggle(isOn: $preferences.reactionNotificationsEnabled) {
                        Label(L10n.Settings.Notifications.reactions, systemImage: "face.smiling")
                    }
                    Toggle(isOn: $preferences.lowBatteryEnabled) {
                        Label(L10n.Settings.Notifications.lowBattery, systemImage: "battery.25")
                    }
                }
            } else {
                Text(L10n.Settings.Notifications.connectDevice)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.Settings.Notifications.header)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await notificationService?.checkAuthorizationStatus()
                }
            }
        }
    }
}
