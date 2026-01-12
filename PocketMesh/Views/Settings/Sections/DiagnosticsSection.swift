import PocketMeshServices
import SwiftUI
import UIKit

/// Settings section for diagnostic tools including log export and clearing
struct DiagnosticsSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExporting = false
    @State private var showingClearLogsAlert = false
    @State private var showError: String?

    var body: some View {
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

            Button(role: .destructive) {
                showingClearLogsAlert = true
            } label: {
                Label("Clear Debug Logs", systemImage: "trash")
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Export includes debug logs from the last 24 hours across app sessions. Logs are stored locally and automatically pruned.")
        }
        .alert("Clear Debug Logs", isPresented: $showingClearLogsAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearDebugLogs()
            }
        } message: {
            Text("This will delete all stored debug logs. Exported log files will not be affected.")
        }
        .errorAlert($showError)
    }

    private func exportLogs() {
        guard let dataStore = appState.services?.dataStore else { return }
        isExporting = true

        Task {
            if let url = await LogExportService.createExportFile(
                appState: appState,
                persistenceStore: dataStore
            ) {
                await MainActor.run {
                    let activityVC = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )

                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController {
                            topVC = presented
                        }

                        // Configure popover for iPad
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = topVC.view
                            popover.sourceRect = CGRect(
                                x: topVC.view.bounds.midX,
                                y: topVC.view.bounds.midY,
                                width: 0,
                                height: 0
                            )
                            popover.permittedArrowDirections = []
                        }

                        topVC.present(activityVC, animated: true)
                    }

                    isExporting = false
                }
            } else {
                await MainActor.run {
                    showError = "Failed to create export file"
                    isExporting = false
                }
            }
        }
    }

    private func clearDebugLogs() {
        guard let dataStore = appState.services?.dataStore else { return }

        Task {
            do {
                try await dataStore.clearDebugLogEntries()
            } catch {
                await MainActor.run {
                    showError = error.localizedDescription
                }
            }
        }
    }
}
