import SwiftUI
import SwiftData
import UserNotifications
import PocketMeshKit

/// App-wide state management using Observable
@Observable
@MainActor
public final class AppState: AccessorySetupKitServiceDelegate {

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

    /// The AccessorySetupKit service for device discovery/pairing
    let accessorySetupKit = AccessorySetupKitService()

    /// Current connection state
    var connectionState: BLEConnectionState = .disconnected

    /// Connected device info (after successful connection)
    var connectedDevice: DeviceDTO?

    /// Last error encountered
    var lastError: String?

    /// Whether we're currently connecting to a device
    var isConnecting: Bool = false

    /// Whether BLE has operations in progress (for activity indicator animation)
    var isBLEBusy: Bool = false

    /// Current device battery level in millivolts (nil if not fetched)
    var deviceBatteryMillivolts: UInt16?

    /// Device ID to retry connection after failure
    var pendingReconnectDeviceID: UUID?

    /// Whether to show the connection failure alert
    var showingConnectionFailedAlert: Bool = false

    /// Message for connection failure alert
    var connectionFailedMessage: String?

    // MARK: - Contact Sync State

    /// Whether contacts are currently syncing (for UI overlay)
    var isContactsSyncing: Bool = false

    /// Contact sync progress (current, total)
    var contactsSyncProgress: (Int, Int)?

    // MARK: - Activity Tracking

    /// Counter for sync/settings operations (on-demand) - shows pill
    private var syncActivityCount: Int = 0

    /// Counter for message polling operations (event-driven) - shows pill
    private var pollingActivityCount: Int = 0

    /// Whether the syncing pill should be displayed
    /// Only true for on-demand (sync/settings) and event-driven (polling) operations
    var shouldShowSyncingPill: Bool {
        syncActivityCount > 0 || pollingActivityCount > 0
    }

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

    /// The settings service for device configuration
    let settingsService: SettingsService

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
        self.settingsService = SettingsService(bleTransport: bleService)

        // Set up BLE activity tracking for UI animation
        Task {
            await bleService.setSendActivityHandler { [weak self] isBusy in
                Task { @MainActor in
                    self?.isBLEBusy = isBusy
                }
            }
        }

        // Wire up notification service to message event broadcaster
        messageEventBroadcaster.notificationService = notificationService

        // Wire up message service for send confirmation handling
        messageEventBroadcaster.messageService = messageService

        // Set up message failure handler to notify UI
        Task {
            await messageService.setMessageFailedHandler { [weak self] messageID in
                guard let self else { return }
                await MainActor.run {
                    self.messageEventBroadcaster.handleMessageFailed(messageID: messageID)
                }
            }
        }

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

    /// Initialize Bluetooth services
    func initializeBLE() async {
        // Set up delegates
        bleStateRestoration.delegate = self
        accessorySetupKit.delegate = self

        // Pre-warm database to avoid lazy initialization freeze
        // Must complete before any database operations
        try? await dataStore.warmUp()

        // Activate AccessorySetupKit session FIRST (before any CBCentralManager usage)
        do {
            try await accessorySetupKit.activateSession()
        } catch {
            // Propagate error state for UI to display
            lastError = "Bluetooth setup failed. Please ensure Bluetooth is enabled."
            return  // Don't proceed with reconnection if ASK failed
        }

        // If we have a previously connected device, initialize BLE and reconnect
        // NOTE: BLEService.initialize() is safe here because device was already paired via ASK
        if let deviceID = bleStateRestoration.lastConnectedDeviceID {
            await initializeBLEForReconnection()
            await attemptReconnection(to: deviceID)
        }
    }

    /// Initialize BLE service for reconnection (called after ASK session is active)
    private func initializeBLEForReconnection() async {
        await bleService.initialize()

        // Set up disconnection handler
        await bleService.setDisconnectionHandler { [weak self] deviceID, error in
            Task { @MainActor in
                guard let self else { return }
                await self.bleStateRestoration.handleConnectionLoss(deviceID: deviceID, error: error)
            }
        }

        // Set up reconnection handler - initialize device after iOS auto-reconnect
        await bleService.setReconnectionHandler { [weak self] deviceID in
            Task { @MainActor in
                guard let self else { return }
                print("[AppState] iOS auto-reconnect completed for device: \(deviceID)")

                // Device may have rebooted - fail any pending messages first
                // They won't receive ACKs since device lost state
                do {
                    try await self.messageService.failAllPendingMessages()
                } catch {
                    print("[AppState] Failed to mark pending messages as failed after reconnect: \(error)")
                }

                // Initialize device to transition from .connected to .ready
                // This also restarts message polling and syncs contacts/channels
                await self.handleRestoredConnection(deviceID: deviceID)
            }
        }

        // Wait briefly for Bluetooth to be ready
        await bleService.waitForBluetoothReady()
    }

    /// Attempt reconnection to a previously paired device
    private func attemptReconnection(to deviceID: UUID) async {
        guard bleStateRestoration.shouldAttemptReconnection() else { return }

        isConnecting = true
        defer { isConnecting = false }

        do {
            connectionState = .connecting
            try await bleService.connect(to: deviceID)
            let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry()

            // Restore device info
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
            bleStateRestoration.resetReconnectionAttempts()
            persistConnectedDevice(connectedDevice!)

            // Update device in SwiftData (updates lastConnected timestamp)
            try await dataStore.saveDevice(connectedDevice!)

            // Start message polling
            await connectMessagePolling()

            // Fetch battery info
            await fetchDeviceBattery()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()

        } catch {
            connectionState = .disconnected
        }
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

        case .connecting:
            connectionState = actualState
        }
    }

    // MARK: - Device Pairing

    /// Shows AccessorySetupKit picker for new device pairing
    /// IMPORTANT: BLEService.initialize() is called AFTER showPicker() to avoid ASError 550
    /// WARNING: showPicker() causes CBCentralManager state cycling which disconnects existing peripherals
    func pairNewDevice() async throws {
        // 1. Store current connection info BEFORE showing picker (for logging)
        // Note: showPicker() will disconnect any existing peripheral due to CBCentralManager state cycling
        let previousDeviceID = connectedDevice?.id
        let hadPreviousConnection = connectionState == .ready

        // 2. Show ASK picker FIRST (before any CBCentralManager usage)
        // This triggers CBCentralManager state cycling: poweredOn → poweredOff → poweredOn
        let deviceID = try await accessorySetupKit.showPicker()

        // 3. Clear previous connection state if needed
        if hadPreviousConnection, let previousID = previousDeviceID, previousID != deviceID {
            // Previous device was disconnected during ASK picker state cycling
            connectedDevice = nil
            connectionState = .disconnected
        }

        // 4. Connect with retry pattern
        // - Don't use fixed delays - they're guessing at timing
        // - Use retry with exponential backoff - adapts to actual conditions
        // - Peripheral may need stabilization time after ASK bonding
        let (deviceInfo, selfInfo) = try await connectWithRetry(deviceID: deviceID, maxAttempts: 4)

        // 5. Update connection state
        connectionState = await bleService.connectionState

        // 6. Create DeviceDTO from device info
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

        // 7. Store and persist
        connectionState = .ready
        persistConnectedDevice(connectedDevice!)
        try await dataStore.saveDevice(connectedDevice!)
        bleStateRestoration.recordConnection(deviceID: deviceID)

        // 8. Start message polling
        await connectMessagePolling()

        // 9. Fetch battery info
        await fetchDeviceBattery()

        // 10. Sync contacts and channels
        await syncContactsFromDevice()
        await syncChannelsFromDevice()
    }

    /// Connects to a device with retry pattern and exponential backoff
    /// - Peripheral may need stabilization time after ASK bonding
    /// - "fence tx observer timed out" indicates link-layer supervision timeout
    /// - Retry pattern adapts to actual conditions rather than guessing at timing
    private func connectWithRetry(
        deviceID: UUID,
        maxAttempts: Int
    ) async throws -> (DeviceInfo, SelfInfo) {
        var lastError: Error = BLEError.connectionFailed("Unknown")

        for attempt in 1...maxAttempts {
            do {
                // Initialize BLE service
                await bleService.initialize()

                // Set up disconnection handler
                await bleService.setDisconnectionHandler { [weak self] deviceID, error in
                    Task { @MainActor in
                        guard let self else { return }
                        await self.bleStateRestoration.handleConnectionLoss(deviceID: deviceID, error: error)
                    }
                }

                // Set up reconnection handler - initialize device after iOS auto-reconnect
                await bleService.setReconnectionHandler { [weak self] deviceID in
                    Task { @MainActor in
                        guard let self else { return }
                        print("[AppState] iOS auto-reconnect completed for device: \(deviceID)")
                        do {
                            try await self.messageService.failAllPendingMessages()
                        } catch {
                            print("[AppState] Failed to mark pending messages as failed after reconnect: \(error)")
                        }
                        await self.handleRestoredConnection(deviceID: deviceID)
                    }
                }

                // Wait for Bluetooth to be ready
                await bleService.waitForBluetoothReady()

                // Attempt connection
                connectionState = .connecting
                try await bleService.connect(to: deviceID)

                // Verify connection is stable by attempting initialization
                // If connection dropped (supervision timeout), this will fail
                let result = try await bleService.initializeDeviceWithRetry()

                #if DEBUG
                if attempt > 1 {
                    print("[AppState] connectWithRetry: succeeded on attempt \(attempt)")
                }
                #endif

                return result

            } catch {
                lastError = error

                #if DEBUG
                print("[AppState] connectWithRetry: attempt \(attempt) failed - \(error.localizedDescription)")
                #endif

                // Clean up failed connection
                await bleService.disconnect()
                connectionState = .disconnected

                if attempt < maxAttempts {
                    // Exponential backoff with jitter
                    // Base delays: 300ms, 600ms, 1200ms
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay

                    #if DEBUG
                    print("[AppState] connectWithRetry: waiting \(Int((baseDelay + jitter) * 1000))ms before retry")
                    #endif

                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

        throw lastError
    }

    // MARK: - Connection

    /// Reconnect to a previously paired device by ID
    /// Validates ASK pairing, uses retry pattern, and handles stale entries gracefully
    func reconnectToDevice(id deviceID: UUID) async throws {
        isConnecting = true
        lastError = nil

        defer { isConnecting = false }

        // 1. Validate device is still registered with AccessorySetupKit
        // If user removed device from Settings > Accessories while app wasn't running,
        // we need to clean up our stale database entry
        if accessorySetupKit.isSessionActive {
            let isRegisteredWithASK = accessorySetupKit.pairedAccessories.contains {
                $0.bluetoothIdentifier == deviceID
            }

            if !isRegisteredWithASK {
                #if DEBUG
                print("[AppState] reconnectToDevice: device \(deviceID) not found in ASK pairedAccessories, removing stale entry")
                #endif

                // Clean up stale database entry
                await removeStaleDevice(id: deviceID)

                throw ReconnectionError.deviceNoLongerPaired
            }
        }

        // 2. Attempt connection with retry pattern
        do {
            let (deviceInfo, selfInfo) = try await reconnectWithRetry(deviceID: deviceID, maxAttempts: 4)

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

            // Fetch battery info
            await fetchDeviceBattery()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()

        } catch BLEError.deviceNotFound {
            // 3. Handle stale database entry - device no longer known to CoreBluetooth
            #if DEBUG
            print("[AppState] reconnectToDevice: device \(deviceID) not found by CoreBluetooth, removing stale entry")
            #endif

            await removeStaleDevice(id: deviceID)
            throw ReconnectionError.deviceNoLongerPaired

        } catch {
            lastError = error.localizedDescription
            connectionState = .disconnected
            await bleService.disconnect()
            throw error
        }
    }

    /// Initiates device reconnection without blocking the caller
    /// Shows error alert on failure with retry option
    func initiateReconnection(to deviceID: UUID) {
        Task {
            do {
                try await reconnectToDevice(id: deviceID)
            } catch ReconnectionError.deviceNoLongerPaired {
                connectionFailedMessage = "This device is no longer paired. Please pair it again using 'Scan for New Device'."
                showingConnectionFailedAlert = true
                pendingReconnectDeviceID = nil  // Can't retry - device removed
            } catch {
                connectionFailedMessage = error.localizedDescription
                pendingReconnectDeviceID = deviceID  // Store for retry
                showingConnectionFailedAlert = true
            }
        }
    }

    /// Retries the pending reconnection
    func retryPendingReconnection() {
        guard let deviceID = pendingReconnectDeviceID else { return }
        initiateReconnection(to: deviceID)
    }

    /// Reconnects to a device with retry pattern and exponential backoff
    /// Similar to connectWithRetry but optimized for reconnection scenarios
    private func reconnectWithRetry(
        deviceID: UUID,
        maxAttempts: Int
    ) async throws -> (DeviceInfo, SelfInfo) {
        var lastError: Error = BLEError.connectionFailed("Unknown")

        for attempt in 1...maxAttempts {
            do {
                // Ensure BLE is initialized
                await bleService.initialize()

                // Set up disconnection handler
                await bleService.setDisconnectionHandler { [weak self] deviceID, error in
                    Task { @MainActor in
                        guard let self else { return }
                        await self.bleStateRestoration.handleConnectionLoss(deviceID: deviceID, error: error)
                    }
                }

                // Set up reconnection handler - initialize device after iOS auto-reconnect
                await bleService.setReconnectionHandler { [weak self] deviceID in
                    Task { @MainActor in
                        guard let self else { return }
                        print("[AppState] iOS auto-reconnect completed for device: \(deviceID)")
                        do {
                            try await self.messageService.failAllPendingMessages()
                        } catch {
                            print("[AppState] Failed to mark pending messages as failed after reconnect: \(error)")
                        }
                        await self.handleRestoredConnection(deviceID: deviceID)
                    }
                }

                // Disconnect first to ensure clean state
                await bleService.disconnect()

                // Wait for Bluetooth to be ready
                await bleService.waitForBluetoothReady()

                // Attempt connection
                connectionState = .connecting
                try await bleService.connect(to: deviceID)

                // Verify connection is stable by attempting initialization
                let result = try await bleService.initializeDeviceWithRetry()

                #if DEBUG
                if attempt > 1 {
                    print("[AppState] reconnectWithRetry: succeeded on attempt \(attempt)")
                }
                #endif

                return result

            } catch BLEError.deviceNotFound {
                // Don't retry deviceNotFound - it won't resolve with retries
                throw BLEError.deviceNotFound

            } catch {
                lastError = error

                #if DEBUG
                print("[AppState] reconnectWithRetry: attempt \(attempt) failed - \(error.localizedDescription)")
                #endif

                // Clean up failed connection
                await bleService.disconnect()
                connectionState = .disconnected

                if attempt < maxAttempts {
                    // Exponential backoff with jitter
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay

                    #if DEBUG
                    print("[AppState] reconnectWithRetry: waiting \(Int((baseDelay + jitter) * 1000))ms before retry")
                    #endif

                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

        throw lastError
    }

    /// Removes a stale device entry from the database and clears related state
    private func removeStaleDevice(id deviceID: UUID) async {
        // Clear from state restoration
        bleStateRestoration.clearConnection(deviceID: deviceID)

        // Clear persisted device if it matches
        if let uuidString = UserDefaults.standard.string(forKey: lastDeviceIDKey),
           UUID(uuidString: uuidString) == deviceID {
            clearPersistedDevice()
        }

        // Remove from SwiftData
        try? await dataStore.deleteDevice(id: deviceID)
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
        deviceBatteryMillivolts = nil
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
        deviceBatteryMillivolts = nil
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

        // Set up polling activity handler for syncing pill
        await messagePollingService.setPollingActivityHandler { [weak self] isPolling in
            Task { @MainActor in
                guard let self else { return }
                if isPolling {
                    self.pollingActivityCount += 1
                } else {
                    self.pollingActivityCount -= 1
                }
            }
        }

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

        do {
            try await withSyncActivity {
                // Set up progress handler
                await contactService.setSyncProgressHandler { [weak self] current, total in
                    Task { @MainActor in
                        self?.contactsSyncProgress = (current, total)
                    }
                }

                _ = try await contactService.syncContacts(deviceID: deviceID)
            }
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
            try await withSyncActivity {
                _ = try await channelService.syncChannels(deviceID: deviceID)
            }
        } catch {
            // Silently ignore sync errors - channels can be synced manually
        }
    }

    // MARK: - Device Info Refresh

    /// Refreshes device info from the connected device after settings changes
    /// Call this after making settings changes to update the UI with the new values
    func refreshDeviceInfo() async {
        guard await bleService.connectionState == .ready else { return }
        guard let currentDevice = connectedDevice else { return }

        do {
            let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry(maxRetries: 1, initialDelay: 0.1)

            connectedDevice = DeviceDTO(
                from: Device(
                    id: currentDevice.id,
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
                    multiAcks: selfInfo.multiAcks > 0,
                    telemetryModeBase: selfInfo.telemetryModes & 0x03,
                    telemetryModeLoc: (selfInfo.telemetryModes >> 2) & 0x03,
                    telemetryModeEnv: (selfInfo.telemetryModes >> 4) & 0x03,
                    advertLocationPolicy: selfInfo.advertLocationPolicy.rawValue,
                    isActive: true
                )
            )

            persistConnectedDevice(connectedDevice!)
            try await dataStore.saveDevice(connectedDevice!)
        } catch {
            // Silently fail - device info will refresh on next sync
        }
    }

    // MARK: - Device Info Update

    /// Update connected device from verification results
    /// Call this after a verified settings change succeeds
    func updateDeviceInfo(_ deviceInfo: DeviceInfo, _ selfInfo: SelfInfo) {
        guard let currentDevice = connectedDevice else { return }

        connectedDevice = DeviceDTO(
            from: Device(
                id: currentDevice.id,
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
                multiAcks: selfInfo.multiAcks > 0,
                telemetryModeBase: selfInfo.telemetryModes & 0x03,
                telemetryModeLoc: (selfInfo.telemetryModes >> 2) & 0x03,
                telemetryModeEnv: (selfInfo.telemetryModes >> 4) & 0x03,
                advertLocationPolicy: selfInfo.advertLocationPolicy.rawValue,
                isActive: true
            )
        )

        persistConnectedDevice(connectedDevice!)
        Task {
            try? await dataStore.saveDevice(connectedDevice!)
        }
    }

    // MARK: - Battery Info

    /// Fetches current battery info from connected device
    func fetchDeviceBattery() async {
        guard connectionState == .ready else { return }

        do {
            let battery = try await settingsService.getBatteryAndStorage()
            deviceBatteryMillivolts = battery.batteryMillivolts
        } catch {
            // Silently fail - battery info is optional
            deviceBatteryMillivolts = nil
        }
    }

    // MARK: - Activity Tracking Methods

    /// Execute an operation while tracking it as sync activity (shows pill)
    /// Use for: settings changes, contact sync, channel sync, device initialization
    func withSyncActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        syncActivityCount += 1
        defer { syncActivityCount -= 1 }
        return try await operation()
    }

    /// Execute an operation while tracking it as polling activity (shows pill)
    /// Use for: message polling when device signals waiting messages
    func withPollingActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        pollingActivityCount += 1
        defer { pollingActivityCount -= 1 }
        return try await operation()
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

    /// Trigger device pairing flow (called from UI)
    func startDeviceScan() {
        Task {
            do {
                try await pairNewDevice()
                completeOnboarding()
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error to show
            } catch AccessorySetupKitError.pickerRestricted {
                lastError = "Cannot show device picker. Please check Bluetooth permissions."
            } catch {
                lastError = error.localizedDescription
            }
        }
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

// MARK: - Reconnection Errors

/// Errors specific to device reconnection
enum ReconnectionError: LocalizedError {
    /// Device was removed from Settings > Accessories or is no longer paired
    case deviceNoLongerPaired

    var errorDescription: String? {
        switch self {
        case .deviceNoLongerPaired:
            return "This device is no longer paired. Please pair it again using 'Scan for New Device'."
        }
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
        connectedDevice = nil
        deviceBatteryMillivolts = nil

        // Atomically stop ACK checking and fail all pending messages
        do {
            try await messageService.stopAndFailAllPending()
        } catch {
            print("[AppState] Failed to mark pending messages as failed: \(error)")
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
                // Device may have rebooted - use more patient retry settings
                // Allows up to ~12 seconds for device to finish booting
                let (deviceInfo, selfInfo) = try await bleService.initializeDeviceWithRetry(
                    maxRetries: 5,
                    initialDelay: 1.0
                )

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

                // Fetch battery info
                await fetchDeviceBattery()

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

            // Fetch battery info
            await fetchDeviceBattery()

            // Auto-sync contacts then channels from device
            await syncContactsFromDevice()
            await syncChannelsFromDevice()

        } catch {
            connectionState = .disconnected
        }
    }
}

// MARK: - AccessorySetupKitServiceDelegate

extension AppState {
    public func accessorySetupKitService(_ service: AccessorySetupKitService, didRemoveAccessoryWithID bluetoothID: UUID) {
        // Called when accessory is removed from Settings > Accessories

        // Clear stored connection state if this was our device
        if connectedDevice?.id == bluetoothID {
            Task {
                await bleService.disconnect()
                connectedDevice = nil
                connectionState = .disconnected
                deviceBatteryMillivolts = nil
            }
        }

        // Clear from state restoration
        bleStateRestoration.clearConnection(deviceID: bluetoothID)

        // Remove from SwiftData
        Task {
            try? await dataStore.deleteDevice(id: bluetoothID)
        }
    }
}
