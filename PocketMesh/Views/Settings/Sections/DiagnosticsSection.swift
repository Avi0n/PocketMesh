import PocketMeshServices
import SwiftUI
import UIKit

/// Settings section for diagnostic tools including log export and clearing
struct DiagnosticsSection: View {
    @Environment(\.appState) private var appState
    @State private var isExporting = false
    @State private var showingClearLogsAlert = false
    @State private var showError: String?

    var body: some View {
        Section {
            Button {
                exportLogs()
            } label: {
                HStack {
                    Label(L10n.Settings.Diagnostics.exportLogs, systemImage: "arrow.up.doc")
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
                Label(L10n.Settings.Diagnostics.clearLogs, systemImage: "trash")
            }
        } header: {
            Text(L10n.Settings.Diagnostics.header)
        } footer: {
            Text(L10n.Settings.Diagnostics.footer)
        }
        .alert(L10n.Settings.Diagnostics.Alert.Clear.title, isPresented: $showingClearLogsAlert) {
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
            Button(L10n.Settings.Diagnostics.Alert.Clear.confirm, role: .destructive) {
                clearDebugLogs()
            }
        } message: {
            Text(L10n.Settings.Diagnostics.Alert.Clear.message)
        }
        .errorAlert($showError)
    }

    private func exportLogs() {
        let dataStore = appState.services?.dataStore ?? appState.connectionManager.createStandalonePersistenceStore()
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
                    showError = L10n.Settings.Diagnostics.Error.exportFailed
                    isExporting = false
                }
            }
        }
    }

    private func clearDebugLogs() {
        let dataStore = appState.services?.dataStore ?? appState.connectionManager.createStandalonePersistenceStore()

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
