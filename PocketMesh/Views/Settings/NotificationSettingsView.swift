import SwiftUI

struct NotificationSettingsView: View {
    var body: some View {
        List {
            NotificationSettingsSection()
        }
        .navigationTitle(L10n.Settings.Notifications.header)
        .navigationBarTitleDisplayMode(.inline)
    }
}
