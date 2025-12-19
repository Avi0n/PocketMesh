import PocketMeshServices
import SwiftUI

/// Notification toggle settings
struct NotificationSettingsSection: View {
    @State private var preferences = NotificationPreferencesStore()

    var body: some View {
        Section {
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
        } header: {
            Text("Notifications")
        }
    }
}
