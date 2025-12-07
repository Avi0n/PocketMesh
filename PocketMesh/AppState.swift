import SwiftUI
import PocketMeshKit

/// App-wide state management using Observable
@Observable
@MainActor
public final class AppState {

    // MARK: - Onboarding State

    /// Whether the user has completed onboarding (stored property for @Observable tracking)
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    /// Current step in the onboarding flow
    var onboardingStep: OnboardingStep = .welcome

    // MARK: - Device Connection State

    /// The BLE service for device communication
    let bleService: BLEService

    /// Current connection state
    var connectionState: BLEConnectionState = .disconnected

    /// Connected device info (after successful connection)
    var connectedDevice: DeviceDTO?

    /// Last error encountered
    var lastError: String?

    /// Whether we're currently connecting to a device
    var isConnecting: Bool = false

    // MARK: - Discovered Devices

    /// Devices discovered during scanning
    var discoveredDevices: [DiscoveredDevice] = []

    /// Whether scanning is in progress
    var isScanning: Bool = false

    // MARK: - Initialization

    init(bleService: BLEService = BLEService()) {
        self.bleService = bleService
    }

    // MARK: - Scanning

    /// Start scanning for MeshCore devices
    func startScanning() async {
        guard !isScanning else { return }

        isScanning = true
        discoveredDevices = []
        lastError = nil

        do {
            await bleService.initialize()
            try await bleService.startScanning()

            // Listen for discovered devices
            for await device in await bleService.scanForDevices() {
                if !discoveredDevices.contains(where: { $0.id == device.id }) {
                    discoveredDevices.append(device)
                }
                discoveredDevices.sort { $0.rssi > $1.rssi }
            }
        } catch {
            lastError = error.localizedDescription
            isScanning = false
        }
    }

    /// Stop scanning for devices
    func stopScanning() async {
        await bleService.stopScanning()
        isScanning = false
    }

    // MARK: - Connection

    /// Connect to a discovered device
    func connect(to device: DiscoveredDevice) async throws {
        isConnecting = true
        lastError = nil

        defer { isConnecting = false }

        do {
            // Stop scanning first
            await stopScanning()

            // Connect to the device
            try await bleService.connect(to: device.id)

            // Initialize device and get info
            let (deviceInfo, selfInfo) = try await bleService.initializeDevice()

            // Update connection state
            connectionState = await bleService.connectionState

            // Create device DTO from the info
            // Note: In a full implementation, we'd save this to SwiftData
            connectedDevice = DeviceDTO(
                from: Device(
                    id: device.id,
                    publicKey: selfInfo.publicKey,
                    nodeName: selfInfo.nodeName,
                    firmwareVersion: deviceInfo.firmwareVersion,
                    firmwareVersionString: deviceInfo.firmwareVersionString,
                    manufacturerName: deviceInfo.manufacturerName,
                    buildDate: deviceInfo.buildDate,
                    maxContacts: deviceInfo.maxContacts,
                    maxChannels: deviceInfo.maxChannels,
                    frequency: selfInfo.frequency,
                    bandwidth: selfInfo.bandwidth,
                    spreadingFactor: selfInfo.spreadingFactor,
                    codingRate: selfInfo.codingRate,
                    txPower: selfInfo.txPower,
                    maxTxPower: selfInfo.maxTxPower,
                    latitude: selfInfo.latitude,
                    longitude: selfInfo.longitude,
                    blePin: deviceInfo.blePin,
                    manualAddContacts: selfInfo.manualAddContacts > 0,
                    isActive: true
                )
            )
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Disconnect from the current device
    func disconnect() async {
        await bleService.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
    }

    // MARK: - Onboarding Completion

    /// Mark onboarding as complete
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Reset onboarding (for testing)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        onboardingStep = .welcome
    }
}

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case deviceScan
    case devicePair

    var next: OnboardingStep? {
        guard let index = OnboardingStep.allCases.firstIndex(of: self),
              index + 1 < OnboardingStep.allCases.count else {
            return nil
        }
        return OnboardingStep.allCases[index + 1]
    }

    var previous: OnboardingStep? {
        guard let index = OnboardingStep.allCases.firstIndex(of: self),
              index > 0 else {
            return nil
        }
        return OnboardingStep.allCases[index - 1]
    }
}
