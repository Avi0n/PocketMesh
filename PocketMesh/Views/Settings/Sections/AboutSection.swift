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
                    Label("MeshCore Website", systemImage: "globe")
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
