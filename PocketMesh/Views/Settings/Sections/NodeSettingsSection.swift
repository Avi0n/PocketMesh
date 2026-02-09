import SwiftUI
import PocketMeshServices

/// Node identity settings (name and public key)
struct NodeSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var nodeName: String = ""
    @State private var isEditingName = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false
    @State private var copyHapticTrigger = 0

    var body: some View {
        Section {
            // Node Name
            HStack {
                Label(L10n.Settings.Node.name, systemImage: "person.text.rectangle")
                Spacer()
                Button(appState.connectedDevice?.nodeName ?? L10n.Settings.Node.unknown) {
                    nodeName = appState.connectedDevice?.nodeName ?? ""
                    isEditingName = true
                }
                .foregroundStyle(.secondary)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

            // Public Key (copy)
            if let device = appState.connectedDevice {
                Button {
                    copyHapticTrigger += 1
                    let hex = device.publicKey.map { String(format: "%02X", $0) }.joined()
                    UIPasteboard.general.string = hex
                } label: {
                    HStack {
                        Label {
                            Text(L10n.Settings.DeviceInfo.publicKey)
                        } icon: {
                            Image(systemName: "key")
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Text(L10n.Settings.Node.copy)
                            .foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text(L10n.Settings.Node.header)
        } footer: {
            Text(L10n.Settings.Node.footer)
        }
        .alert(L10n.Settings.Node.Alert.EditName.title, isPresented: $isEditingName) {
            TextField(L10n.Settings.Node.name, text: $nodeName)
                .onChange(of: nodeName) { _, newValue in
                    if newValue.utf8.count > ProtocolLimits.maxUsableNameBytes {
                        nodeName = newValue.utf8Prefix(maxBytes: ProtocolLimits.maxUsableNameBytes)
                    }
                }
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
            Button(L10n.Localizable.Common.save) {
                saveNodeName()
            }
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
    }

    private func saveNodeName() {
        let name = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                _ = try await settingsService.setNodeNameVerified(name)
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.errorDescription ?? L10n.Settings.Alert.Retry.fallbackMessage,
                    onRetry: { saveNodeName() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
