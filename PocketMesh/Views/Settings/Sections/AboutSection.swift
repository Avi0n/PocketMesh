import SwiftUI

/// About and links section
struct AboutSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExporting = false

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
    }

    private func exportLogs() {
        isExporting = true
        Task {
            guard let fileURL = await LogExportService.createExportFile(appState: appState) else {
                isExporting = false
                return
            }

            await MainActor.run {
                let activityVC = UIActivityViewController(
                    activityItems: [fileURL],
                    applicationActivities: nil
                )

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    // Find the topmost presented controller
                    var topVC = rootVC
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }
                    topVC.present(activityVC, animated: true)
                }

                isExporting = false
            }
        }
    }
}
