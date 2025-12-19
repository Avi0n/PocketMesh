import SwiftUI
import MapKit
import PocketMeshServices

/// Node name and location settings
struct NodeSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var showingLocationPicker: Bool
    @State private var nodeName: String = ""
    @State private var isEditingName = false
    @State private var shareLocation = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false

    var body: some View {
        Section {
            // Node Name
            HStack {
                Label("Node Name", systemImage: "person.text.rectangle")
                Spacer()
                Button(appState.connectedDevice?.nodeName ?? "Unknown") {
                    nodeName = appState.connectedDevice?.nodeName ?? ""
                    isEditingName = true
                }
                .foregroundStyle(.secondary)
                .disabled(isSaving)
            }

            // Public Key (copy)
            if let device = appState.connectedDevice {
                Button {
                    let hex = device.publicKey.map { String(format: "%02X", $0) }.joined()
                    UIPasteboard.general.string = hex
                } label: {
                    HStack {
                        Label {
                            Text("Public Key")
                        } icon: {
                            Image(systemName: "key")
                                .foregroundStyle(.tint)
                        }
                        Spacer()
                        Text("Copy")
                            .foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            }

            // Location
            Button {
                showingLocationPicker = true
            } label: {
                HStack {
                    Label {
                        Text("Set Location")
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    if let device = appState.connectedDevice,
                       device.latitude != 0 || device.longitude != 0 {
                        Text("Set")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not Set")
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .disabled(isSaving)

            // Share Location Toggle
            Toggle(isOn: $shareLocation) {
                Label("Share Location Publicly", systemImage: "location")
            }
            .onChange(of: shareLocation) { _, newValue in
                updateShareLocation(newValue)
            }
            .disabled(isSaving)

        } header: {
            Text("Node")
        } footer: {
            Text("Your node name and location are visible to other mesh users when shared.")
        }
        .onAppear {
            if let device = appState.connectedDevice {
                shareLocation = device.advertLocationPolicy == 1
            }
        }
        .alert("Edit Node Name", isPresented: $isEditingName) {
            TextField("Node Name", text: $nodeName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                saveNodeName()
            }
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
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
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { saveNodeName() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func updateShareLocation(_ share: Bool) {
        guard let device = appState.connectedDevice,
              let settingsService = appState.services?.settingsService else { return }

        isSaving = true
        Task {
            do {
                let telemetryModes = TelemetryModes(
                    base: device.telemetryModeBase,
                    location: device.telemetryModeLoc,
                    environment: device.telemetryModeEnv
                )
                _ = try await settingsService.setOtherParamsVerified(
                    autoAddContacts: !device.manualAddContacts,
                    telemetryModes: telemetryModes,
                    shareLocationPublicly: share,
                    multiAcks: device.multiAcks
                )
                retryAlert.reset()
            } catch let error as SettingsServiceError where error.isRetryable {
                shareLocation = !share // Revert
                retryAlert.show(
                    message: error.errorDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { updateShareLocation(share) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                shareLocation = !share // Revert
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
