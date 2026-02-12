import SwiftUI
import PocketMeshServices

/// Destructive device actions
struct DangerZoneSection: View {
    @Environment(\.appState) private var appState
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
                Label(L10n.Settings.DangerZone.forgetDevice, systemImage: "trash")
            }

            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                if isResetting {
                    HStack {
                        ProgressView()
                        Text(L10n.Settings.DangerZone.resetting)
                    }
                } else {
                    Label(L10n.Settings.DangerZone.factoryReset, systemImage: "exclamationmark.triangle")
                }
            }
            .radioDisabled(for: appState.connectionState, or: isResetting)
        } header: {
            Text(L10n.Settings.DangerZone.header)
        } footer: {
            Text(L10n.Settings.DangerZone.footer)
        }
        .alert(L10n.Settings.DangerZone.Alert.Forget.title, isPresented: $showingForgetAlert) {
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
            Button(L10n.Settings.DangerZone.Alert.Forget.confirm, role: .destructive) {
                forgetDevice()
            }
        } message: {
            Text(L10n.Settings.DangerZone.Alert.Forget.message)
        }
        .alert(L10n.Settings.DangerZone.Alert.Reset.title, isPresented: $showingResetAlert) {
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
            Button(L10n.Settings.DangerZone.Alert.Reset.confirm, role: .destructive) {
                factoryReset()
            }
        } message: {
            Text(L10n.Settings.DangerZone.Alert.Reset.message)
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
            showError = L10n.Settings.DangerZone.Error.servicesUnavailable
            return
        }

        guard let deviceID = appState.connectedDevice?.id else {
            showError = L10n.Settings.DangerZone.Error.servicesUnavailable
            return
        }

        isResetting = true
        Task {
            defer { isResetting = false }

            // Send reset command. The device typically reboots before responding,
            // so a timeout/connection error here is expected — not a failure.
            do {
                try await settingsService.factoryReset()
                try await Task.sleep(for: .seconds(1))
            } catch {
                // Expected: device reboots before sending OK response
            }

            // Always clean up: remove from ASK, disconnect, delete from SwiftData
            await appState.connectionManager.forgetDevice(id: deviceID)
            dismiss()
        }
    }
}
