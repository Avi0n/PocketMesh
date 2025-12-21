import SwiftUI
import SwiftData
import UserNotifications
import PocketMeshServices
import MeshCore
import OSLog

/// Simplified app-wide state management.
/// Composes ConnectionManager for connection lifecycle.
/// Handles only UI state, navigation, and notification wiring.
@Observable
@MainActor
public final class AppState {

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.pocketmesh", category: "AppState")

    // MARK: - Connection (via ConnectionManager)

    /// The connection manager for device lifecycle
    public let connectionManager: ConnectionManager

    // Convenience accessors
    public var connectionState: PocketMeshServices.ConnectionState { connectionManager.connectionState }
    public var connectedDevice: DeviceDTO? { connectionManager.connectedDevice }
    public var services: ServiceContainer? { connectionManager.services }

    // MARK: - UI State for Connection

    /// Whether to show connection failure alert
    var showingConnectionFailedAlert = false

    /// Message for connection failure alert
    var connectionFailedMessage: String?

    /// Device ID pending retry
    var pendingReconnectDeviceID: UUID?

    /// Current device battery level in millivolts (nil if not fetched)
    var deviceBatteryMillivolts: UInt16?

    // MARK: - Onboarding State

    /// Whether onboarding is complete
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    /// Current onboarding step
    var onboardingStep: OnboardingStep = .welcome

    // MARK: - Navigation State

    /// Selected tab index
    var selectedTab: Int = 0

    /// Contact to navigate to
    var pendingChatContact: ContactDTO?

    /// Room session to navigate to
    var pendingRoomSession: RemoteNodeSessionDTO?

    /// Whether to navigate to Discovery
    var pendingDiscoveryNavigation = false

    // MARK: - UI Coordination

    /// Message event broadcaster for UI updates
    let messageEventBroadcaster = MessageEventBroadcaster()

    // MARK: - Activity Tracking

    /// Counter for sync/settings operations (on-demand) - shows pill
    private var syncActivityCount: Int = 0

    /// Task for initial sync, tracked for cancellation on disconnect
    private var initialSyncTask: Task<Void, Never>?

    /// Whether the syncing pill should be displayed
    /// Only true for on-demand operations (contact sync, channel sync, settings changes)
    var shouldShowSyncingPill: Bool {
        syncActivityCount > 0
    }

    // MARK: - Contact Discovery Deduplication

    /// Recently notified contact public keys (prevents duplicate notifications)
    private var recentlyNotifiedContactKeys: Set<Data> = []

    /// Device ID pending sync (for debouncing rapid ADVERT pushes)
    private var pendingSyncDeviceID: UUID?

    /// Task for debounced sync (cancelled if new ADVERT arrives within debounce window)
    private var syncDebounceTask: Task<Void, Never>?

    // MARK: - Derived State

    /// Whether connecting
    var isConnecting: Bool { connectionState == .connecting }

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        self.connectionManager = ConnectionManager(modelContainer: modelContainer)

        // Set up notification handlers
        setupNotificationHandlers()
    }

    // MARK: - Lifecycle

    /// Initialize on app launch
    func initialize() async {
        // Set up notification center delegate
        if let notificationService = services?.notificationService {
            UNUserNotificationCenter.current().delegate = notificationService
            await notificationService.setup()
        }

        await connectionManager.activate()

        // Wire services to UI coordination when connected
        await wireServicesIfConnected()
    }

    /// Wire services to message event broadcaster
    private func wireServicesIfConnected() async {
        guard let services else { return }

        // Wire notification service to message event broadcaster
        messageEventBroadcaster.notificationService = services.notificationService

        // Wire message service for send confirmation handling
        messageEventBroadcaster.messageService = services.messageService

        // Wire remote node service for login result handling
        messageEventBroadcaster.remoteNodeService = services.remoteNodeService
        messageEventBroadcaster.dataStore = services.dataStore

        // Wire room server service for room message handling
        messageEventBroadcaster.roomServerService = services.roomServerService

        // Wire binary protocol and repeater admin services
        messageEventBroadcaster.binaryProtocolService = services.binaryProtocolService
        messageEventBroadcaster.repeaterAdminService = services.repeaterAdminService

        // Wire up message polling handlers for incoming messages
        await wireMessagePollingHandlers(services: services)

        // Wire up retry status events from MessageService
        await services.messageService.setRetryStatusHandler { [weak self] messageID, attempt, maxAttempts in
            await MainActor.run {
                self?.messageEventBroadcaster.handleMessageRetrying(
                    messageID: messageID,
                    attempt: attempt,
                    maxAttempts: maxAttempts
                )
            }
        }

        // Wire up routing change events from MessageService
        await services.messageService.setRoutingChangedHandler { [weak self] contactID, isFlood in
            await MainActor.run {
                self?.messageEventBroadcaster.handleRoutingChanged(
                    contactID: contactID,
                    isFlood: isFlood
                )
            }
        }

        // Wire up message failure handler
        await services.messageService.setMessageFailedHandler { [weak self] messageID in
            await MainActor.run {
                self?.messageEventBroadcaster.handleMessageFailed(messageID: messageID)
            }
        }

        // Set up channel name lookup for notifications
        messageEventBroadcaster.channelNameLookup = { [dataStore = services.dataStore] deviceID, channelIndex in
            let channel = try? await dataStore.fetchChannel(deviceID: deviceID, index: channelIndex)
            return channel?.name
        }

        // Configure badge count callback
        services.notificationService.getBadgeCount = { [dataStore = services.dataStore] in
            do {
                return try await dataStore.getTotalUnreadCounts()
            } catch {
                return (contacts: 0, channels: 0)
            }
        }

        // Configure notification interaction handlers
        configureNotificationHandlers()

        // Wire up contact discovery handlers from AdvertisementService
        await wireContactDiscoveryHandlers(services: services)
    }

    /// Triggers initial sync of contacts and channels from the device.
    /// Uses withSyncActivity to show the syncing pill during operation.
    func triggerInitialSync() {
        guard let services, let deviceID = connectedDevice?.id else { return }

        // Cancel any existing sync
        initialSyncTask?.cancel()

        initialSyncTask = Task {
            await withSyncActivity {
                await services.performInitialSync(deviceID: deviceID)
            }

            // Trigger UI refresh after sync completes
            messageEventBroadcaster.contactsRefreshTrigger += 1
            messageEventBroadcaster.conversationRefreshTrigger += 1
        }
    }

    /// Wire up advertisement service handlers for contact discovery
    private func wireContactDiscoveryHandlers(services: ServiceContainer) async {
        guard let deviceID = connectedDevice?.id else { return }

        // Wire up new contact notification events from AdvertisementService (manual-add mode)
        await services.advertisementService.setNewContactDiscoveredHandler { [weak self] contactName, contactID in
            guard let self else { return }

            // Check deduplication - fetch contact to get public key
            if let contact = try? await services.dataStore.fetchContact(id: contactID) {
                let shouldNotify = await MainActor.run {
                    if self.recentlyNotifiedContactKeys.contains(contact.publicKey) {
                        return false // Already notified
                    }
                    self.recentlyNotifiedContactKeys.insert(contact.publicKey)
                    return true
                }
                guard shouldNotify else { return }
            }

            await services.notificationService.postNewContactNotification(
                contactName: contactName,
                contactID: contactID
            )

            // Schedule deduplication cache cleanup
            await MainActor.run {
                self.scheduleDeduplicationCleanup()
            }
        }

        // Wire up contact sync requests from AdvertisementService (auto-add mode)
        // Debounced: waits 500ms to coalesce rapid discoveries before syncing
        await services.advertisementService.setContactSyncRequestHandler { [weak self] _ in
            guard let self else { return }

            await MainActor.run {
                // Cancel any pending sync request (coalesce rapid discoveries)
                self.syncDebounceTask?.cancel()
                self.pendingSyncDeviceID = deviceID

                // Debounce: wait 500ms before syncing
                self.syncDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, let syncDeviceID = self.pendingSyncDeviceID else { return }
                    self.pendingSyncDeviceID = nil

                    await self.performDebouncedContactSync(deviceID: syncDeviceID)
                }
            }
        }
    }

    /// Perform contact sync with deduplication for notifications
    private func performDebouncedContactSync(deviceID: UUID) async {
        guard let services else { return }

        do {
            // Fetch existing contacts before sync
            let existingContacts = try await services.dataStore.fetchContacts(deviceID: deviceID)
            let existingKeys = Set(existingContacts.map(\.publicKey))

            // Sync contacts from device
            _ = try await services.contactService.syncContacts(deviceID: deviceID)

            // Fetch updated contacts
            let updatedContacts = try await services.dataStore.fetchContacts(deviceID: deviceID)

            // Find new contacts (not in existing set and not recently notified)
            let newContacts = updatedContacts.filter {
                !existingKeys.contains($0.publicKey) && !recentlyNotifiedContactKeys.contains($0.publicKey)
            }

            // Notify UI to refresh
            messageEventBroadcaster.handleContactsUpdated()

            // Post notification for each new contact and track to prevent duplicates
            for contact in newContacts {
                recentlyNotifiedContactKeys.insert(contact.publicKey)
                await services.notificationService.postNewContactNotification(
                    contactName: contact.displayName,
                    contactID: contact.id
                )
            }

            // Schedule deduplication cache cleanup
            scheduleDeduplicationCleanup()
        } catch {
            logger.warning("Auto-sync after ADVERT failed: \(error.localizedDescription)")
        }
    }

    /// Schedule cleanup of deduplication cache
    private func scheduleDeduplicationCleanup() {
        // Clear deduplication cache after 30 seconds (limit to 50 entries max)
        if recentlyNotifiedContactKeys.count > 50 {
            recentlyNotifiedContactKeys.removeAll()
        } else {
            Task {
                try? await Task.sleep(for: .seconds(30))
                recentlyNotifiedContactKeys.removeAll()
            }
        }
    }

    // MARK: - Message Polling Handlers

    /// Wire up MessagePollingService handlers for incoming messages
    private func wireMessagePollingHandlers(services: ServiceContainer) async {
        guard let deviceID = connectedDevice?.id else {
            logger.warning("Cannot wire message handlers: no connected device")
            return
        }

        // Contact message handler (direct messages)
        await services.messagePollingService.setContactMessageHandler { [weak self] message, contact in
            guard let self else { return }

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)
            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: contact?.id,
                channelIndex: nil,
                text: message.text,
                timestamp: timestamp,
                createdAt: Date(),
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: message.pathLength,
                snr: message.snr,
                senderKeyPrefix: message.senderPublicKeyPrefix,
                senderNodeName: nil,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0
            )

            do {
                try await withRetry {
                    try await services.dataStore.saveMessage(messageDTO)
                }

                // Update contact's last message date and unread count
                if let contactID = contact?.id {
                    try await services.dataStore.updateContactLastMessage(contactID: contactID, date: Date())
                    try await services.dataStore.incrementUnreadCount(contactID: contactID)
                }

                // Post notification and update UI (only for known contacts)
                if let contactID = contact?.id {
                    await services.notificationService.postDirectMessageNotification(
                        from: contact?.displayName ?? "Unknown",
                        contactID: contactID,
                        messageText: message.text,
                        messageID: messageDTO.id
                    )
                }
                await services.notificationService.updateBadgeCount()

                await MainActor.run {
                    self.messageEventBroadcaster.conversationRefreshTrigger += 1
                }
            } catch {
                self.logger.error("Contact message lost after retry: \(error)")
            }
        }

        // Channel message handler
        await services.messagePollingService.setChannelMessageHandler { [weak self] message, channel in
            guard let self else { return }

            // Parse "NodeName: text" format for sender name
            let (senderNodeName, messageText) = Self.parseChannelMessage(message.text)

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)
            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: nil,
                channelIndex: message.channelIndex,
                text: messageText,
                timestamp: timestamp,
                createdAt: Date(),
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: message.pathLength,
                snr: message.snr,
                senderKeyPrefix: nil,
                senderNodeName: senderNodeName,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0
            )

            do {
                try await withRetry {
                    try await services.dataStore.saveMessage(messageDTO)
                }

                // Update channel's last message date and unread count
                if let channelID = channel?.id {
                    try await services.dataStore.updateChannelLastMessage(channelID: channelID, date: Date())
                    try await services.dataStore.incrementChannelUnreadCount(channelID: channelID)
                }

                // Post notification and update UI
                await services.notificationService.postChannelMessageNotification(
                    channelName: channel?.name ?? "Channel \(message.channelIndex)",
                    channelIndex: message.channelIndex,
                    deviceID: deviceID,
                    senderName: senderNodeName,
                    messageText: messageText,
                    messageID: messageDTO.id
                )
                await services.notificationService.updateBadgeCount()

                await MainActor.run {
                    self.messageEventBroadcaster.conversationRefreshTrigger += 1
                }
            } catch {
                self.logger.error("Channel message lost after retry: \(error)")
            }
        }

        // Signed message handler (room server messages)
        await services.messagePollingService.setSignedMessageHandler { [weak self] message, _ in
            guard let self else { return }

            // For signed room messages, the signature contains the 4-byte author key prefix
            guard let authorPrefix = message.signature?.prefix(4), authorPrefix.count == 4 else {
                self.logger.warning("Dropping signed message: missing or invalid author prefix")
                return
            }

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            do {
                try await services.roomServerService.handleIncomingMessage(
                    senderPublicKeyPrefix: message.senderPublicKeyPrefix,
                    timestamp: timestamp,
                    authorPrefix: Data(authorPrefix),
                    text: message.text
                )
            } catch {
                self.logger.error("Failed to handle room message: \(error)")
            }
        }

        // CLI message handler (repeater admin responses)
        await services.messagePollingService.setCLIMessageHandler { [weak self] message, contact in
            guard let self else { return }

            // Forward CLI response to the broadcaster for routing to RepeaterSettingsViewModel
            if let contact {
                await MainActor.run {
                    Task {
                        await self.messageEventBroadcaster.handleCLIResponse(message, fromContact: contact)
                    }
                }
            } else {
                self.logger.warning("Dropping CLI response: no contact found for sender")
            }
        }

        // ACK handler not needed - MessageService handles ACKs internally
    }

    /// Parse channel message format "NodeName: text" into components
    private nonisolated static func parseChannelMessage(_ text: String) -> (senderNodeName: String?, messageText: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        if parts.count > 1 {
            let senderName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let messageText = String(parts[1]).trimmingCharacters(in: .whitespaces)
            return (senderName, messageText)
        }
        return (nil, text)
    }

    // MARK: - Device Actions

    /// Start device scan/pairing
    func startDeviceScan() {
        Task {
            do {
                try await connectionManager.pairNewDevice()
                hasCompletedOnboarding = true
                await wireServicesIfConnected()
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error
            } catch {
                connectionFailedMessage = error.localizedDescription
                showingConnectionFailedAlert = true
            }
        }
    }

    /// Disconnect from device
    func disconnect() async {
        // Cancel any in-progress sync
        initialSyncTask?.cancel()
        initialSyncTask = nil

        await connectionManager.disconnect()
    }

    /// Fetch device battery level
    func fetchDeviceBattery() async {
        guard connectionState == .ready else { return }

        do {
            let battery = try await services?.settingsService.getBattery()
            deviceBatteryMillivolts = battery.map { UInt16(clamping: $0.level) }
        } catch {
            // Silently fail - battery info is optional
            deviceBatteryMillivolts = nil
        }
    }

    // MARK: - App Lifecycle

    /// Called when app enters background
    func handleEnterBackground() {
        // Nothing needed - ConnectionManager handles persistence
    }

    /// Called when app returns to foreground
    func handleReturnToForeground() async {
        // Update badge count from database
        await services?.notificationService.updateBadgeCount()

        // Check for expired ACKs
        if connectionState == .ready {
            try? await services?.messageService.checkExpiredAcks()
        }
    }

    // MARK: - Navigation

    func navigateToChat(with contact: ContactDTO) {
        pendingChatContact = contact
        selectedTab = 0
    }

    func navigateToRoom(with session: RemoteNodeSessionDTO) {
        pendingRoomSession = session
        selectedTab = 0
    }

    func navigateToDiscovery() {
        pendingDiscoveryNavigation = true
        selectedTab = 1
    }

    func navigateToContacts() {
        selectedTab = 1
    }

    func clearPendingNavigation() {
        pendingChatContact = nil
    }

    func clearPendingRoomNavigation() {
        pendingRoomSession = nil
    }

    func clearPendingDiscoveryNavigation() {
        pendingDiscoveryNavigation = false
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        onboardingStep = .welcome
    }

    // MARK: - Activity Tracking Methods

    /// Execute an operation while tracking it as sync activity (shows pill)
    /// Use for: settings changes, contact sync, channel sync, device initialization
    func withSyncActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        syncActivityCount += 1
        defer { syncActivityCount -= 1 }
        return try await operation()
    }

    // MARK: - Notification Handlers

    private func setupNotificationHandlers() {
        // Handlers will be set up when services become available after connection
        // This is called during init before connection, so we defer actual setup
    }

    /// Configure notification handlers once services are available
    func configureNotificationHandlers() {
        guard let services else { return }

        // Notification tap handler
        services.notificationService.onNotificationTapped = { [weak self] contactID in
            guard let self else { return }

            guard let contact = try? await services.dataStore.fetchContact(id: contactID) else { return }
            self.navigateToChat(with: contact)
        }

        // New contact notification tap
        services.notificationService.onNewContactNotificationTapped = { [weak self] _ in
            guard let self else { return }

            if self.connectedDevice?.manualAddContacts == true {
                self.navigateToDiscovery()
            } else {
                self.navigateToContacts()
            }
        }

        // Quick reply handler
        services.notificationService.onQuickReply = { [weak self] contactID, text in
            guard let self else { return }

            guard let contact = try? await services.dataStore.fetchContact(id: contactID) else { return }

            if self.connectionState == .ready {
                do {
                    _ = try await services.messageService.sendDirectMessage(text: text, to: contact)
                    return
                } catch {
                    // Fall through to draft handling
                }
            }

            services.notificationService.saveDraft(for: contactID, text: text)
            await services.notificationService.postQuickReplyFailedNotification(
                contactName: contact.displayName,
                contactID: contactID
            )
        }

        // Mark as read handler
        services.notificationService.onMarkAsRead = { [weak self] contactID, messageID in
            guard let self else { return }
            do {
                try await services.dataStore.markMessageAsRead(id: messageID)
                try await services.dataStore.clearUnreadCount(contactID: contactID)
                services.notificationService.removeDeliveredNotification(messageID: messageID)
                await services.notificationService.updateBadgeCount()
                self.messageEventBroadcaster.conversationRefreshTrigger += 1
            } catch {
                // Silently ignore
            }
        }

        // Channel mark as read handler
        services.notificationService.onChannelMarkAsRead = { [weak self] deviceID, channelIndex, messageID in
            guard let self else { return }
            do {
                try await services.dataStore.markMessageAsRead(id: messageID)
                try await services.dataStore.clearChannelUnreadCount(deviceID: deviceID, index: channelIndex)
                services.notificationService.removeDeliveredNotification(messageID: messageID)
                await services.notificationService.updateBadgeCount()
                self.messageEventBroadcaster.conversationRefreshTrigger += 1
            } catch {
                // Silently ignore
            }
        }
    }
}

// MARK: - Preview Support

extension AppState {
    /// Creates an AppState for previews using an in-memory container
    @MainActor
    convenience init() {
        let schema = Schema([
            Device.self,
            Contact.self,
            Message.self,
            Channel.self,
            RemoteNodeSession.self,
            RoomMessage.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.init(modelContainer: container)
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
