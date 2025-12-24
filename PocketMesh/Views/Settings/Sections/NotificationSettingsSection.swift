import PocketMeshServices
import SwiftUI

/// Notification toggle settings
struct NotificationSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = NotificationPreferencesStore()

    private var notificationService: NotificationService? {
        appState.services?.notificationService
    }

    var body: some View {
        Section {
            if let service = notificationService {
                switch service.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    notificationToggles

                case .notDetermined:
                    Button {
                        Task {
                            await service.requestAuthorization()
                        }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }

                case .denied:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications Disabled", systemImage: "bell.slash")
                            .foregroundStyle(.secondary)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(.subheadline)
                    }

                @unknown default:
                    notificationToggles
                }
            } else {
                Text("Connect a device to configure notifications")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await notificationService?.checkAuthorizationStatus()
                }
            }
        }
    }

    @ViewBuilder
    private var notificationToggles: some View {
        Toggle(isOn: $preferences.contactMessagesEnabled) {
            Label("Contact Messages", systemImage: "message")
        }

        Toggle(isOn: $preferences.channelMessagesEnabled) {
            Label("Channel Messages", systemImage: "person.3")
        }

        Toggle(isOn: $preferences.roomMessagesEnabled) {
            Label("Room Messages", systemImage: "bubble.left.and.bubble.right")
        }

        Toggle(isOn: $preferences.newContactDiscoveredEnabled) {
            Label("New Contact Discovered", systemImage: "person.badge.plus")
        }
    }
}
