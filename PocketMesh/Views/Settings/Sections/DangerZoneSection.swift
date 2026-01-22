import SwiftUI
import PocketMeshServices

/// Destructive device actions
struct DangerZoneSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingForgetAlert = false
    @State private var showingResetAlert = false
    @State private var isResetting = false
    @State private var showError: String?

    var body: some View {
        Section {
            Button(role: .destructive) {
                showingForgetAlert = true
            } label: {
                Label("Forget Device", systemImage: "trash")
            }

            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                if isResetting {
                    HStack {
                        ProgressView()
                        Text("Resetting...")
                    }
                } else {
                    Label("Factory Reset Device", systemImage: "exclamationmark.triangle")
                }
            }
            .radioDisabled(for: appState.connectionState, or: isResetting)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Factory reset erases all contacts, messages, and settings on the device.")
        }
        .alert("Forget Device", isPresented: $showingForgetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Forget", role: .destructive) {
                forgetDevice()
            }
        } message: {
            Text("This will remove the device from your paired devices. You can pair it again later.")
        }
        .alert("Factory Reset", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                factoryReset()
            }
        } message: {
            Text("This will erase ALL data on the device including contacts, messages, and settings. This cannot be undone.")
        }
        .errorAlert($showError)
    }

    private func forgetDevice() {
        Task {
            do {
                try await appState.connectionManager.forgetDevice()
                dismiss()
            } catch {
                showError = error.localizedDescription
            }
        }
    }

    private func factoryReset() {
        guard let settingsService = appState.services?.settingsService else {
            showError = "Services not available"
            return
        }

        isResetting = true
        Task {
            do {
                try await settingsService.factoryReset()

                // Wait briefly then disconnect
                try await Task.sleep(for: .seconds(1))
                await appState.disconnect()
                dismiss()
            } catch {
                showError = error.localizedDescription
            }
            isResetting = false
        }
    }
}
