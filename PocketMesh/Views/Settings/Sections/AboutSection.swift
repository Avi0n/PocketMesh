import SwiftUI

/// About and links section
struct AboutSection: View {
    var body: some View {
        Section {
            Link(destination: URL(string: "https://meshcore.co.uk")!) {
                HStack {
                    Label {
                        Text(L10n.Settings.About.website)
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://map.meshcore.dev")!) {
                HStack {
                    Label {
                        Text(L10n.Settings.About.onlineMap)
                    } icon: {
                        Image(systemName: "map")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://github.com/Avi0n/PocketMesh")!) {
                HStack {
                    Label {
                        Text(L10n.Settings.About.github)
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

        } header: {
            Text(L10n.Settings.About.header)
        }
    }
}
