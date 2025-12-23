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

    /// The sync coordinator for data synchronization (stored for direct observation)
    public private(set) var syncCoordinator: SyncCoordinator?

    /// Incremented when services change (device switch, reconnect). Views observe this to reload.
    public private(set) var servicesVersion: Int = 0

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

    /// Whether the syncing pill should be displayed
    /// True for: on-demand operations OR automatic device sync
    var shouldShowSyncingPill: Bool {
        syncActivityCount > 0 || syncCoordinator?.state.isSyncing == true
    }

    // MARK: - Derived State

    /// Whether connecting
    var isConnecting: Bool { connectionState == .connecting }

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        self.connectionManager = ConnectionManager(modelContainer: modelContainer)

        // Wire connection ready callback - automatically updates UI when connection completes
        connectionManager.onConnectionReady = { [weak self] in
            await self?.wireServicesIfConnected()
        }

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

        // activate() will trigger onConnectionReady callback if connection succeeds
        await connectionManager.activate()
    }

    /// Wire services to message event broadcaster
    func wireServicesIfConnected() async {
        guard let services else {
            // Clear syncCoordinator when services are nil
            syncCoordinator = nil
            return
        }

        // Store syncCoordinator directly for SwiftUI observation
        // (computed property chains through other objects break observation)
        syncCoordinator = services.syncCoordinator

        // Increment version to trigger UI refresh in views observing this
        servicesVersion += 1

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
    }

    // MARK: - Device Actions

    /// Start device scan/pairing
    func startDeviceScan() {
        Task {
            do {
                // pairNewDevice() triggers onConnectionReady callback on success
                try await connectionManager.pairNewDevice()
                hasCompletedOnboarding = true
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
                await self.syncCoordinator?.notifyConversationsChanged()
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
                await self.syncCoordinator?.notifyConversationsChanged()
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
