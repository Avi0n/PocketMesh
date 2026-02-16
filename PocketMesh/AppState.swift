import SwiftUI
import SwiftData
import UserNotifications
import PocketMeshServices
import MeshCore
import OSLog
import TipKit
import UIKit

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
    private let bootstrapDebugLogBuffer: DebugLogBuffer

    // Convenience accessors
    public var connectionState: PocketMeshServices.ConnectionState { connectionManager.connectionState }
    public var connectedDevice: DeviceDTO? { connectionManager.connectedDevice }
    public var services: ServiceContainer? { connectionManager.services }

    /// The sync coordinator for data synchronization
    public private(set) var syncCoordinator: SyncCoordinator?

    /// Incremented when services change (device switch, reconnect). Views observe this to reload.
    public private(set) var servicesVersion: Int = 0

    // MARK: - Offline Data Access

    /// Cached standalone persistence store for offline browsing
    private var cachedOfflineStore: PersistenceStore?

    /// Device ID for data access - returns connected device or last-connected device for offline browsing
    public var currentDeviceID: UUID? {
        connectedDevice?.id ?? connectionManager.lastConnectedDeviceID
    }

    /// Data store that works regardless of connection state - uses services when connected,
    /// cached standalone store when disconnected
    public var offlineDataStore: PersistenceStore? {
        if let services {
            cachedOfflineStore = nil  // Clear cache when services available
            return services.dataStore
        }
        guard connectionManager.lastConnectedDeviceID != nil else {
            cachedOfflineStore = nil
            return nil
        }
        if cachedOfflineStore == nil {
            cachedOfflineStore = connectionManager.createStandalonePersistenceStore()
        }
        return cachedOfflineStore
    }

    /// Incremented when contacts data changes. Views observe this to reload contact lists.
    public private(set) var contactsVersion: Int = 0

    /// Incremented when conversations data changes. Views observe this to reload chat lists.
    public private(set) var conversationsVersion: Int = 0

    // MARK: - Connection UI State

    /// Connection UI state (status pills, sync activity, alerts, pairing)
    let connectionUI = ConnectionUIState()

    /// Battery monitoring (polling, thresholds, low-battery notifications)
    let batteryMonitor = BatteryMonitor()

    /// Task chain that serializes BLE lifecycle transitions across scene-phase changes.
    /// Do not cancel this task externally -- cancelling breaks the serialization
    /// guarantee because Task<Void, Never>.value returns immediately on cancellation.
    private var bleLifecycleTransitionTask: Task<Void, Never>?

    /// Fallback task that re-runs foreground recovery shortly after activation when the
    /// app is still disconnected. Covers edge cases where scene-phase callbacks are missed.
    private var activeRecoveryFallbackTask: Task<Void, Never>?

#if DEBUG
    /// Optional test-only hooks for deterministic lifecycle ordering tests.
    private var bleEnterBackgroundOverride: (@MainActor () async -> Void)?
    private var bleBecomeActiveOverride: (@MainActor () async -> Void)?
#endif


    // MARK: - Onboarding State

    /// Onboarding state (completion flag, navigation path)
    let onboarding = OnboardingState()

    // MARK: - Navigation State

    /// Navigation coordinator (tab selection, pending targets, cross-tab navigation)
    let navigation = NavigationCoordinator()

    // MARK: - UI Coordination

    /// Message event broadcaster for UI updates
    let messageEventBroadcaster = MessageEventBroadcaster()

    // MARK: - CLI Tool

    /// Persistent CLI tool view model (survives tab switches, reset on device disconnect)
    var cliToolViewModel: CLIToolViewModel?

    /// Tracks the device ID for CLI state - reset CLI when device changes
    private var lastConnectedDeviceIDForCLI: UUID?

    // MARK: - Status Pill

    /// The current status pill state, computed from all relevant conditions
    /// Priority: failed > syncing > ready > connecting > disconnected > hidden
    var statusPillState: StatusPillState {
        if connectionUI.syncFailedPillVisible {
            return .failed(message: "Sync Failed")
        }
        if connectionUI.syncActivityCount > 0 {
            return .syncing
        }
        if connectionUI.showReadyToast {
            return .ready
        }
        if connectionState == .connecting {
            return .connecting
        }
        if connectionUI.disconnectedPillVisible {
            return .disconnected
        }
        return .hidden
    }

    /// Whether Settings startup reads should run right now.
    var canRunSettingsStartupReads: Bool {
        if connectionState == .ready { return true }
        return connectionState == .connected && connectionUI.currentSyncPhase == .messages
    }

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        let bootstrapStore = PersistenceStore(modelContainer: modelContainer)
        let bootstrapBuffer = DebugLogBuffer(persistenceStore: bootstrapStore)
        self.bootstrapDebugLogBuffer = bootstrapBuffer
        DebugLogBuffer.shared = bootstrapBuffer

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
    }

    // MARK: - Lifecycle

    /// Initialize on app launch
    func initialize() async {
        // activate() will trigger onConnectionReady callback if connection succeeds
        // Notification delegate is set in wireServicesIfConnected() when services become available
        await connectionManager.activate()
        // Check if disconnected pill should show (for fresh launch after termination)
        connectionUI.updateDisconnectedPillState(
            connectionState: connectionState,
            lastConnectedDeviceID: connectionManager.lastConnectedDeviceID,
            shouldSuppressDisconnectedPill: connectionManager.shouldSuppressDisconnectedPill
        )
    }

    /// Wire services to message event broadcaster
    func wireServicesIfConnected() async {
        guard let services else {
            // Announce disconnection for VoiceOver users
            if UIAccessibility.isVoiceOverRunning {
                connectionUI.announceConnectionState("Device connection lost")
            }
            // Clear syncCoordinator when services are nil
            syncCoordinator = nil
            // Reset sync activity count to prevent stuck pill
            connectionUI.syncActivityCount = 0
            connectionUI.currentSyncPhase = nil
            // Reset CLI tool state on disconnect (preserves command history)
            cliToolViewModel?.reset()
            // Hide ready toast on disconnect
            connectionUI.hideReadyToast()
            // Stop battery refresh and clear thresholds on disconnect
            batteryMonitor.stop()
            batteryMonitor.clearThresholds()
            // Reset node storage full flag (will be set again by 0x90 push if still full)
            connectionUI.isNodeStorageFull = false
            // Update disconnected pill state (may show after delay)
            connectionUI.updateDisconnectedPillState(
            connectionState: connectionState,
            lastConnectedDeviceID: connectionManager.lastConnectedDeviceID,
            shouldSuppressDisconnectedPill: connectionManager.shouldSuppressDisconnectedPill
        )
            return
        }

        // Hide disconnected pill when services are available (connected)
        connectionUI.hideDisconnectedPill()

        // Reset CLI if device changed (handles device switch where onConnectionLost doesn't fire)
        if let newDeviceID = connectedDevice?.id,
           let oldDeviceID = lastConnectedDeviceIDForCLI,
           newDeviceID != oldDeviceID {
            cliToolViewModel?.reset()
        }
        lastConnectedDeviceIDForCLI = connectedDevice?.id

        // Announce reconnection for VoiceOver users
        if UIAccessibility.isVoiceOverRunning {
            connectionUI.announceConnectionState("Device reconnected")
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
                self?.connectionUI.syncActivityCount += 1
            },
            onEnded: { @MainActor [weak self] in
                guard let self else { return }
                // Guard against double-decrement: onDisconnected and sync error path
                // can both call this if WiFi drops or device switch during sync
                guard self.connectionUI.syncActivityCount > 0 else { return }
                self.connectionUI.syncActivityCount -= 1
                // Show "Ready" toast when all sync activity completes
                if self.connectionUI.syncActivityCount == 0 {
                    self.connectionUI.showReadyToastBriefly()
                }
            },
            onPhaseChanged: { @MainActor [weak self] phase in
                self?.connectionUI.currentSyncPhase = phase
            }
        )

        // Wire resync failed callback for "Sync Failed" pill
        connectionManager.onResyncFailed = { [weak self] in
            self?.connectionUI.showSyncFailedPill()
        }

        // Consume settings service event stream
        // Updates connectedDevice when settings are changed via SettingsService
        Task { [weak self] in
            guard let self else { return }
            for await event in await services.settingsService.events() {
                switch event {
                case .deviceUpdated(let selfInfo):
                    await MainActor.run {
                        self.connectionManager.updateDevice(from: selfInfo)
                    }
                case .autoAddConfigUpdated(let config):
                    await MainActor.run {
                        self.connectionManager.updateAutoAddConfig(config)
                        // Clear storage full flag when overwrite oldest is enabled (bit 0x01)
                        if config & 0x01 != 0 {
                            self.connectionUI.isNodeStorageFull = false
                        }
                    }
                case .clientRepeatUpdated(let enabled):
                    await MainActor.run {
                        self.connectionManager.updateClientRepeat(enabled)
                    }
                case .allowedRepeatFreqUpdated(let ranges):
                    await MainActor.run {
                        self.connectionManager.allowedRepeatFreqRanges = ranges
                    }
                }
            }
        }

        // Wire device update callback for device data changes
        // Updates connectedDevice when local device settings (like OCV) are changed via DeviceService
        await services.deviceService.setDeviceUpdateCallback { [weak self] deviceDTO in
            await MainActor.run {
                self?.connectionManager.updateDevice(with: deviceDTO)
            }
        }

        // Wire node storage full callback
        // Updates isNodeStorageFull when 0x90 (contactsFull) or 0x8F (contactDeleted) push received
        await services.advertisementService.setNodeStorageFullChangedHandler { [weak self] isFull in
            await MainActor.run {
                self?.connectionUI.isNodeStorageFull = isFull
            }
        }

        // Wire contact updated callback for real-time Discover page updates
        await services.advertisementService.setContactUpdatedHandler { @MainActor [weak self] in
            self?.contactsVersion += 1
        }

        // Wire node deleted callback
        // Clears isNodeStorageFull when user manually deletes a node (frees up space)
        await services.contactService.setNodeDeletedHandler { [weak self] in
            await MainActor.run {
                self?.connectionUI.isNodeStorageFull = false
            }
        }

        // Wire contact deleted cleanup callback
        // Removes notifications and updates badge when device auto-deletes a contact via 0x8F
        await services.advertisementService.setContactDeletedCleanupHandler { [weak self] contactID, _ in
            guard let self else { return }
            await self.services?.notificationService.removeDeliveredNotifications(forContactID: contactID)
            await self.services?.notificationService.updateBadgeCount()
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
            },
            onReactionReceived: { [weak self] messageID, summary in
                await self?.messageEventBroadcaster.handleReactionReceived(messageID: messageID, summary: summary)
                await self?.handleReactionNotification(messageID: messageID)
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

        // Wire notification string provider for localized discovery notifications
        services.notificationService.setStringProvider(NotificationStringProviderImpl())

        // Wire message service for send confirmation handling
        messageEventBroadcaster.messageService = services.messageService

        // Wire remote node service for login result handling
        messageEventBroadcaster.remoteNodeService = services.remoteNodeService
        messageEventBroadcaster.dataStore = services.dataStore

        // Wire session state change handler for room connection status UI updates
        await services.remoteNodeService.setSessionStateChangedHandler { [weak self] sessionID, isConnected in
            await MainActor.run {
                self?.conversationsVersion += 1
                self?.messageEventBroadcaster.handleSessionStateChanged(sessionID: sessionID, isConnected: isConnected)
            }
        }

        // Wire room connection recovery handler
        await services.roomServerService.setConnectionRecoveryHandler { [weak self] sessionID in
            await MainActor.run {
                self?.conversationsVersion += 1
                self?.messageEventBroadcaster.handleSessionStateChanged(sessionID: sessionID, isConnected: true)
            }
        }

        // Wire room server service for room message handling
        messageEventBroadcaster.roomServerService = services.roomServerService

        // Wire room message status handler for delivery confirmation UI updates
        await services.roomServerService.setStatusUpdateHandler { [weak self] messageID, status in
            await MainActor.run {
                if status == .failed {
                    self?.messageEventBroadcaster.handleRoomMessageFailed(messageID: messageID)
                } else {
                    self?.messageEventBroadcaster.handleRoomMessageStatusUpdated(messageID: messageID)
                }
            }
        }

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
        services.notificationService.getBadgeCount = { [weak self, dataStore = services.dataStore] in
            let deviceID = await MainActor.run { self?.currentDeviceID }
            guard let deviceID else {
                return (contacts: 0, channels: 0, rooms: 0)
            }
            do {
                return try await dataStore.getTotalUnreadCounts(deviceID: deviceID)
            } catch {
                return (contacts: 0, channels: 0, rooms: 0)
            }
        }

        // Configure notification interaction handlers
        configureNotificationHandlers()

        // Defer battery bootstrap so connection setup is not blocked by device request timeouts.
        batteryMonitor.start(services: services, device: connectedDevice)
    }

    // MARK: - Device Actions

    /// Start device scan/pairing
    func startDeviceScan() {
        // Hide disconnected pill when starting new connection
        connectionUI.hideDisconnectedPill()
        // Clear any previous pairing failure state
        connectionUI.failedPairingDeviceID = nil
        connectionUI.isPairing = true

        Task {
            defer { connectionUI.isPairing = false }

            do {
                // pairNewDevice() triggers onConnectionReady callback on success
                try await connectionManager.pairNewDevice()
                await wireServicesIfConnected()

                // If still in onboarding, navigate to radio preset; otherwise mark complete
                if !onboarding.hasCompletedOnboarding {
                    onboarding.onboardingPath.append(.radioPreset)
                }
            } catch AccessorySetupKitError.pickerDismissed {
                // User cancelled - no error
            } catch AccessorySetupKitError.pickerAlreadyActive {
                // Picker is already showing - ignore
            } catch let pairingError as PairingError {
                // ASK pairing succeeded but BLE connection failed (e.g., wrong PIN)
                // Store device ID for recovery UI instead of showing generic alert
                connectionUI.failedPairingDeviceID = pairingError.deviceID
                connectionUI.connectionFailedMessage = "Authentication failed. The device was added but couldn't connect — this usually means the wrong PIN was entered."
                connectionUI.showingConnectionFailedAlert = true
            } catch {
                connectionUI.connectionFailedMessage = error.localizedDescription
                connectionUI.showingConnectionFailedAlert = true
            }
        }
    }

    /// Remove a device that failed pairing (wrong PIN) and automatically retry
    func removeFailedPairingAndRetry() {
        guard let deviceID = connectionUI.failedPairingDeviceID else { return }

        Task {
            await connectionManager.removeFailedPairing(deviceID: deviceID)
            connectionUI.failedPairingDeviceID = nil
            // Set flag - View observing scenePhase will trigger startDeviceScan when active
            connectionUI.shouldShowPickerOnForeground = true
        }
    }

    /// Dismisses the other app warning alert
    func cancelOtherAppWarning() {
        connectionUI.otherAppWarningDeviceID = nil
    }

    /// Called by View when scenePhase becomes active and shouldShowPickerOnForeground is true
    func handleBecameActive() {
        if connectionUI.shouldShowPickerOnForeground {
            connectionUI.shouldShowPickerOnForeground = false
            startDeviceScan()
        }

        activeRecoveryFallbackTask?.cancel()
        activeRecoveryFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard self.connectionState == .disconnected,
                  self.connectionManager.lastConnectedDeviceID != nil else { return }

            self.logger.info("[BLE] Active fallback: disconnected after activation, running foreground reconciliation")
            await self.handleReturnToForeground()
        }
    }

    /// Disconnect from device
    /// - Parameter reason: The reason for disconnecting (for debugging)
    func disconnect(reason: DisconnectReason = .userInitiated) async {
        await connectionManager.disconnect(reason: reason)
    }

    /// Connect to a device via WiFi/TCP
    func connectViaWiFi(host: String, port: UInt16, forceFullSync: Bool = false) async throws {
        // Hide disconnected pill when starting new connection
        connectionUI.hideDisconnectedPill()
        try await connectionManager.connectViaWiFi(host: host, port: port, forceFullSync: forceFullSync)
        await wireServicesIfConnected()
    }

    // MARK: - App Lifecycle

    private enum BLELifecycleTransition {
        case enterBackground
        case becomeActive
    }

    @discardableResult
    private func enqueueBLELifecycleTransition(_ transition: BLELifecycleTransition) -> Task<Void, Never> {
        let priorTask = bleLifecycleTransitionTask
        let manager = connectionManager

        let transitionTask = Task { @MainActor in
            await priorTask?.value

#if DEBUG
            switch transition {
            case .enterBackground:
                if let override = bleEnterBackgroundOverride {
                    await override()
                    return
                }
            case .becomeActive:
                if let override = bleBecomeActiveOverride {
                    await override()
                    return
                }
            }
#endif

            switch transition {
            case .enterBackground:
                await manager.appDidEnterBackground()
            case .becomeActive:
                await manager.appDidBecomeActive()
            }
        }

        bleLifecycleTransitionTask = transitionTask
        return transitionTask
    }

    /// Called when app enters background
    func handleEnterBackground() {
        activeRecoveryFallbackTask?.cancel()
        activeRecoveryFallbackTask = nil

        // Stop battery refresh - don't poll while UI isn't visible
        batteryMonitor.stop()

        // Stop room keepalives to save battery/bandwidth
        Task {
            await services?.remoteNodeService.stopAllKeepAlives()
        }

        // Queue BLE lifecycle transition so background/foreground hooks stay ordered.
        enqueueBLELifecycleTransition(.enterBackground)
    }

    /// Called when app returns to foreground
    func handleReturnToForeground() async {
        // Update badge count from database
        await services?.notificationService.updateBadgeCount()

        // Room keepalives are managed by RoomConversationView lifecycle
        // (started on view appear, stopped on disappear, restarted via scenePhase)

        // Check for missed battery thresholds and restart polling if connected
        if let services {
            await batteryMonitor.checkMissedBatteryThreshold(device: connectedDevice, services: services)
            batteryMonitor.startRefreshLoop(services: services, device: connectedDevice)
        }

        // Check for expired ACKs
        if connectionState == .ready {
            try? await services?.messageService.checkExpiredAcks()
        }

        // Check connection health (may have died while backgrounded)
        await connectionManager.checkWiFiConnectionHealth()
        await enqueueBLELifecycleTransition(.becomeActive).value

        // Trigger resync if sync failed while connected
        await connectionManager.checkSyncHealth()
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        onboarding.completeOnboarding()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await donateFloodAdvertTipIfOnValidTab()
        }
    }

    /// Tabs where BLEStatusIndicatorView exists and tip can anchor (Chats, Contacts, Map)
    private var isOnValidTabForFloodAdvertTip: Bool {
        navigation.selectedTab == 0 || navigation.selectedTab == 1 || navigation.selectedTab == 2
    }

    /// Donates the tip if on a valid tab, otherwise marks it pending.
    /// Thin coordinator that reads from both navigation and onboarding concerns.
    func donateFloodAdvertTipIfOnValidTab() async {
        if isOnValidTabForFloodAdvertTip {
            navigation.pendingFloodAdvertTipDonation = false
            await SendFloodAdvertTip.hasCompletedOnboarding.donate()
        } else {
            navigation.pendingFloodAdvertTipDonation = true
        }
    }

#if DEBUG
    /// Test helper: Overrides BLE lifecycle operations for deterministic ordering tests.
    func setBLELifecycleOverridesForTesting(
        enterBackground: (@MainActor () async -> Void)? = nil,
        becomeActive: (@MainActor () async -> Void)? = nil
    ) {
        bleEnterBackgroundOverride = enterBackground
        bleBecomeActiveOverride = becomeActive
    }
#endif

    // MARK: - Notification Handlers

    /// Configure notification handlers once services are available
    func configureNotificationHandlers() {
        guard let services else { return }

        // Notification tap handler
        services.notificationService.onNotificationTapped = { [weak self] contactID in
            guard let self else { return }

            guard let contact = try? await services.dataStore.fetchContact(id: contactID) else { return }
            self.navigation.navigateToChat(with: contact)
        }

        // New contact notification tap
        services.notificationService.onNewContactNotificationTapped = { [weak self] contactID in
            guard let self else { return }

            if self.connectedDevice?.manualAddContacts == true {
                self.navigation.navigateToDiscovery()
            } else {
                // Navigate to contact detail, with contacts list as base
                guard let contact = try? await services.dataStore.fetchContact(id: contactID) else {
                    self.navigation.navigateToContacts()
                    return
                }
                self.navigation.navigateToContactDetail(contact)
            }
        }

        // Channel notification tap handler
        services.notificationService.onChannelNotificationTapped = { [weak self] deviceID, channelIndex in
            guard let self else { return }

            guard let channel = try? await services.dataStore.fetchChannel(deviceID: deviceID, index: channelIndex) else { return }
            self.navigation.navigateToChannel(with: channel)
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

        // Channel quick reply handler
        services.notificationService.onChannelQuickReply = { [weak self] deviceID, channelIndex, text in
            guard let self else { return }

            // Fetch channel for display name in failure notification
            let channel = try? await services.dataStore.fetchChannel(deviceID: deviceID, index: channelIndex)
            let channelName = channel?.name ?? "Channel \(channelIndex)"

            guard self.connectionState == .ready else {
                await services.notificationService.postChannelQuickReplyFailedNotification(
                    channelName: channelName,
                    deviceID: deviceID,
                    channelIndex: channelIndex
                )
                return
            }

            do {
                _ = try await services.messageService.sendChannelMessage(
                    text: text,
                    channelIndex: channelIndex,
                    deviceID: deviceID
                )

                // Clear unread state - user replied so they've seen the channel
                try? await services.dataStore.clearChannelUnreadCount(deviceID: deviceID, index: channelIndex)
                await services.notificationService.removeDeliveredNotifications(
                    forChannelIndex: channelIndex,
                    deviceID: deviceID
                )
                await services.notificationService.updateBadgeCount()
                self.syncCoordinator?.notifyConversationsChanged()
            } catch {
                await services.notificationService.postChannelQuickReplyFailedNotification(
                    channelName: channelName,
                    deviceID: deviceID,
                    channelIndex: channelIndex
                )
            }
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

        // Reaction notification tap handler
        services.notificationService.onReactionNotificationTapped = { [weak self] contactID, channelIndex, deviceID, messageID in
            guard let self else { return }

            // Navigate to the appropriate conversation and scroll to the message
            if let contactID,
               let contact = try? await services.dataStore.fetchContact(id: contactID) {
                self.navigation.navigateToChat(with: contact, scrollToMessageID: messageID)
            } else if let channelIndex, let deviceID,
                      let channel = try? await services.dataStore.fetchChannel(deviceID: deviceID, index: channelIndex) {
                self.navigation.navigateToChannel(with: channel, scrollToMessageID: messageID)
            }
        }
    }

    /// Handle posting a notification when someone reacts to the user's message
    private func handleReactionNotification(messageID: UUID) async {
        guard let services else { return }

        // Fetch the message to check if it's outgoing
        guard let message = try? await services.dataStore.fetchMessage(id: messageID),
              message.direction == .outgoing else {
            return
        }

        // Fetch the latest reaction for this message
        guard let reactions = try? await services.dataStore.fetchReactions(for: messageID, limit: 1),
              let latestReaction = reactions.first else {
            return
        }

        // Check if this is a self-reaction (user reacting to their own message)
        if let localNodeName = connectedDevice?.nodeName,
           latestReaction.senderName == localNodeName {
            return
        }

        // Check mute status based on message type
        let isMuted: Bool
        if let contactID = message.contactID {
            let contact = try? await services.dataStore.fetchContact(id: contactID)
            isMuted = contact?.isMuted ?? false
        } else if let channelIndex = message.channelIndex {
            let channel = try? await services.dataStore.fetchChannel(deviceID: message.deviceID, index: channelIndex)
            isMuted = channel?.isMuted ?? false
        } else {
            isMuted = false
        }

        guard !isMuted else { return }

        // Truncate preview if too long
        let truncatedPreview = message.text.count > 50
            ? String(message.text.prefix(47)) + "..."
            : message.text

        // Post the notification
        await services.notificationService.postReactionNotification(
            reactorName: latestReaction.senderName,
            body: L10n.Localizable.Notifications.Reaction.body(latestReaction.emoji, truncatedPreview),
            messageID: messageID,
            contactID: message.contactID,
            channelIndex: message.channelIndex,
            deviceID: message.channelIndex != nil ? message.deviceID : nil
        )
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
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.init(modelContainer: container)
    }
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
