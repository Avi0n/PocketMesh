import SwiftUI

/// Settings section for link preview preferences
struct LinkPreviewSettingsSection: View {
    @State private var preferences = LinkPreviewPreferences()

    var body: some View {
        Section {
            Toggle(isOn: $preferences.previewsEnabled) {
                Label("Link Previews", systemImage: "link")
            }

            if preferences.previewsEnabled {
                Toggle(isOn: $preferences.autoResolveDM) {
                    VStack(alignment: .leading) {
                        Text("Load Automatically in Direct Messages")
                        Text("Fetches previews when messages appear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $preferences.autoResolveChannels) {
                    VStack(alignment: .leading) {
                        Text("Load Automatically in Channels")
                        Text("Fetches previews when messages appear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
