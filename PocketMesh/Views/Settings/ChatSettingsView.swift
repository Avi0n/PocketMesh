import SwiftUI

struct ChatSettingsView: View {
    var body: some View {
        List {
            LinkPreviewSettingsSection()
            BlockingSection()
        }
        .navigationTitle(L10n.Settings.ChatSettings.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
