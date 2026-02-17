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
        let bootstrapBuffer = DebugLogBuffer(dataStore: bootstrapStore)
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
            syncCoordinator = nil
            connectionUI.handleDisconnect(
                connectionState: connectionState,
                lastConnectedDeviceID: connectionManager.lastConnectedDeviceID,
                shouldSuppressDisconnectedPill: connectionManager.shouldSuppressDisconnectedPill
            )
            cliToolViewModel?.reset()
            batteryMonitor.stop()
            batteryMonitor.clearThresholds()
            return
        }

        // Wire ConnectionUI callbacks (sync activity, node storage, pills, VoiceOver)
        // IMPORTANT: Must be set before onConnectionEstablished to avoid race condition
        await connectionUI.wireCallbacks(
            syncCoordinator: services.syncCoordinator,
            advertisementService: services.advertisementService,
            contactService: services.contactService,
            connectionManager: connectionManager
        )

        // Reset CLI if device changed (handles device switch where onConnectionLost doesn't fire)
        if let newDeviceID = connectedDevice?.id,
           let oldDeviceID = lastConnectedDeviceIDForCLI,
           newDeviceID != oldDeviceID {
            cliToolViewModel?.reset()
        }
        lastConnectedDeviceIDForCLI = connectedDevice?.id

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

        // Wire contact updated callback for real-time Discover page updates
        await services.advertisementService.setContactUpdatedHandler { @MainActor [weak self] in
            self?.contactsVersion += 1
        }

        // Wire contact deleted cleanup callback
        // Removes notifications and updates badge when device auto-deletes a contact via 0x8F
        await services.advertisementService.setContactDeletedCleanupHandler { [weak self] contactID, _ in
            guard let self else { return }
            await self.services?.notificationService.removeDeliveredNotifications(forContactID: contactID)
            await self.services?.notificationService.updateBadgeCount()
        }

        // Wire message event broadcaster callbacks
        await messageEventBroadcaster.wireServices(
            services,
            onConversationsChanged: { [weak self] in
                self?.conversationsVersion += 1
            },
            onReactionReceived: { [weak self] messageID in
                await self?.handleReactionNotification(messageID: messageID)
            }
        )

        // Increment version to trigger UI refresh in views observing this
        servicesVersion += 1

        // Set up notification center delegate and check authorization
        UNUserNotificationCenter.current().delegate = services.notificationService
        await services.notificationService.setup()

        // Wire notification string provider for localized discovery notifications
        services.notificationService.setStringProvider(NotificationStringProviderImpl())

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
            await donateDeviceMenuTipIfOnValidTab()
        }
    }

    /// Donates the tip if on a valid tab, otherwise marks it pending.
    /// Thin coordinator that reads from both navigation and onboarding concerns.
    func donateDeviceMenuTipIfOnValidTab() async {
        if navigation.isOnValidTabForDeviceMenuTip {
            navigation.pendingDeviceMenuTipDonation = false
            await DeviceMenuTip.hasCompletedOnboarding.donate()
        } else {
            navigation.pendingDeviceMenuTipDonation = true
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

        // Navigation-related notification tap handlers (delegated to NavigationCoordinator)
        navigation.configureNotificationHandlers(
            notificationService: services.notificationService,
            dataStore: services.dataStore,
            connectedDevice: { [weak self] in self?.connectedDevice }
        )

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
