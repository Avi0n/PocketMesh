import SwiftUI
import MapKit
import PocketMeshKit

/// Node name and location settings
struct NodeSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var nodeName: String = ""
    @State private var isEditingName = false
    @State private var showingLocationPicker = false
    @State private var shareLocation = false
    @State private var showError: String?

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
            }

            // Public Key (copy)
            if let device = appState.connectedDevice {
                Button {
                    let hex = device.publicKey.map { String(format: "%02X", $0) }.joined()
                    UIPasteboard.general.string = hex
                } label: {
                    HStack {
                        Label("Public Key", systemImage: "key")
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
                    Label("Set Location", systemImage: "mappin.and.ellipse")
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

            // Share Location Toggle
            Toggle(isOn: $shareLocation) {
                Label("Share Location Publicly", systemImage: "location")
            }
            .onChange(of: shareLocation) { _, newValue in
                updateShareLocation(newValue)
            }

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
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView()
        }
        .errorAlert($showError)
    }

    private func saveNodeName() {
        let name = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            do {
                try await appState.settingsService.setNodeName(name)
                await appState.refreshDeviceInfo()
            } catch {
                showError = error.localizedDescription
            }
        }
    }

    private func updateShareLocation(_ share: Bool) {
        guard let device = appState.connectedDevice else { return }

        Task {
            do {
                let telemetryModes = TelemetryModes(
                    base: TelemetryMode(rawValue: device.telemetryModeBase) ?? .deny,
                    location: TelemetryMode(rawValue: device.telemetryModeLoc) ?? .deny,
                    environment: TelemetryMode(rawValue: device.telemetryModeEnv) ?? .deny
                )
                try await appState.settingsService.setOtherParams(
                    autoAddContacts: !device.manualAddContacts,
                    telemetryModes: telemetryModes,
                    shareLocationPublicly: share,
                    multiAcks: device.multiAcks
                )
                await appState.refreshDeviceInfo()
            } catch {
                shareLocation = !share // Revert
                showError = error.localizedDescription
            }
        }
    }
}
