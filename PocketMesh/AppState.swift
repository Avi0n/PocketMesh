import SwiftUI
import SwiftData
import UserNotifications
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

    /// The BLE state restoration service
    let bleStateRestoration = BLEStateRestoration()

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

    // MARK: - Contact Sync State

    /// Whether contacts are currently syncing (for UI overlay)
    var isContactsSyncing: Bool = false

    /// Contact sync progress (current, total)
    var contactsSyncProgress: (Int, Int)?

    // MARK: - Device Pairing State

    /// Device selected for pairing (set when proceeding from scan to pair)
    var selectedDeviceForPairing: DiscoveredDevice?

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

    /// The channel service for managing channels
    let channelService: ChannelService

    /// The message event broadcaster for UI updates
    let messageEventBroadcaster = MessageEventBroadcaster()

    /// The notification service for local notifications
    let notificationService = NotificationService()

    // MARK: - Navigation State

    /// Currently selected tab index
    var selectedTab: Int = 0

    /// Contact to navigate to in chat (for cross-tab navigation)
    var pendingChatContact: ContactDTO?

    // MARK: - Device Persistence Keys

    private let lastDeviceNameKey = "lastConnectedDeviceName"
    private let lastDeviceIDKey = "lastConnectedDeviceID"

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
        self.channelService = ChannelService(bleTransport: bleService, dataStore: dataStore)

        // Wire up notification service to message event broadcaster
        messageEventBroadcaster.notificationService = notificationService

        // Wire up message service for send confirmation handling
        messageEventBroadcaster.messageService = messageService

        // Set up channel name lookup for notifications
        messageEventBroadcaster.channelNameLookup = { [dataStore] deviceID, channelIndex in
            let channel = try? await dataStore.fetchChannel(deviceID: deviceID, index: channelIndex)
            return channel?.name
        }

        // Set up quick reply handler
        // The callback is @MainActor @Sendable, so it executes on MainActor.
        // We need to capture self to access bleService for connection state.
        notificationService.onQuickReply = { [weak self] contactID, text in
            guard let self else { return }

            // Look up the contact
            guard let contact = try? await self.dataStore.fetchContact(id: contactID) else { return }

            // Check if BLE is connected and try to send
            let connectionState = await self.bleService.connectionState
            if connectionState == .ready {
                do {
                    _ = try await self.messageService.sendDirectMessage(text: text, to: contact)
                    return  // Success - exit early
                } catch {
                    // Send failed - fall through to error handling
                }
            }

            // Not connected or send failed - save draft and notify user
            self.notificationService.saveDraft(for: contactID, text: text)
            await self.notificationService.postQuickReplyFailedNotification(
                contactName: contact.name,
                contactID: contactID
            )
        }

        // Set up notification tap handler
        // The callback is @MainActor @Sendable, so it executes on MainActor.
        // We can access self directly and call navigateToChat without MainActor.run.
        notificationService.onNotificationTapped = { [weak self] contactID in
            guard let self else { return }

            // Look up the contact
            guard let contact = try? await self.dataStore.fetchContact(id: contactID) else { return }

            // Navigate to chat - we're already on MainActor, so just call directly
            self.navigateToChat(with: contact)
        }

        // Set up mark as read handler
        // The callback is @MainActor @Sendable, so it executes on MainActor.
        // We can access self directly since we're on MainActor.
        notificationService.onMarkAsRead = { [weak self] contactID, messageID in
            guard let self else { return }
            do {
                // Mark the specific message as read
                // Note: await hops to DataStore actor, then returns to MainActor
                try await self.dataStore.markMessageAsRead(id: messageID)
                // Clear unread count for the contact
                try await self.dataStore.clearUnreadCount(contactID: contactID)
            } catch {
                // Silently ignore - mark as read is not critical
            }
        }

        // Set up notification service as the notification center delegate
        UNUserNotificationCenter.current().delegate = notificationService

        // Initialize notification service
        Task {
            await notificationService.setup()
        }
    }

    // MARK: - BLE Initialization

    /// Called when app finishes launching to initialize BLE
    func initializeBLE() async {
        // Set up delegate
        bleStateRestoration.delegate = self

        // Initialize the central manager - this triggers state restoration
        await bleService.initialize()

        // Set up disconnection handler
        await bleService.setDisconnectionHandler { [weak self] deviceID, error in
            Task { @MainActor in
                guard let self else { return }
                await self.bleStateRestoration.handleConnectionLoss(deviceID: deviceID, error: error)
            }
        }

        // Wait briefly for Bluetooth to be ready
        await bleService.waitForBluetoothReady()

        // Pre-warm database to avoid lazy initialization freeze
        // Must complete before any database operations
        try? await dataStore.warmUp()

        // Check if we need to reconnect
        await attemptAutoReconnect()
    }

    // MARK: - App Lifecycle

    /// Called when app enters background
    func handleEnterBackground() {
        bleStateRestoration.appDidEnterBackground()
    }

    /// Called when app returns to foreground
    func handleReturnToForeground() async {
        bleStateRestoration.appWillEnterForeground()

        // Sync connection state with actual BLE state
        await syncConnectionState()

        // Force immediate check for expired ACKs when returning from background
        // This catches any timeouts that occurred while the app was suspended
        if connectionState == .ready {
            try? await messageService.checkExpiredAcks()
        }
    }

    /// Syncs UI connection state with actual BLE service state
    func syncConnectionState() async {
        let actualState = await bleService.connectionState
        let actualDeviceID = await bleService.connectedDeviceID

        // Update UI state to match reality
        switch actualState {
        case .disconnected:
            if connectionState != .disconnected {
                connectionState = .disconnected
                connectedDevice = nil
            }

        case .connected, .ready:
            connectionState = actualState

            // If we have a connection but no device info, complete initialization
            if connectedDevice == nil && actualDeviceID != nil {
                await handleRestoredConnection(deviceID: actualDeviceID)
            }

        case .scanning, .connecting:
            connectionState = actualState
        }
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
            let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry()

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

            // Record connection for state restoration
            bleStateRestoration.recordConnection(deviceID: device.id)
            persistConnectedDevice(connectedDevice!)

            // Save device to SwiftData for reconnection list
            try await dataStore.saveDevice(connectedDevice!)

            // Connect message polling for real-time updates
            await connectMessagePolling()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()
        } catch {
            lastError = error.localizedDescription
            connectionState = .disconnected
            isConnecting = false
            throw error
        }
    }

    /// Reconnect to a previously paired device by ID
    func reconnectToDevice(id deviceID: UUID) async throws {
        isConnecting = true
        lastError = nil

        defer { isConnecting = false }

        do {
            // Ensure BLE is initialized
            await bleService.initialize()

            // Connect to the device
            try await bleService.connect(to: deviceID)

            // Initialize device and get info
            let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry()

            // Update connection state
            connectionState = await bleService.connectionState

            // Create device DTO from the info
            connectedDevice = DeviceDTO(
                from: Device(
                    id: deviceID,
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

            // Record connection for state restoration
            bleStateRestoration.recordConnection(deviceID: deviceID)
            persistConnectedDevice(connectedDevice!)

            // Update device in SwiftData (updates lastConnected timestamp)
            try await dataStore.saveDevice(connectedDevice!)

            // Connect message polling for real-time updates
            await connectMessagePolling()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()
        } catch {
            lastError = error.localizedDescription
            connectionState = .disconnected
            throw error
        }
    }

    /// Disconnect from the current device
    func disconnect() async {
        // Stop periodic ACK checking
        await messageService.stopAckExpiryChecking()

        bleStateRestoration.recordDisconnection(intentional: true)
        clearPersistedDevice()
        await bleService.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
    }

    /// Disconnects any existing connection and prepares for new device scan
    func disconnectForNewConnection() async {
        // Stop periodic ACK checking
        await messageService.stopAckExpiryChecking()

        // Check if there's an existing BLE connection (even if UI doesn't know)
        let actualState = await bleService.connectionState

        if actualState == .connected || actualState == .ready {
            // Force disconnect
            await bleService.disconnect()
        }

        // Clear local state
        bleStateRestoration.recordDisconnection(intentional: true)
        clearPersistedDevice()
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

        // Start periodic ACK expiry checking (every 5 seconds)
        await messageService.startAckExpiryChecking(interval: 5.0)

        // Perform initial sync of any waiting messages
        await messagePollingService.syncMessageQueue()
    }

    // MARK: - Contact Sync

    /// Syncs contacts from the connected device
    /// Updates isContactsSyncing and contactsSyncProgress for UI
    func syncContactsFromDevice() async {
        guard let deviceID = connectedDevice?.id else { return }

        isContactsSyncing = true
        contactsSyncProgress = nil

        // Set up progress handler
        await contactService.setSyncProgressHandler { [weak self] current, total in
            Task { @MainActor in
                self?.contactsSyncProgress = (current, total)
            }
        }

        do {
            _ = try await contactService.syncContacts(deviceID: deviceID)
        } catch {
            // Silently ignore sync errors - contacts can be synced manually
        }

        contactsSyncProgress = nil
        isContactsSyncing = false
    }

    // MARK: - Channel Sync

    /// Syncs channels from the connected device
    /// Called after contact sync to ensure contact names are available
    func syncChannelsFromDevice() async {
        guard let deviceID = connectedDevice?.id else { return }

        do {
            _ = try await channelService.syncChannels(deviceID: deviceID)
        } catch {
            // Silently ignore sync errors - channels can be synced manually
        }
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

    /// Navigate directly to device scan (skip welcome/permissions)
    /// Used when user already completed onboarding but wants to connect a new device
    func startDeviceScan() {
        onboardingStep = .deviceScan
        hasCompletedOnboarding = false
    }

    // MARK: - Device Persistence

    /// Persists connected device info for restoration
    private func persistConnectedDevice(_ device: DeviceDTO) {
        UserDefaults.standard.set(device.nodeName, forKey: lastDeviceNameKey)
        UserDefaults.standard.set(device.id.uuidString, forKey: lastDeviceIDKey)
    }

    /// Clears persisted device info
    private func clearPersistedDevice() {
        UserDefaults.standard.removeObject(forKey: lastDeviceNameKey)
        UserDefaults.standard.removeObject(forKey: lastDeviceIDKey)
    }

    /// Gets the last connected device ID
    func getLastConnectedDeviceID() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: lastDeviceIDKey) else { return nil }
        return UUID(uuidString: uuidString)
    }
}

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case deviceScan

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

// MARK: - BLEStateRestorationDelegate

extension AppState: BLEStateRestorationDelegate {
    public func bleStateRestoration(_ restoration: BLEStateRestoration, didLoseConnection deviceID: UUID, error: Error?) async {
        // Handle unexpected disconnection
        connectionState = .disconnected

        // Get device name for notification (check current device first, then UserDefaults)
        let deviceName = connectedDevice?.nodeName ?? UserDefaults.standard.string(forKey: lastDeviceNameKey)
        connectedDevice = nil

        // Post notification if we have device name
        if let deviceName {
            await notificationService.postConnectionLostNotification(deviceName: deviceName)
        }

        // Wait before attempting reconnection to avoid CoreBluetooth state machine issues
        try? await Task.sleep(for: .milliseconds(100))

        // Attempt auto-reconnect after the delay
        await attemptAutoReconnect()
    }

    /// Handles a connection restored by iOS state restoration
    private func handleRestoredConnection(deviceID: UUID?) async {
        guard let deviceID else { return }

        // Don't initialize if another connection attempt is in progress
        // This prevents race conditions between connect() and state restoration
        guard !isConnecting else { return }

        // Complete device initialization if needed
        if await bleService.connectionState == .connected {
            do {
                let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry()

                connectedDevice = DeviceDTO(
                    from: Device(
                        id: deviceID,
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

                connectionState = .ready
                persistConnectedDevice(connectedDevice!)

                // Update device in SwiftData (updates lastConnected timestamp)
                try await dataStore.saveDevice(connectedDevice!)

                await connectMessagePolling()

                // Auto-sync contacts then channels from device
                await syncContactsFromDevice()
                await syncChannelsFromDevice()

            } catch {
                // Initialization failed - disconnect and reset to clean state
                // This handles the "connected but not usable" scenario
                await bleService.disconnect()
                connectionState = .disconnected
                connectedDevice = nil
            }
        }
    }

    /// Attempts to reconnect to the last connected device
    func attemptAutoReconnect() async {
        // Don't attempt if another connection is already in progress
        guard !isConnecting else { return }

        // Ensure BLE is initialized
        await bleService.initialize()

        // Check if already connected (iOS restored connection)
        if await bleService.connectionState == .connected {
            await handleRestoredConnection(deviceID: await bleService.connectedDeviceID)
            return
        }

        // Check if we have a last device to reconnect to
        guard let lastDeviceID = bleStateRestoration.lastConnectedDeviceID else { return }
        guard bleStateRestoration.shouldAttemptReconnection() else { return }

        // Attempt reconnection
        isConnecting = true
        defer { isConnecting = false }

        do {
            connectionState = .connecting

            try await bleService.connect(to: lastDeviceID)
            let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry()

            // Restore device info
            connectedDevice = DeviceDTO(
                from: Device(
                    id: lastDeviceID,
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

            connectionState = .ready
            bleStateRestoration.resetReconnectionAttempts()

            // Update device in SwiftData (updates lastConnected timestamp)
            try await dataStore.saveDevice(connectedDevice!)

            // Start message polling
            await connectMessagePolling()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()

        } catch {
            connectionState = .disconnected

            // Show notification for failed reconnection
            if let deviceName = UserDefaults.standard.string(forKey: lastDeviceNameKey) {
                await notificationService.postConnectionLostNotification(deviceName: deviceName)
            }
        }
    }
}
