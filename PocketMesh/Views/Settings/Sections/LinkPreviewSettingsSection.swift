import SwiftUI

/// Settings section for link preview preferences
struct LinkPreviewSettingsSection: View {
    @AppStorage("linkPreviewsEnabled") private var previewsEnabled = false
    @AppStorage("linkPreviewsAutoResolveDM") private var autoResolveDM = true
    @AppStorage("linkPreviewsAutoResolveChannels") private var autoResolveChannels = true

    var body: some View {
        Section {
            Toggle(isOn: $previewsEnabled) {
                Label(L10n.Settings.LinkPreviews.toggle, systemImage: "link")
            }

            if previewsEnabled {
                Toggle(L10n.Settings.LinkPreviews.showInDMs, isOn: $autoResolveDM)
                Toggle(L10n.Settings.LinkPreviews.showInChannels, isOn: $autoResolveChannels)
            }
        } header: {
            Text(L10n.Settings.LinkPreviews.header)
        } footer: {
            Text(L10n.Settings.LinkPreviews.footer)
        }
    }
}

#Preview {
    Form {
        LinkPreviewSettingsSection()
    }
}
