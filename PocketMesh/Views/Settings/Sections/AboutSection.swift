import SwiftUI

/// About and links section
struct AboutSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About PocketMesh", systemImage: "info.circle")
            }

            Link(destination: URL(string: "https://meshcore.co.uk")!) {
                HStack {
                    Label {
                        Text("MeshCore Website")
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

            Link(destination: URL(string: "https://meshcore.co.uk/map.html")!) {
                HStack {
                    Label {
                        Text("MeshCore Online Map")
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
        } header: {
            Text("About")
        }
    }
}
