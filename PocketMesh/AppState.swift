import SwiftUI
import SwiftData
import UserNotifications
import PocketMeshServices
import MeshCore
import OSLog
import TipKit
import UIKit

/// Represents the current state of the status pill UI component
enum StatusPillState: Hashable {
    case hidden
    case connecting
    case syncing
    case ready
    case disconnected
    case failed(message: String)
}

/// Simplified app-wide state management.
/// Composes ConnectionManager for connection lifecycle.
/// Handles only UI state, navigation, and notification wiring.
@Observable
@MainActor
public final class AppState {

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.pocketmesh", category: "AppState")

    // MARK: - Location

    /// App-wide location service for permission management
    public let locationService = LocationService()

    // MARK: - Connection (via ConnectionManager)

    /// The connection manager for device lifecycle
    public let connectionManager: ConnectionManager

    // Convenience accessors
    public var connectionState: PocketMeshServices.ConnectionState { connectionManager.connectionState }
    public var connectedDevice: DeviceDTO? { connectionManager.connectedDevice }
    public var services: ServiceContainer? { connectionManager.services }
    public var currentTransportType: TransportType? { connectionManager.currentTransportType }

    /// Creates a standalone persistence store for operations that don't require active services
    public func createStandalonePersistenceStore() -> PersistenceStore {
        connectionManager.createStandalonePersistenceStore()
    }

    /// The sync coordinator for data synchronization
    public private(set) var syncCoordinator: SyncCoordinator?

    /// Incremented when services change (device switch, reconnect). Views observe this to reload.
    public private(set) var servicesVersion: Int = 0

    /// Incremented when contacts data changes. Views observe this to reload contact lists.
    public private(set) var contactsVersion: Int = 0

    /// Incremented when conversations data changes. Views observe this to reload chat lists.
    public private(set) var conversationsVersion: Int = 0

    // MARK: - UI State for Connection

    /// Whether to show connection failure alert
    var showingConnectionFailedAlert = false

    /// Message for connection failure alert
    var connectionFailedMessage: String?

    /// Device ID pending retry
    var pendingReconnectDeviceID: UUID?

    /// Device ID that failed pairing (wrong PIN) - for recovery UI
    var failedPairingDeviceID: UUID?

    /// Device ID that triggered "connected to other app" warning - alert shown when non-nil
    var otherAppWarningDeviceID: UUID?

    /// Whether device pairing is in progress (ASK picker or connecting after selection)
    var isPairing = false

    /// Current device battery info (nil if not fetched)
    var deviceBattery: BatteryInfo?

    /// Task for periodic battery refresh (cancel on disconnect/background)
    private var batteryRefreshTask: Task<Void, Never>?

    /// Thresholds that have already triggered a notification this session
    private var notifiedBatteryThresholds: Set<Int> = []

    /// Battery warning threshold levels (percentage)
    private let batteryWarningThresholds = [20, 10, 5]

    // MARK: - Onboarding State

    /// Whether onboarding is complete
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    /// Navigation path for onboarding flow
    var onboardingPath: [OnboardingStep] = []

    // MARK: - Navigation State

    /// Selected tab index
    var selectedTab: Int = 0

    var tabBarVisibility: Visibility = .visible

    /// Contact to navigate to
    var pendingChatContact: ContactDTO?

    /// Room session to navigate to
    var pendingRoomSession: RemoteNodeSessionDTO?

    /// Whether to navigate to Discovery
    var pendingDiscoveryNavigation = false

    /// Contact to navigate to (for detail view on Contacts tab)
    var pendingContactDetail: ContactDTO?

    /// Whether flood advert tip donation is pending (waiting for valid tab)
    var pendingFloodAdvertTipDonation = false

    // MARK: - UI Coordination

    /// Message event broadcaster for UI updates
    let messageEventBroadcaster = MessageEventBroadcaster()

    // MARK: - Activity Tracking

    /// Counter for sync/settings operations (on-demand) - shows pill
    private var syncActivityCount: Int = 0

    // MARK: - Ready Toast

    /// Whether the "Ready" toast pill is visible (shown briefly after connection completes)
    private(set) var showReadyToast = false

    /// Task managing the ready toast visibility timer
    private var readyToastTask: Task<Void, Never>?

    /// Shows "Ready" toast pill for 2 seconds
    func showReadyToastBriefly() {
        readyToastTask?.cancel()
        showReadyToast = true

        readyToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showReadyToast = false
        }
    }

    /// Hides the ready toast immediately (called on disconnect)
    func hideReadyToast() {
        readyToastTask?.cancel()
        readyToastTask = nil
        showReadyToast = false
    }

    // MARK: - Sync Failed Pill

    /// Whether the "Sync Failed" pill is visible
    private(set) var syncFailedPillVisible = false

    /// Task managing the pill visibility timer
    private var syncFailedPillTask: Task<Void, Never>?

    // MARK: - Disconnected Pill

    /// Whether the "Disconnected" pill is visible (shown after 1s delay)
    private(set) var disconnectedPillVisible = false

    /// Task managing the disconnected pill delay
    private var disconnectedPillTask: Task<Void, Never>?

    /// Shows "Sync Failed" pill for 7 seconds with VoiceOver announcement
    func showSyncFailedPill() {
        syncFailedPillTask?.cancel()
        syncFailedPillVisible = true

        // Announce for VoiceOver users
        if UIAccessibility.isVoiceOverRunning {
            announceConnectionState("Sync failed. Disconnecting.")
        }

        syncFailedPillTask = Task {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            syncFailedPillVisible = false
        }
    }

    /// Hides the sync failed pill immediately (called when resync succeeds)
    func hideSyncFailedPill() {
        syncFailedPillTask?.cancel()
        syncFailedPillTask = nil
        syncFailedPillVisible = false
    }

    /// Updates disconnected pill visibility based on connection state
    /// Called when connectionState changes
    func updateDisconnectedPillState() {
        disconnectedPillTask?.cancel()

        // Requires: disconnected + previously paired device
        guard connectionState == .disconnected,
              connectionManager.lastConnectedDeviceID != nil else {
            disconnectedPillVisible = false
            return
        }

        // Show after 1 second delay to avoid flash during brief reconnects
        disconnectedPillTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            disconnectedPillVisible = true
        }
    }

    /// Hides disconnected pill immediately (called when connection starts)
    func hideDisconnectedPill() {
        disconnectedPillTask?.cancel()
        disconnectedPillTask = nil
        disconnectedPillVisible = false
    }

    /// The current status pill state, computed from all relevant conditions
    /// Priority: failed > syncing > ready > connecting > disconnected > hidden
    var statusPillState: StatusPillState {
        if syncFailedPillVisible {
            return .failed(message: "Sync Failed")
        }
        if syncActivityCount > 0 {
            return .syncing
        }
        if showReadyToast {
            return .ready
        }
        if connectionState == .connecting || connectionState == .connected {
            return .connecting
        }
        if disconnectedPillVisible {
            return .disconnected
        }
        return .hidden
    }

    // MARK: - Derived State

    /// Whether connecting
    var isConnecting: Bool { connectionState == .connecting }

    /// The active OCV array for the connected device
    var activeBatteryOCVArray: [Int] {
        connectedDevice?.activeOCVArray ?? OCVPreset.liIon.ocvArray
    }

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        self.connectionManager = ConnectionManager(modelContainer: modelContainer)

        // Wire app state provider for incremental sync support
        connectionManager.appStateProvider = AppStateProviderImpl()

        // Wire connection ready callback - automatically updates UI when connection completes
        connectionManager.onConnectionReady = { [weak self] in
            await self?.wireServicesIfConnected()
        }

        // Wire connection lost callback - updates UI when connection is lost
        connectionManager.onConnectionLost = { [weak self] in
            await self?.wireServicesIfConnected()
        }

        // Set up notification handlers
        setupNotificationHandlers()
    }

    // MARK: - Lifecycle

    /// Initialize on app launch
    func initialize() async {
        // activate() will trigger onConnectionReady callback if connection succeeds
        // Notification delegate is set in wireServicesIfConnected() when services become available
        await connectionManager.activate()
    }

    /// Wire services to message event broadcaster
    func wireServicesIfConnected() async {
        guard let services else {
            // Announce disconnection for VoiceOver users
            if UIAccessibility.isVoiceOverRunning {
                announceConnectionState("Device connection lost")
            }
            // Clear syncCoordinator when services are nil
            syncCoordinator = nil
            // Reset sync activity count to prevent stuck pill
            syncActivityCount = 0
            // Hide ready toast on disconnect
            hideReadyToast()
            // Stop battery refresh loop on disconnect
            stopBatteryRefreshLoop()
            // Clear battery notification thresholds for next connection
            notifiedBatteryThresholds = []
            // Update disconnected pill state (may show after delay)
            updateDisconnectedPillState()
            return
        }

        // Hide disconnected pill when services are available (connected)
        hideDisconnectedPill()

        // Announce reconnection for VoiceOver users
        if UIAccessibility.isVoiceOverRunning {
            announceConnectionState("Device reconnected")
        }

        // Store syncCoordinator reference
        syncCoordinator = services.syncCoordinator

        // Wire data change callbacks for SwiftUI observation
        // (actors don't participate in SwiftUI's observation system, so we need callbacks)
        await services.syncCoordinator.setDataChangeCallbacks(
            onContactsChanged: { @MainActor [weak self] in
                self?.contactsVersion += 1
            },
            onConversationsChanged: { @MainActor [weak self] in
                self?.conversationsVersion += 1
            }
        )

        // Wire sync activity callbacks for syncing pill display
        // These are called for contacts and channels phases, NOT for messages
        // IMPORTANT: Must be set before onConnectionEstablished to avoid race condition
        await services.syncCoordinator.setSyncActivityCallbacks(
            onStarted: { @MainActor [weak self] in
                self?.syncActivityCount += 1
            },
            onEnded: { @MainActor [weak self] in
                guard let self else { return }
                self.syncActivityCount -= 1
                // Show "Ready" toast when all sync activity completes
                if self.syncActivityCount == 0 {
                    self.showReadyToastBriefly()
                }
            },
            onPhaseChanged: { _ in }
        )

        // Wire resync failed callback for "Sync Failed" pill
        connectionManager.onResyncFailed = { [weak self] in
            self?.showSyncFailedPill()
        }

        // Wire device update callback for settings changes
        // Updates connectedDevice when radio/node settings are changed via SettingsService
        await services.settingsService.setDeviceUpdateCallback { [weak self] selfInfo in
            await MainActor.run {
                self?.connectionManager.updateDevice(from: selfInfo)
            }
        }

        // Wire device update callback for device data changes
        // Updates connectedDevice when local device settings (like OCV) are changed via DeviceService
        await services.deviceService.setDeviceUpdateCallback { [weak self] deviceDTO in
            await MainActor.run {
                self?.connectionManager.updateDevice(with: deviceDTO)
            }
        }

        // Wire message event callbacks for real-time chat updates
        await services.syncCoordinator.setMessageEventCallbacks(
            onDirectMessageReceived: { [weak self] message, contact in
                await self?.messageEventBroadcaster.handleDirectMessage(message, from: contact)
            },
            onChannelMessageReceived: { [weak self] message, channelIndex in
                await self?.messageEventBroadcaster.handleChannelMessage(message, channelIndex: channelIndex)
            },
            onRoomMessageReceived: { [weak self] message in
                await self?.messageEventBroadcaster.handleRoomMessage(message)
            }
        )

        // Wire heard repeat callback for UI updates when repeats are recorded
        await services.heardRepeatsService.setRepeatRecordedHandler { [weak self] messageID, count in
            await MainActor.run {
                self?.messageEventBroadcaster.handleHeardRepeatRecorded(messageID: messageID, count: count)
            }
        }

        // Increment version to trigger UI refresh in views observing this
        servicesVersion += 1

        // Set up notification center delegate and check authorization
        UNUserNotificationCenter.current().delegate = services.notificationService
        await services.notificationService.setup()

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

        // Wire up ACK confirmation handler to trigger UI refresh on delivery
        await services.messageService.setAckConfirmationHandler { [weak self] ackCode, _ in
            Task { @MainActor in
                self?.messageEventBroadcaster.handleAcknowledgement(ackCode: ackCode)
            }
        }

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

        // Configure badge count callback
        services.notificationService.getBadgeCount = { [dataStore = services.dataStore] in
            do {
                return try await dataStore.getTotalUnreadCounts()
            } catch {
                return (contacts: 0, channels: 0, rooms: 0)
            }
        }

        // Configure notification interaction handlers
        configureNotificationHandlers()

        // Fetch battery and initialize thresholds before starting periodic checks
        // We fetch directly here (not via fetchDeviceBattery) to avoid calling
        // checkBatteryThresholds before thresholds are initialized
        deviceBattery = try? await services.settingsService.getBattery()
        initializeBatteryThresholds()
        startBatteryRefreshLoop()
    }

    // MARK: - Device Actions

    /// Start device scan/pairing
    func startDeviceScan() {
        // Hide disconnected pill when starting new connection
        hideDisconnectedPill()
        // Clear any previous pairing failure state
        failedPairingDeviceID = nil
        isPairing = true

        Task {
            defer { isPairing = false }

            do {
                // pairNewDevice() triggers onConnectionReady callback on success
                try await connectionManager.pairNewDevice()
                await wireServicesIfConnected()

                // If still in onboarding, navigate to radio preset; otherwise mark complete
                if !hasCompletedOnboarding {
                    onboardingPath.append(.radioPreset)
                }
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error
            } catch AccessorySetupKitError.pickerAlreadyActive {
                // Picker is already showing - ignore
            } catch let pairingError as PairingError {
                // ASK pairing succeeded but BLE connection failed (e.g., wrong PIN)
                // Store device ID for recovery UI instead of showing generic alert
                failedPairingDeviceID = pairingError.deviceID
                connectionFailedMessage = "Authentication failed. The device was added but couldn't connect — this usually means the wrong PIN was entered."
                showingConnectionFailedAlert = true
            } catch {
                connectionFailedMessage = error.localizedDescription
                showingConnectionFailedAlert = true
            }
        }
    }

    /// Flag indicating ASK picker should be shown when app returns to foreground
    var shouldShowPickerOnForeground = false

    /// Remove a device that failed pairing (wrong PIN) and automatically retry
    func removeFailedPairingAndRetry() {
        guard let deviceID = failedPairingDeviceID else { return }

        Task {
            await connectionManager.removeFailedPairing(deviceID: deviceID)
            failedPairingDeviceID = nil
            // Set flag - View observing scenePhase will trigger startDeviceScan when active
            shouldShowPickerOnForeground = true
        }
    }

    /// Dismisses the other app warning alert
    func cancelOtherAppWarning() {
        otherAppWarningDeviceID = nil
    }

    /// Called by View when scenePhase becomes active and shouldShowPickerOnForeground is true
    func handleBecameActive() {
        guard shouldShowPickerOnForeground else { return }
        shouldShowPickerOnForeground = false
        startDeviceScan()
    }

    /// Disconnect from device
    func disconnect() async {
        await connectionManager.disconnect()
    }

    /// Connect to a device via WiFi/TCP
    func connectViaWiFi(host: String, port: UInt16) async throws {
        // Hide disconnected pill when starting new connection
        hideDisconnectedPill()
        try await connectionManager.connectViaWiFi(host: host, port: port)
        await wireServicesIfConnected()
    }

    /// Fetch device battery level
    func fetchDeviceBattery() async {
        guard let settingsService = services?.settingsService else { return }

        do {
            deviceBattery = try await settingsService.getBattery()
            await checkBatteryThresholds()
        } catch {
            // Silently fail - battery info is optional
            deviceBattery = nil
        }
    }

    /// Start periodic battery refresh loop (2-minute interval)
    private func startBatteryRefreshLoop() {
        batteryRefreshTask?.cancel()
        batteryRefreshTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    break  // Cancelled, exit cleanly
                }
                guard let self, self.services != nil else { break }
                await self.fetchDeviceBattery()
            }
        }
    }

    /// Stop periodic battery refresh
    private func stopBatteryRefreshLoop() {
        batteryRefreshTask?.cancel()
        batteryRefreshTask = nil
    }

    /// Initialize battery thresholds based on current level to prevent false notifications on connect
    private func initializeBatteryThresholds() {
        guard let battery = deviceBattery, let device = connectedDevice else {
            notifiedBatteryThresholds = []
            return
        }

        let percentage = battery.percentage(using: device.activeOCVArray)

        // Mark all thresholds at or above current level as "already notified"
        notifiedBatteryThresholds = Set(
            batteryWarningThresholds.filter { percentage <= $0 }
        )
    }

    /// Check battery level against thresholds and send notifications
    private func checkBatteryThresholds() async {
        guard let battery = deviceBattery,
              let device = connectedDevice,
              let notificationService = services?.notificationService else { return }

        let percentage = battery.percentage(using: device.activeOCVArray)

        for threshold in batteryWarningThresholds {
            if percentage <= threshold && !notifiedBatteryThresholds.contains(threshold) {
                // First time crossing below this threshold
                notifiedBatteryThresholds.insert(threshold)
                await notificationService.postLowBatteryNotification(
                    deviceName: device.nodeName,
                    batteryPercentage: percentage
                )
                break  // Only one notification per check
            } else if percentage > threshold && notifiedBatteryThresholds.contains(threshold) {
                // Charged back above threshold — reset it
                notifiedBatteryThresholds.remove(threshold)
            }
        }
    }

    /// Check for battery thresholds crossed while app was backgrounded
    /// Posts a single notification if any thresholds were missed, marking all as notified
    private func checkMissedBatteryThreshold() async {
        guard let device = connectedDevice,
              let settingsService = services?.settingsService,
              let notificationService = services?.notificationService else { return }

        do {
            deviceBattery = try await settingsService.getBattery()
        } catch {
            return
        }

        guard let battery = deviceBattery else { return }
        let percentage = battery.percentage(using: device.activeOCVArray)

        // Find thresholds crossed while backgrounded
        let missedThresholds = batteryWarningThresholds.filter { threshold in
            percentage <= threshold && !notifiedBatteryThresholds.contains(threshold)
        }

        guard !missedThresholds.isEmpty else { return }

        // Mark all crossed thresholds as notified
        for threshold in missedThresholds {
            notifiedBatteryThresholds.insert(threshold)
        }

        // Post single notification with current percentage
        await notificationService.postLowBatteryNotification(
            deviceName: device.nodeName,
            batteryPercentage: percentage
        )
    }

    // MARK: - App Lifecycle

    /// Called when app enters background
    func handleEnterBackground() {
        // Stop battery refresh - don't poll while UI isn't visible
        stopBatteryRefreshLoop()
    }

    /// Called when app returns to foreground
    func handleReturnToForeground() async {
        // Update badge count from database
        await services?.notificationService.updateBadgeCount()

        // Check for missed battery thresholds and restart polling if connected
        if services != nil {
            await checkMissedBatteryThreshold()
            startBatteryRefreshLoop()
        }

        // Check for expired ACKs
        if connectionState == .ready {
            try? await services?.messageService.checkExpiredAcks()
        }

        // Check connection health (may have died while backgrounded)
        await connectionManager.checkWiFiConnectionHealth()
        await connectionManager.checkBLEConnectionHealth()

        // Trigger resync if sync failed while connected
        await connectionManager.checkSyncHealth()
    }

    // MARK: - Accessibility

    /// Posts a VoiceOver announcement for connection state changes
    private func announceConnectionState(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: - Navigation

    func navigateToChat(with contact: ContactDTO) {
        tabBarVisibility = .hidden  // Hide tab bar BEFORE switching tabs
        pendingChatContact = contact
        selectedTab = 0
    }

    func navigateToRoom(with session: RemoteNodeSessionDTO) {
        tabBarVisibility = .hidden  // Hide tab bar BEFORE switching tabs
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

    func navigateToContactDetail(_ contact: ContactDTO) {
        pendingContactDetail = contact
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

    func clearPendingContactDetailNavigation() {
        pendingContactDetail = nil
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await donateFloodAdvertTipIfOnValidTab()
        }
    }

    /// Tabs where BLEStatusIndicatorView exists and tip can anchor (Chats, Contacts, Map)
    private var isOnValidTabForFloodAdvertTip: Bool {
        selectedTab == 0 || selectedTab == 1 || selectedTab == 2
    }

    /// Donates the tip if on a valid tab, otherwise marks it pending
    func donateFloodAdvertTipIfOnValidTab() async {
        if isOnValidTabForFloodAdvertTip {
            pendingFloodAdvertTipDonation = false
            await SendFloodAdvertTip.hasCompletedOnboarding.donate()
        } else {
            pendingFloodAdvertTipDonation = true
        }
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        onboardingPath = []
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
        services.notificationService.onNewContactNotificationTapped = { [weak self] contactID in
            guard let self else { return }

            if self.connectedDevice?.manualAddContacts == true {
                self.navigateToDiscovery()
            } else {
                // Navigate to contact detail, with contacts list as base
                guard let contact = try? await services.dataStore.fetchContact(id: contactID) else {
                    self.navigateToContacts()
                    return
                }
                self.navigateToContactDetail(contact)
            }
        }

        // Quick reply handler
        services.notificationService.onQuickReply = { [weak self] contactID, text in
            guard let self else { return }

            guard let contact = try? await services.dataStore.fetchContact(id: contactID) else { return }

            if self.connectionState == .ready {
                do {
                    _ = try await services.messageService.sendDirectMessage(text: text, to: contact)

                    // Clear unread state - user replied so they've seen the chat
                    try? await services.dataStore.clearUnreadCount(contactID: contactID)
                    await services.notificationService.removeDeliveredNotifications(forContactID: contactID)
                    await services.notificationService.updateBadgeCount()
                    self.syncCoordinator?.notifyConversationsChanged()
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
                self.syncCoordinator?.notifyConversationsChanged()
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
                self.syncCoordinator?.notifyConversationsChanged()
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

enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case permissions
    case deviceScan
    case radioPreset
}

// MARK: - Environment Key

/// Environment key for AppState with safe default for background snapshot scenarios.
/// MainActor.assumeIsolated asserts we're on the main actor, which is always true
/// for SwiftUI environment access in views.
private struct AppStateKey: EnvironmentKey {
    static var defaultValue: AppState {
        MainActor.assumeIsolated {
            AppState()
        }
    }
}

extension EnvironmentValues {
    /// AppState environment value with safe default for background snapshot scenarios.
    /// Having a default value ensures a value is always available, preventing crashes when
    /// iOS takes app switcher snapshots or launches the app in background.
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
