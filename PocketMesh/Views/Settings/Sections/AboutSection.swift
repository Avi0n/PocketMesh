import SwiftUI

/// About and links section
struct AboutSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExporting = false
    @State private var exportFileURL: URL?

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

        Section {
            Button {
                exportLogs()
            } label: {
                HStack {
                    Label("Export Debug Logs", systemImage: "arrow.up.doc")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
        } header: {
            Text("Support")
        }
        .sheet(item: $exportFileURL) { url in
            ShareSheet(activityItems: [url])
        }
    }

    private func exportLogs() {
        isExporting = true
        Task {
            exportFileURL = await LogExportService.createExportFile(appState: appState)
            isExporting = false
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// UIKit ShareSheet wrapper for SwiftUI
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
