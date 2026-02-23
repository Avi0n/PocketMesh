import SwiftUI

/// About and links section
struct AboutSection: View {
    var body: some View {
        Section {
            Link(destination: URL(string: "https://meshcore.co.uk")!) {
                HStack {
                    TintedLabel(L10n.Settings.About.website, systemImage: "globe")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://map.meshcore.dev")!) {
                HStack {
                    TintedLabel(L10n.Settings.About.onlineMap, systemImage: "map")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://github.com/Avi0n/PocketMesh")!) {
                HStack {
                    TintedLabel(L10n.Settings.About.github, systemImage: "chevron.left.forwardslash.chevron.right")
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
