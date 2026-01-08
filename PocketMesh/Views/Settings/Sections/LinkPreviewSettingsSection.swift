import SwiftUI

/// Settings section for link preview preferences
struct LinkPreviewSettingsSection: View {
    @AppStorage("linkPreviewsEnabled") private var previewsEnabled = false
    @AppStorage("linkPreviewsAutoResolveDM") private var autoResolveDM = true
    @AppStorage("linkPreviewsAutoResolveChannels") private var autoResolveChannels = true

    var body: some View {
        Section {
            Toggle(isOn: $previewsEnabled) {
                Label("Link Previews", systemImage: "link")
            }

            if previewsEnabled {
                Toggle("Show in Direct Messages", isOn: $autoResolveDM)
                Toggle("Show in Channels", isOn: $autoResolveChannels)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Link previews fetch data from the web, which may reveal your IP address to the server hosting the link.")
        }
    }
}

#Preview {
    Form {
        LinkPreviewSettingsSection()
    }
}
