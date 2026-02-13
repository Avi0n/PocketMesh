import SwiftUI

/// Settings section for link preview preferences
struct LinkPreviewSettingsSection: View {
    @AppStorage("linkPreviewsEnabled") private var previewsEnabled = false
    @AppStorage("linkPreviewsAutoResolveDM") private var autoResolveDM = true
    @AppStorage("linkPreviewsAutoResolveChannels") private var autoResolveChannels = true
    @AppStorage("showInlineImages") private var showInlineImages = true
    @AppStorage("autoPlayGIFs") private var autoPlayGIFs = true

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

        Section {
            Toggle(isOn: $showInlineImages) {
                Label(L10n.Settings.InlineImages.toggle, systemImage: "photo")
            }

            if showInlineImages {
                Toggle(isOn: $autoPlayGIFs) {
                    Label(L10n.Settings.InlineImages.autoPlayGifs, systemImage: "play.square")
                }
            }
        } footer: {
            Text(L10n.Settings.InlineImages.footer)
        }
    }
}

#Preview {
    Form {
        LinkPreviewSettingsSection()
    }
}
