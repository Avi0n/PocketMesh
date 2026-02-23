import OSLog
import SwiftUI
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "LocationSettings")

/// Location settings: set location, share publicly, auto-update from GPS
struct LocationSettingsSection: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var showingLocationPicker: Bool
    @State private var shareLocation = false
    @State private var autoUpdateLocation = false
    @State private var gpsSource: GPSSource = .phone
    @State private var deviceHasGPS = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()
    @State private var isSaving = false
    @State private var didLoad = false

    private let devicePreferenceStore = DevicePreferenceStore()

    private var shouldPollDeviceGPS: Bool {
        autoUpdateLocation && gpsSource == .device
    }

    var body: some View {
        Section {
            // Set Location
            Button {
                showingLocationPicker = true
            } label: {
                HStack {
                    TintedLabel(L10n.Settings.Node.setLocation, systemImage: "mappin.and.ellipse")
                    Spacer()
                    if let device = appState.connectedDevice,
                       device.latitude != 0 || device.longitude != 0 {
                        Text(L10n.Settings.Node.locationSet)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.Settings.Node.locationNotSet)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .radioDisabled(for: appState.connectionState, or: isSaving || autoUpdateLocation)

            // Share Location Publicly
            Toggle(isOn: $shareLocation) {
                TintedLabel(L10n.Settings.Node.shareLocationPublicly, systemImage: "location")
            }
            .onChange(of: shareLocation) { _, newValue in
                guard didLoad else { return }
                updateShareLocation(newValue)
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

            // Auto-Update Location
            Toggle(isOn: $autoUpdateLocation) {
                TintedLabel(L10n.Settings.Location.autoUpdate, systemImage: "location.circle")
            }
            .onChange(of: autoUpdateLocation) { _, newValue in
                guard let deviceID = appState.connectedDevice?.id else { return }
                devicePreferenceStore.setAutoUpdateLocationEnabled(newValue, deviceID: deviceID)
                if newValue {
                    if gpsSource == .phone {
                        appState.locationService.requestPermissionIfNeeded()
                    }
                }
                if !newValue, gpsSource == .device {
                    disableDeviceGPS()
                }
            }
            .radioDisabled(for: appState.connectionState, or: isSaving)

            // GPS Source (only show picker when device has GPS hardware)
            if autoUpdateLocation, deviceHasGPS {
                Picker(L10n.Settings.Location.gpsSource, selection: $gpsSource) {
                    Text(L10n.Settings.Location.GpsSource.phone).tag(GPSSource.phone)
                    Text(L10n.Settings.Location.GpsSource.device).tag(GPSSource.device)
                }
                .onChange(of: gpsSource) { _, newValue in
                    guard let deviceID = appState.connectedDevice?.id else { return }
                    devicePreferenceStore.setGPSSource(newValue, deviceID: deviceID)
                    if newValue == .phone {
                        appState.locationService.requestPermissionIfNeeded()
                        disableDeviceGPS()
                    } else if newValue == .device {
                        enableDeviceGPS()
                    }
                }
                .radioDisabled(for: appState.connectionState, or: isSaving)
            }
        } header: {
            Text(L10n.Settings.Location.header)
        } footer: {
            Text(L10n.Settings.Location.footer)
        }
        .task(id: startupTaskID) {
            loadPreferences()
            guard appState.canRunSettingsStartupReads else {
                logger.debug("Deferring location settings startup reads until sync is less contended")
                return
            }
            await queryDeviceGPSCapability()
        }
        .task(id: shouldPollDeviceGPS) {
            guard shouldPollDeviceGPS,
                  let settingsService = appState.services?.settingsService else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let device = appState.connectedDevice,
                      device.latitude == 0, device.longitude == 0 else { break }
                try? await settingsService.refreshDeviceInfo()
            }
        }
        .errorAlert($showError)
        .retryAlert(retryAlert)
    }

    private var startupTaskID: String {
        let deviceID = appState.connectedDevice?.id.uuidString ?? "none"
        let syncPhase = appState.connectionUI.currentSyncPhase.map { String(describing: $0) } ?? "none"
        return "\(deviceID)-\(String(describing: appState.connectionState))-\(syncPhase)"
    }

    private func loadPreferences() {
        if let device = appState.connectedDevice {
            shareLocation = device.advertLocationPolicy == 1
            autoUpdateLocation = devicePreferenceStore.isAutoUpdateLocationEnabled(deviceID: device.id)
            gpsSource = devicePreferenceStore.gpsSource(deviceID: device.id)
        }
        didLoad = true
    }

    private func queryDeviceGPSCapability() async {
        guard appState.canRunSettingsStartupReads else { return }
        guard let settingsService = appState.services?.settingsService else { return }
        do {
            let vars = try await settingsService.getCustomVars()
            deviceHasGPS = vars.keys.contains("gps")
            // If device GPS is already active, default to device source on first visit
            if let deviceID = appState.connectedDevice?.id,
               vars["gps"] == "1",
               !devicePreferenceStore.hasSetGPSSource(deviceID: deviceID) {
                gpsSource = .device
                devicePreferenceStore.setGPSSource(.device, deviceID: deviceID)
            }
            // Refresh device info to pick up GPS-derived coordinates
            if vars["gps"] == "1" {
                try? await settingsService.refreshDeviceInfo()
            }
        } catch {
            deviceHasGPS = false
        }
    }

    private func enableDeviceGPS() {
        guard let settingsService = appState.services?.settingsService else { return }
        Task {
            do {
                try await settingsService.setCustomVar(key: "gps", value: "1")
                try await settingsService.refreshDeviceInfo()
            } catch {
                logger.warning("Failed to enable device GPS: \(error.localizedDescription)")
            }
        }
    }

    private func disableDeviceGPS() {
        guard let settingsService = appState.services?.settingsService else { return }
        Task {
            do {
                try await settingsService.setCustomVar(key: "gps", value: "0")
            } catch {
                logger.warning("Failed to disable device GPS: \(error.localizedDescription)")
            }
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
                shareLocation = !share
                retryAlert.show(
                    message: error.errorDescription ?? L10n.Settings.Alert.Retry.fallbackMessage,
                    onRetry: { updateShareLocation(share) },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                shareLocation = !share
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
