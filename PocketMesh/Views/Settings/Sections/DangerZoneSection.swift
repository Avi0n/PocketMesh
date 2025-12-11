import SwiftUI
import PocketMeshKit

/// Destructive device actions
struct DangerZoneSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingDisconnectAlert = false
    @State private var showingForgetAlert = false
    @State private var showingResetAlert = false
    @State private var isResetting = false
    @State private var showError: String?

    var body: some View {
        Section {
            Button(role: .destructive) {
                showingDisconnectAlert = true
            } label: {
                Label("Disconnect Device", systemImage: "eject")
            }

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
            .disabled(isResetting)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Factory reset erases all contacts, messages, and settings on the device.")
        }
        .alert("Disconnect Device", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                Task {
                    await appState.disconnect()
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to disconnect from this device?")
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
        guard let deviceID = appState.connectedDevice?.id,
              let accessory = appState.accessorySetupKit.accessory(for: deviceID) else {
            return
        }

        Task {
            do {
                try await appState.accessorySetupKit.removeAccessory(accessory)
                await appState.disconnect()
                dismiss()
            } catch {
                showError = error.localizedDescription
            }
        }
    }

    private func factoryReset() {
        isResetting = true
        Task {
            do {
                try await appState.settingsService.factoryReset()

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
