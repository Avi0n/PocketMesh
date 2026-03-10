import PocketMeshServices
import SwiftUI

/// Settings section for diagnostic tools including log export and clearing
struct DiagnosticsSection: View {
    @Environment(\.appState) private var appState
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showingClearLogsAlert = false
    @State private var showError: String?

    var body: some View {
        Section {
            if let url = exportedFileURL {
                ShareLink(item: url, preview: SharePreview(L10n.Settings.Diagnostics.exportLogs)) {
                    TintedLabel(L10n.Settings.Diagnostics.exportLogs, systemImage: "arrow.up.doc")
                }
            } else {
                Button {
                    exportLogs()
                } label: {
                    HStack {
                        TintedLabel(L10n.Settings.Diagnostics.exportLogs, systemImage: "arrow.up.doc")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
            }

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

        Task { @MainActor in
            if let url = await LogExportService.createExportFile(
                appState: appState,
                persistenceStore: dataStore
            ) {
                exportedFileURL = url
            } else {
                showError = L10n.Settings.Diagnostics.Error.exportFailed
            }
            isExporting = false
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
