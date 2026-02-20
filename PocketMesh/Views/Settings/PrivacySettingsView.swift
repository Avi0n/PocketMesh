import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        List {
            LinkPreviewSettingsSection()
            BlockingSection()
        }
        .navigationTitle(L10n.Settings.Privacy.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
