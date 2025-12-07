import SwiftUI
import SwiftData
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

    // MARK: - Data Services

    /// The SwiftData model container
    let modelContainer: ModelContainer

    /// The data store for persistence operations
    let dataStore: PocketMeshKit.DataStore

    /// The message service for sending messages
    let messageService: MessageService

    /// The contact service for managing contacts
    let contactService: ContactService

    /// The message polling service for handling incoming messages
    let messagePollingService: MessagePollingService

    /// The message event broadcaster for UI updates
    let messageEventBroadcaster = MessageEventBroadcaster()

    // MARK: - Navigation State

    /// Currently selected tab index
    var selectedTab: Int = 0

    /// Contact to navigate to in chat (for cross-tab navigation)
    var pendingChatContact: ContactDTO?

    // MARK: - Initialization

    init(bleService: BLEService = BLEService(), modelContainer: ModelContainer? = nil) {
        self.bleService = bleService

        // Create or use provided model container
        if let container = modelContainer {
            self.modelContainer = container
        } else {
            do {
                self.modelContainer = try DataStore.createContainer()
            } catch {
                fatalError("Failed to create model container: \(error)")
            }
        }

        // Create data store
        self.dataStore = DataStore(modelContainer: self.modelContainer)

        // Create services
        self.messageService = MessageService(bleTransport: bleService, dataStore: dataStore)
        self.contactService = ContactService(bleTransport: bleService, dataStore: dataStore)
        self.messagePollingService = MessagePollingService(bleTransport: bleService, dataStore: dataStore)
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

            // Connect message polling for real-time updates
            await connectMessagePolling()
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

    // MARK: - Message Polling

    /// Connects the BLE response handler to the message polling service.
    /// Call this after device connection is established.
    func connectMessagePolling() async {
        guard let deviceID = connectedDevice?.id else { return }

        // Set the active device on the polling service
        await messagePollingService.setActiveDevice(deviceID)

        // Set the delegate for message events
        await messagePollingService.setDelegate(messageEventBroadcaster)

        // Connect BLE push notifications to the polling service
        await bleService.setResponseHandler { [weak self] data in
            guard let self else { return }
            Task {
                try? await self.messagePollingService.processPushData(data)
            }
        }

        // Perform initial sync of any waiting messages
        await messagePollingService.syncMessageQueue()
    }

    // MARK: - Navigation

    /// Navigates to the chat tab and opens a conversation with the specified contact
    func navigateToChat(with contact: ContactDTO) {
        pendingChatContact = contact
        selectedTab = 0
    }

    /// Clears the pending navigation after it's been handled
    func clearPendingNavigation() {
        pendingChatContact = nil
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
