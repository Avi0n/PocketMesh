// SyncCoordinator.swift
import Foundation
import OSLog

// MARK: - Sync Types

/// Current state of the sync coordinator
public enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: SyncProgress)
    case synced
    case failed(SyncCoordinatorError)

    /// Whether currently syncing
    public var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    public static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.synced, .synced): return true
        case (.syncing(let a), .syncing(let b)): return a == b
        case (.failed, .failed): return true  // Simplified equality
        default: return false
        }
    }
}

/// Progress information during sync
public struct SyncProgress: Sendable, Equatable {
    public let phase: SyncPhase
    public let current: Int
    public let total: Int

    public init(phase: SyncPhase, current: Int, total: Int) {
        self.phase = phase
        self.current = current
        self.total = total
    }
}

/// Phases of the sync process
public enum SyncPhase: Sendable, Equatable {
    case contacts
    case channels
    case messages
}

/// Errors from SyncCoordinator operations
public enum SyncCoordinatorError: Error, Sendable {
    case notConnected
    case syncFailed(String)
    case alreadySyncing
}

// MARK: - SyncCoordinator Actor

/// Coordinates data synchronization between MeshCore device and local database.
///
/// SyncCoordinator owns:
/// - Handler wiring (before event monitoring starts)
/// - Event monitoring lifecycle
/// - Full sync (contacts, channels, messages)
/// - UI refresh notifications
public actor SyncCoordinator {

    // MARK: - Logging

    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "SyncCoordinator")

    /// In-memory cache for message deduplication
    private let deduplicationCache = MessageDeduplicationCache()

    /// Cached blocked contact names for O(1) lookup in message handlers
    private var blockedContactNames: Set<String> = []

    /// Tracks unresolved channel indices that generated notifications in this connection session.
    private var unresolvedChannelIndices: Set<UInt8> = []
    private var lastUnresolvedChannelSummaryAt: Date?
    private let unresolvedChannelSummaryIntervalSeconds: TimeInterval = 60

    /// Timestamp window size (in seconds) for matching reactions to messages.
    /// Allows for clock drift and delayed delivery within a 5-minute window.
    private let reactionTimestampWindowSeconds: UInt32 = 300

    // MARK: - Observable State (@MainActor for SwiftUI)

    /// Current sync state
    @MainActor public private(set) var state: SyncState = .idle

    /// Incremented when contacts data changes
    @MainActor public private(set) var contactsVersion: Int = 0

    /// Incremented when conversations data changes
    @MainActor public private(set) var conversationsVersion: Int = 0

    /// Last successful sync date
    @MainActor public private(set) var lastSyncDate: Date?

    /// Callback when non-message sync activity starts
    private var onSyncActivityStarted: (@Sendable () async -> Void)?

    /// Callback when non-message sync activity ends
    private var onSyncActivityEnded: (@Sendable () async -> Void)?

    /// Tracks whether onSyncActivityEnded has been called for the current sync cycle.
    /// Prevents double-callback when disconnect occurs mid-sync (both onDisconnected
    /// and error path would otherwise call onSyncActivityEnded).
    private var hasEndedSyncActivity = true

    /// Watchdog task that force-clears notification suppression after 120s.
    /// Prevents stuck suppression if sync completes abnormally without clearing it.
    private var suppressionWatchdogTask: Task<Void, Never>?

    /// Callback when sync phase changes (for SwiftUI observation)
    /// nonisolated(unsafe) because it's set once during wiring and only called from @MainActor methods
    nonisolated(unsafe) private var onPhaseChanged: (@Sendable @MainActor (_ phase: SyncPhase?) -> Void)?

    /// Callback when contacts data changes (for SwiftUI observation)
    /// nonisolated(unsafe) because it's set once during wiring and only called from @MainActor methods
    nonisolated(unsafe) private var onContactsChanged: (@Sendable @MainActor () -> Void)?

    /// Callback when conversations data changes (for SwiftUI observation)
    /// nonisolated(unsafe) because it's set once during wiring and only called from @MainActor methods
    nonisolated(unsafe) private var onConversationsChanged: (@Sendable @MainActor () -> Void)?

    /// Callback when a direct message is received (for MessageEventBroadcaster)
    private var onDirectMessageReceived: (@Sendable (_ message: MessageDTO, _ contact: ContactDTO) async -> Void)?

    /// Callback when a channel message is received (for MessageEventBroadcaster)
    private var onChannelMessageReceived: (@Sendable (_ message: MessageDTO, _ channelIndex: UInt8) async -> Void)?

    /// Callback when a room message is received (for MessageEventBroadcaster)
    private var onRoomMessageReceived: (@Sendable (_ message: RoomMessageDTO) async -> Void)?

    /// Callback when a reaction is received for a channel message
    private var onReactionReceived: (@Sendable (_ messageID: UUID, _ summary: String) async -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - State Setters

    @MainActor
    private func setState(_ newState: SyncState) {
        state = newState
        if case .syncing(let progress) = newState {
            onPhaseChanged?(progress.phase)
        } else {
            onPhaseChanged?(nil)
        }
    }

    @MainActor
    private func setLastSyncDate(_ date: Date) {
        lastSyncDate = date
    }

    /// Sets callbacks for sync activity tracking (used by UI to show syncing pill)
    /// Only called for contacts and channels phases, NOT for messages.
    public func setSyncActivityCallbacks(
        onStarted: @escaping @Sendable () async -> Void,
        onEnded: @escaping @Sendable () async -> Void,
        onPhaseChanged: @escaping @Sendable @MainActor (_ phase: SyncPhase?) -> Void
    ) {
        onSyncActivityStarted = onStarted
        onSyncActivityEnded = onEnded
        self.onPhaseChanged = onPhaseChanged
    }

    /// Sets callbacks for data change notifications (used by AppState for SwiftUI observation)
    public func setDataChangeCallbacks(
        onContactsChanged: @escaping @Sendable @MainActor () -> Void,
        onConversationsChanged: @escaping @Sendable @MainActor () -> Void
    ) {
        self.onContactsChanged = onContactsChanged
        self.onConversationsChanged = onConversationsChanged
    }

    /// Sets callbacks for message events (used by AppState for MessageEventBroadcaster)
    public func setMessageEventCallbacks(
        onDirectMessageReceived: @escaping @Sendable (_ message: MessageDTO, _ contact: ContactDTO) async -> Void,
        onChannelMessageReceived: @escaping @Sendable (_ message: MessageDTO, _ channelIndex: UInt8) async -> Void,
        onRoomMessageReceived: @escaping @Sendable (_ message: RoomMessageDTO) async -> Void,
        onReactionReceived: @escaping @Sendable (_ messageID: UUID, _ summary: String) async -> Void
    ) {
        self.onDirectMessageReceived = onDirectMessageReceived
        self.onChannelMessageReceived = onChannelMessageReceived
        self.onRoomMessageReceived = onRoomMessageReceived
        self.onReactionReceived = onReactionReceived
    }

    // MARK: - Sync Activity Tracking

    /// Calls onSyncActivityEnded at most once per sync cycle.
    /// Guards against double-callback when disconnect occurs mid-sync.
    private func endSyncActivityOnce() async {
        guard !hasEndedSyncActivity else { return }
        hasEndedSyncActivity = true
        logger.info("[Sync] Calling onSyncActivityEnded")
        await onSyncActivityEnded?()
    }

    // MARK: - Notification Suppression Watchdog

    private func startSuppressionWatchdog(services: ServiceContainer) {
        suppressionWatchdogTask?.cancel()
        suppressionWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self else { return }
            let isSuppressing = await services.notificationService.isSuppressingNotifications
            guard isSuppressing else { return }
            self.logger.warning("[Sync] Notification suppression watchdog fired after 120s - force clearing")
            await MainActor.run {
                services.notificationService.isSuppressingNotifications = false
            }
        }
    }

    private func cancelSuppressionWatchdog() {
        suppressionWatchdogTask?.cancel()
        suppressionWatchdogTask = nil
    }

    // MARK: - Notifications

    /// Notify that contacts data changed (triggers UI refresh)
    @MainActor
    public func notifyContactsChanged() {
        logger.info("notifyContactsChanged: version \(self.contactsVersion) → \(self.contactsVersion + 1)")
        contactsVersion += 1
        onContactsChanged?()
    }

    /// Notify that conversations data changed (triggers UI refresh)
    @MainActor
    public func notifyConversationsChanged() {
        conversationsVersion += 1
        onConversationsChanged?()
    }

    // MARK: - Blocked Contacts Cache

    /// Refresh the blocked contacts cache from the data store
    public func refreshBlockedContactsCache(deviceID: UUID, dataStore: any PersistenceStoreProtocol) async {
        do {
            let blockedContacts = try await dataStore.fetchBlockedContacts(deviceID: deviceID)
            blockedContactNames = Set(blockedContacts.map(\.name))
            logger.debug("Refreshed blocked contacts cache: \(self.blockedContactNames.count) entries")
        } catch {
            logger.error("Failed to refresh blocked contacts cache: \(error)")
            blockedContactNames = []
        }
    }

    /// Invalidate the blocked contacts cache (call when block status changes)
    public func invalidateBlockedContactsCache() {
        blockedContactNames = []
        logger.debug("Invalidated blocked contacts cache")
    }

    /// Check if a sender name is blocked (O(1) lookup)
    public func isBlockedSender(_ name: String?) -> Bool {
        guard let name else { return false }
        return blockedContactNames.contains(name)
    }

    private func logPostSyncChannelDiagnostics(deviceID: UUID, dataStore: PersistenceStore) async {
        do {
            let channels = try await dataStore.fetchChannels(deviceID: deviceID)
            let emptyNameWithSecretIndices = channels
                .filter { $0.name.isEmpty && $0.hasSecret }
                .map(\.index)
                .sorted()
            logger.info(
                "Post-sync channel diagnostics: total=\(channels.count), emptyNameWithSecret=\(emptyNameWithSecretIndices.count)"
            )
            if !emptyNameWithSecretIndices.isEmpty {
                logger.warning(
                    "Post-sync channels with empty names and non-zero secrets: \(emptyNameWithSecretIndices)"
                )
            }
        } catch {
            logger.error("Failed to compute post-sync channel diagnostics: \(error)")
        }
    }

    private func refreshRxLogChannels(
        deviceID: UUID,
        dataStore: PersistenceStore,
        rxLogService: RxLogService
    ) async {
        do {
            let channels = try await dataStore.fetchChannels(deviceID: deviceID)
            let secrets = Dictionary(uniqueKeysWithValues: channels.map { ($0.index, $0.secret) })
            let names = Dictionary(uniqueKeysWithValues: channels.map { ($0.index, $0.name) })
            await rxLogService.updateChannels(secrets: secrets, names: names)
            logger.debug("Refreshed RxLogService channel cache with \(channels.count) channels")
        } catch {
            logger.error("Failed to refresh RxLogService channel cache: \(error)")
        }
    }

    private func recordUnresolvedChannelNotification(
        channelIndex: UInt8,
        deviceID: UUID,
        senderTimestamp: UInt32
    ) {
        let isNewIndex = unresolvedChannelIndices.insert(channelIndex).inserted
        logger.warning(
            "Posting notification for unresolved channel \(channelIndex) on device \(deviceID), senderTimestamp: \(senderTimestamp)"
        )

        let now = Date()
        let shouldEmitSummary: Bool
        if isNewIndex {
            shouldEmitSummary = true
        } else if let lastSummary = lastUnresolvedChannelSummaryAt {
            shouldEmitSummary = now.timeIntervalSince(lastSummary) >= unresolvedChannelSummaryIntervalSeconds
        } else {
            shouldEmitSummary = true
        }

        guard shouldEmitSummary else { return }
        let sortedIndices = unresolvedChannelIndices.sorted()
        logger.warning(
            "Unresolved channel notification summary: total=\(sortedIndices.count), indices=\(sortedIndices)"
        )
        lastUnresolvedChannelSummaryAt = now
    }

    // MARK: - Full Sync

    /// Performs full sync of contacts, channels, and messages from device.
    ///
    /// This is the core sync method that ensures all data is pulled from the device.
    /// It syncs in order: contacts → channels → messages.
    ///
    /// - Parameters:
    ///   - deviceID: The connected device UUID
    ///   - dataStore: Persistence store for data operations
    ///   - contactService: Service for contact sync
    ///   - channelService: Service for channel sync
    ///   - messagePollingService: Service for message polling
    ///   - appStateProvider: Optional provider for foreground/background state. When nil,
    ///     defaults to foreground mode (channels sync). When provided and app is backgrounded,
    ///     channel sync is skipped to reduce BLE traffic.
    ///   - rxLogService: Optional service for updating contact public keys after sync.
    ///   - forceFullSync: When true, ignores lastContactSync watermark and fetches all contacts.
    public func performFullSync(
        deviceID: UUID,
        dataStore: PersistenceStore,
        contactService: some ContactServiceProtocol,
        channelService: some ChannelServiceProtocol,
        messagePollingService: some MessagePollingServiceProtocol,
        appStateProvider: AppStateProvider? = nil,
        rxLogService: RxLogService? = nil,
        forceFullSync: Bool = false
    ) async throws {
        // Prevent concurrent syncs - check before logging to avoid noise
        let currentState = await state
        if currentState.isSyncing {
            logger.warning("performFullSync called while already syncing, ignoring duplicate")
            return
        }

        logger.info("Starting full sync for device \(deviceID)")

        do {
            // Set phase before triggering pill visibility
            await setState(.syncing(progress: SyncProgress(phase: .contacts, current: 0, total: 0)))
            hasEndedSyncActivity = false
            logger.info("[Sync] Calling onSyncActivityStarted")
            await onSyncActivityStarted?()

            // Perform contacts and channels sync (activity should show pill)
            do {
                // Fetch device once for both contacts (lastContactSync) and channels (maxChannels)
                let device = try await dataStore.fetchDevice(id: deviceID)

                // Phase 1: Contacts (incremental unless forced full)
                logger.info("[Sync] Phase start: contacts")
                let lastContactSync: Date? = forceFullSync ? nil : {
                    guard let timestamp = device?.lastContactSync, timestamp > 0 else { return nil }
                    return Date(timeIntervalSince1970: Double(timestamp))
                }()

                let contactResult = try await contactService.syncContacts(deviceID: deviceID, since: lastContactSync)
                let syncType = contactResult.isIncremental ? "incremental" : "full"
                let forced = forceFullSync ? ", forced" : ""
                logger.info("[Sync] Phase end: contacts - \(contactResult.contactsReceived) (\(syncType)\(forced))")
                await notifyContactsChanged()

                // Update lastContactSync watermark for future incremental syncs
                if contactResult.lastSyncTimestamp > 0 {
                    try await dataStore.updateDeviceLastContactSync(
                        deviceID: deviceID,
                        timestamp: contactResult.lastSyncTimestamp
                    )
                }

                // Update RxLogService with contact public keys for direct message decryption
                if let rxLogService {
                    do {
                        let publicKeys = try await dataStore.fetchContactPublicKeysByPrefix(deviceID: deviceID)
                        await rxLogService.updateContactPublicKeys(publicKeys)
                        logger.debug("Updated \(publicKeys.count) contact public keys for direct message decryption")
                    } catch {
                        logger.error("Failed to fetch contact public keys: \(error)")
                    }
                }

                // Phase 2: Channels (foreground only)
                logger.debug("About to check foreground state, provider exists: \(appStateProvider != nil)")
                let shouldSyncChannels: Bool
                if let provider = appStateProvider {
                    logger.debug("Calling isInForeground...")
                    shouldSyncChannels = await provider.isInForeground
                    logger.debug("isInForeground returned: \(shouldSyncChannels)")
                } else {
                    logger.debug("No appStateProvider, defaulting to foreground mode")
                    shouldSyncChannels = true
                }
                logger.debug("Proceeding with shouldSyncChannels=\(shouldSyncChannels)")
                if shouldSyncChannels {
                    logger.info("[Sync] Phase start: channels")
                    await setState(.syncing(progress: SyncProgress(phase: .channels, current: 0, total: 0)))
                    let maxChannels = device?.maxChannels ?? 0

                    let channelResult = try await channelService.syncChannels(deviceID: deviceID, maxChannels: maxChannels)
                    logger.info("[Sync] Phase end: channels - \(channelResult.channelsSynced) synced (device capacity: \(maxChannels))")

                    // Retry failed channels once if there are retryable errors
                    if !channelResult.isComplete {
                        let retryableIndices = channelResult.retryableIndices
                        if !retryableIndices.isEmpty {
                            logger.info("Retrying \(retryableIndices.count) failed channels")
                            let retryResult = try await channelService.retryFailedChannels(
                                deviceID: deviceID,
                                indices: retryableIndices
                            )

                            if retryResult.isComplete {
                                logger.info("Retry recovered \(retryResult.channelsSynced) channels")
                            } else {
                                logger.warning("Channels still failing after retry: \(retryResult.errors.map { $0.index })")
                            }
                        }
                    }

                    await logPostSyncChannelDiagnostics(deviceID: deviceID, dataStore: dataStore)
                    if let rxLogService {
                        await refreshRxLogChannels(deviceID: deviceID, dataStore: dataStore, rxLogService: rxLogService)
                    }
                } else {
                    logger.info("Skipping channel sync (app in background)")
                }
            } catch {
                // End sync activity on error during contacts/channels phase
                await endSyncActivityOnce()
                throw error
            }

            // End sync activity before messages phase (pill should hide)
            await endSyncActivityOnce()

            // Phase 3: Messages (no pill for this phase)
            logger.info("[Sync] Phase start: messages")
            await setState(.syncing(progress: SyncProgress(phase: .messages, current: 0, total: 0)))
            let messageCount = try await messagePollingService.pollAllMessages()
            logger.info("[Sync] Phase end: messages - \(messageCount) polled")
            await notifyConversationsChanged()

            // Complete
            await setState(.synced)
            await setLastSyncDate(Date())

            logger.info("Full sync complete")
        } catch let error as CancellationError {
            // Defensive: ensure activity count is decremented even if cancellation
            // occurs outside the contacts/channels error path.
            await endSyncActivityOnce()
            await setState(.idle)
            throw error
        } catch {
            // Defensive: ensure activity count is decremented even if an error is
            // thrown from a path that bypasses the inner contacts/channels catch.
            await endSyncActivityOnce()
            await setState(.failed(.syncFailed(error.localizedDescription)))
            throw error
        }
    }

    /// Attempts to resync data after a previous sync failure.
    /// Unlike onConnectionEstablished, does NOT rewire handlers or restart event monitoring.
    /// - Parameters:
    ///   - deviceID: The connected device UUID
    ///   - services: The ServiceContainer with all services
    /// - Returns: `true` if sync succeeded, `false` if it failed
    public func performResync(
        deviceID: UUID,
        services: ServiceContainer,
        forceFullSync: Bool = false
    ) async -> Bool {
        logger.info("Attempting resync for device \(deviceID)")

        await MainActor.run {
            logger.info("Suppressing message notifications during resync")
            services.notificationService.isSuppressingNotifications = true
        }
        startSuppressionWatchdog(services: services)

        do {
            try await performFullSync(
                deviceID: deviceID,
                dataStore: services.dataStore,
                contactService: services.contactService,
                channelService: services.channelService,
                messagePollingService: services.messagePollingService,
                appStateProvider: services.appStateProvider,
                rxLogService: services.rxLogService,
                forceFullSync: forceFullSync
            )

            await wireDiscoveryHandlers(services: services, deviceID: deviceID)

            let pendingHandlerDrainTimeout: Duration = .seconds(2)
            let didDrainPendingHandlers = await services.messagePollingService.waitForPendingHandlers(timeout: pendingHandlerDrainTimeout)
            if !didDrainPendingHandlers {
                logger.warning("Resync: some handlers did not complete in time")
            }

            cancelSuppressionWatchdog()
            await MainActor.run {
                logger.info("Resuming message notifications (resync complete)")
                services.notificationService.isSuppressingNotifications = false
            }

            logger.info("Resync succeeded")
            return true
        } catch {
            let pendingHandlerDrainTimeout: Duration = .seconds(2)
            let didDrainPendingHandlers = await services.messagePollingService.waitForPendingHandlers(timeout: pendingHandlerDrainTimeout)
            if !didDrainPendingHandlers {
                logger.warning("Resync: some handlers did not complete in time (error path)")
            }

            cancelSuppressionWatchdog()
            await MainActor.run {
                logger.info("Resuming message notifications (resync failed)")
                services.notificationService.isSuppressingNotifications = false
            }

            logger.warning("Resync failed: \(error.localizedDescription)")
            await setState(.failed(.syncFailed(error.localizedDescription)))
            return false
        }
    }

    // MARK: - Connection Lifecycle

    /// Called by ConnectionManager when connection is established.
    /// Wires handlers, starts event monitoring, and performs initial sync.
    ///
    /// This is the critical method that fixes the handler wiring gap:
    /// 1. Wire message handlers FIRST (before events can arrive)
    /// 2. Start event monitoring (handlers are now ready)
    /// 3. Perform full sync (contacts, channels, messages)
    /// 4. Wire discovery handlers (for ongoing contact discovery)
    ///
    /// - Parameters:
    ///   - deviceID: The connected device UUID
    ///   - services: The ServiceContainer with all services
    ///   - forceFullSync: When true, forces a full contact sync instead of incremental.
    public func onConnectionEstablished(deviceID: UUID, services: ServiceContainer, forceFullSync: Bool = false) async throws {
        logger.info("Connection established for device \(deviceID)")

        // Prevent duplicate sync if already syncing (race condition during rapid auto-reconnect cycles)
        let currentState = await state
        if currentState.isSyncing {
            logger.warning("onConnectionEstablished called while already syncing, ignoring duplicate")
            return
        }

        // Suppress message notifications during sync to avoid flooding user on reconnect
        // Unread counts and badges still update - only system notifications are suppressed
        await MainActor.run {
            logger.info("Suppressing message notifications during sync")
            services.notificationService.isSuppressingNotifications = true
        }
        startSuppressionWatchdog(services: services)

        do {
            // Defer advert-driven contact fetches during sync to avoid BLE contention
            await services.advertisementService.setSyncingContacts(true)

            // 1. Wire message handlers FIRST (before events can arrive)
            await wireMessageHandlers(services: services, deviceID: deviceID)

            // 2. NOW start event monitoring (handlers are ready), but delay auto-fetch and advert monitoring until after sync
            await services.startEventMonitoring(deviceID: deviceID, enableAutoFetch: false)

            // 3. Export device private key for direct message decryption
            do {
                let privateKey = try await services.session.exportPrivateKey()
                await services.rxLogService.updatePrivateKey(privateKey)
                logger.debug("Device private key exported for direct message decryption")
            } catch {
                logger.warning("Failed to export private key: \(error.localizedDescription)")
            }

            // 4. Perform full sync
            try await performFullSync(
                deviceID: deviceID,
                dataStore: services.dataStore,
                contactService: services.contactService,
                channelService: services.channelService,
                messagePollingService: services.messagePollingService,
                appStateProvider: services.appStateProvider,
                rxLogService: services.rxLogService,
                forceFullSync: forceFullSync
            )

            // 5. Start auto-fetch after full sync to reduce BLE contention
            await services.messagePollingService.startAutoFetch(deviceID: deviceID)

            // 6. Wire discovery handlers (for ongoing contact discovery)
            await wireDiscoveryHandlers(services: services, deviceID: deviceID)

            // 7. Flush deferred advert-driven contact fetches now that handlers are wired
            await services.advertisementService.setSyncingContacts(false)

            // 8. Wait for any pending message handlers to complete
            // Message events are processed asynchronously by the event monitor - we need to ensure
            // all handlers finish before resuming notifications, otherwise sync-time messages
            // may trigger notifications after suppression is lifted
            let pendingHandlerDrainTimeout: Duration = .seconds(2)
            let didDrainPendingHandlers = await services.messagePollingService.waitForPendingHandlers(timeout: pendingHandlerDrainTimeout)
            if !didDrainPendingHandlers {
                logger.warning("Timed out waiting for pending message handlers")
            }

            // Resume notifications on success - synchronously before return
            cancelSuppressionWatchdog()
            await MainActor.run {
                logger.info("Resuming message notifications (sync complete)")
                services.notificationService.isSuppressingNotifications = false
            }

            logger.info("Connection setup complete for device \(deviceID)")
        } catch {
            // Wait for any pending handlers even on error
            let pendingHandlerDrainTimeout: Duration = .seconds(2)
            let didDrainPendingHandlers = await services.messagePollingService.waitForPendingHandlers(timeout: pendingHandlerDrainTimeout)
            if !didDrainPendingHandlers {
                logger.warning("Timed out waiting for pending message handlers")
            }

            // Resume notifications on error - synchronously before throw
            cancelSuppressionWatchdog()
            await MainActor.run {
                logger.info("Resuming message notifications (sync failed)")
                services.notificationService.isSuppressingNotifications = false
            }
            await services.advertisementService.setSyncingContacts(false)
            throw error
        }
    }

    /// Called when disconnecting from device
    ///
    /// If disconnect occurs mid-sync (during contacts or channels phase), we must call
    /// onSyncActivityEnded to decrement the activity count, otherwise the pill stays stuck.
    public func onDisconnected(services: ServiceContainer) async {
        let currentState = await state
        logger.warning(
            "[Sync] onDisconnected called - syncState: \(String(describing: currentState)), hasEndedSyncActivity: \(hasEndedSyncActivity)"
        )

        await deduplicationCache.clear()
        // Note: pending reactions are NOT cleared on disconnect - they persist for the app session
        // This handles temporary BLE disconnects without losing queued reactions
        unresolvedChannelIndices.removeAll()
        lastUnresolvedChannelSummaryAt = nil

        // If we're mid-sync in contacts or channels phase, end the activity to hide the pill
        if case .syncing(let progress) = currentState,
           progress.phase == .contacts || progress.phase == .channels {
            await endSyncActivityOnce()
        }

        await setState(.idle)

        // Safety net: ensure suppression is cleared on disconnect
        // Handles edge cases like connection dropping mid-sync or force-quit
        cancelSuppressionWatchdog()
        await MainActor.run {
            services.notificationService.isSuppressingNotifications = false
        }

        logger.info("Disconnected, sync state reset to idle")
    }

    // MARK: - Message Handler Wiring

    private func wireMessageHandlers(services: ServiceContainer, deviceID: UUID) async {
        logger.info("Wiring message handlers for device \(deviceID)")

        // Populate blocked contacts cache
        await refreshBlockedContactsCache(deviceID: deviceID, dataStore: services.dataStore)

        // Cache device node name for self-mention detection
        let device = try? await services.dataStore.fetchDevice(id: deviceID)
        let selfNodeName = device?.nodeName ?? ""

        // Contact message handler (direct messages)
        await services.messagePollingService.setContactMessageHandler { [weak self] message, contact in
            guard let self else { return }

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            // Correct invalid timestamps (sender clock wrong)
            let receiveTime = Date()
            let (finalTimestamp, timestampCorrected) = Self.correctTimestampIfNeeded(timestamp, receiveTime: receiveTime)
            if timestampCorrected {
                self.logger.debug("Corrected invalid direct message timestamp from \(Date(timeIntervalSince1970: TimeInterval(timestamp))) to \(receiveTime)")
            }

            // Look up path data from RxLogEntry (for direct messages, channelIndex is nil)
            var pathNodes: Data?
            var pathLength = message.pathLength
            do {
                if let rxEntry = try await services.dataStore.findRxLogEntry(
                    channelIndex: nil,
                    senderTimestamp: timestamp,
                    withinSeconds: 10,
                    contactName: contact?.displayName
                ) {
                    pathNodes = rxEntry.pathNodes
                    pathLength = rxEntry.pathLength  // Use RxLogEntry pathLength for consistency
                    self.logger.debug("Correlated incoming direct message to RxLogEntry, pathLength: \(pathLength), pathNodes: \(pathNodes?.count ?? 0) bytes")
                } else {
                    self.logger.debug("No RxLogEntry found for direct message from \(contact?.displayName ?? "unknown")")
                }
            } catch {
                self.logger.error("Failed to lookup RxLogEntry for direct message: \(error)")
            }

            // Check for self-mention before creating DTO
            let hasSelfMention = !selfNodeName.isEmpty &&
                MentionUtilities.containsSelfMention(in: message.text, selfName: selfNodeName)

            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: contact?.id,
                channelIndex: nil,
                text: message.text,
                timestamp: finalTimestamp,
                createdAt: receiveTime,
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: pathLength,
                snr: message.snr,
                pathNodes: pathNodes,
                senderKeyPrefix: message.senderPublicKeyPrefix,
                senderNodeName: nil,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0,
                containsSelfMention: hasSelfMention,
                mentionSeen: false,
                timestampCorrected: timestampCorrected,
                senderTimestamp: timestampCorrected ? timestamp : nil
            )

            // Check for duplicate before saving
            if await self.deduplicationCache.isDuplicateDirectMessage(
                contactID: contact?.id ?? MessageDeduplicationCache.unknownContactID,
                timestamp: timestamp,
                content: message.text
            ) {
                self.logger.info("Skipping duplicate direct message")
                return
            }

            // Check if this is a DM reaction
            if let parsed = ReactionParser.parseDM(message.text),
               let contact {
                // Try to find target in cache first
                if let targetMessageID = await services.reactionService.findDMTargetMessage(
                    messageHash: parsed.messageHash,
                    contactID: contact.id
                ) {
                    let senderName = contact.displayName
                    let exists = try? await services.dataStore.reactionExists(
                        messageID: targetMessageID,
                        senderName: senderName,
                        emoji: parsed.emoji
                    )

                    if exists != true {
                        let reactionDTO = ReactionDTO(
                            messageID: targetMessageID,
                            emoji: parsed.emoji,
                            senderName: senderName,
                            messageHash: parsed.messageHash,
                            rawText: message.text,
                            contactID: contact.id,
                            deviceID: deviceID
                        )
                        if let result = await services.reactionService.persistReactionAndUpdateSummary(
                            reactionDTO,
                            using: services.dataStore
                        ) {
                            await self.onReactionReceived?(result.messageID, result.summary)
                        }

                        self.logger.debug("Saved DM reaction \(parsed.emoji) to message \(targetMessageID)")
                    }

                    return  // Don't save as regular message
                }

                // Try persistence fallback
                let now = UInt32(Date().timeIntervalSince1970)
                let windowStart = now > reactionTimestampWindowSeconds ? now - reactionTimestampWindowSeconds : 0
                let windowEnd = now + reactionTimestampWindowSeconds

                if let targetMessage = try? await services.dataStore.findDMMessageForReaction(
                    deviceID: deviceID,
                    contactID: contact.id,
                    messageHash: parsed.messageHash,
                    timestampWindow: windowStart...windowEnd,
                    limit: 200
                ) {
                    let senderName = contact.displayName
                    let exists = try? await services.dataStore.reactionExists(
                        messageID: targetMessage.id,
                        senderName: senderName,
                        emoji: parsed.emoji
                    )

                    if exists != true {
                        let reactionDTO = ReactionDTO(
                            messageID: targetMessage.id,
                            emoji: parsed.emoji,
                            senderName: senderName,
                            messageHash: parsed.messageHash,
                            rawText: message.text,
                            contactID: contact.id,
                            deviceID: deviceID
                        )
                        if let result = await services.reactionService.persistReactionAndUpdateSummary(
                            reactionDTO,
                            using: services.dataStore
                        ) {
                            await self.onReactionReceived?(result.messageID, result.summary)
                        }

                        self.logger.debug("Saved DM reaction \(parsed.emoji) to message \(targetMessage.id) (from DB)")
                    }

                    return
                }

                // Queue as pending if target not found
                await services.reactionService.queuePendingDMReaction(
                    parsed: parsed,
                    contactID: contact.id,
                    senderName: contact.displayName,
                    rawText: message.text,
                    deviceID: deviceID
                )

                self.logger.debug("Queued pending DM reaction \(parsed.emoji)")
                return  // Don't save as regular message
            }

            do {
                try await services.dataStore.saveMessage(messageDTO)

                // Index DM message for reaction targeting
                if let contact {
                    let pendingMatches = await services.reactionService.indexDMMessage(
                        id: messageDTO.id,
                        contactID: contact.id,
                        text: message.text,
                        timestamp: timestamp
                    )

                    // Process pending reactions that now have their target
                    for pending in pendingMatches {
                        let exists = try? await services.dataStore.reactionExists(
                            messageID: messageDTO.id,
                            senderName: pending.senderName,
                            emoji: pending.parsed.emoji
                        )

                        if exists != true {
                            let reactionDTO = ReactionDTO(
                                messageID: messageDTO.id,
                                emoji: pending.parsed.emoji,
                                senderName: pending.senderName,
                                messageHash: pending.parsed.messageHash,
                                rawText: pending.rawText,
                                contactID: contact.id,
                                deviceID: deviceID
                            )
                            if let result = await services.reactionService.persistReactionAndUpdateSummary(
                                reactionDTO,
                                using: services.dataStore
                            ) {
                                await self.onReactionReceived?(result.messageID, result.summary)
                            }

                            self.logger.debug("Processed pending DM reaction \(pending.parsed.emoji)")
                        }
                    }
                }

                // Update contact's last message date
                if let contactID = contact?.id {
                    try await services.dataStore.updateContactLastMessage(contactID: contactID, date: Date())
                }

                // Only increment unread count, post notification, and update badge for non-blocked contacts
                if let contactID = contact?.id, contact?.isBlocked != true {
                    // Only increment unread if user is NOT currently viewing this contact's chat
                    let isViewingContact = await services.notificationService.activeContactID == contactID
                    if !isViewingContact {
                        try await services.dataStore.incrementUnreadCount(contactID: contactID)

                        // Increment unread mention count if message contains self-mention
                        if hasSelfMention {
                            try await services.dataStore.incrementUnreadMentionCount(contactID: contactID)
                        }
                    }

                    await services.notificationService.postDirectMessageNotification(
                        from: contact?.displayName ?? "Unknown",
                        contactID: contactID,
                        messageText: message.text,
                        messageID: messageDTO.id,
                        isMuted: contact?.isMuted ?? false
                    )
                    await services.notificationService.updateBadgeCount()
                }

                // Notify UI via SyncCoordinator
                await self.notifyConversationsChanged()

                // Notify MessageEventBroadcaster for real-time chat updates
                if let contact {
                    await self.onDirectMessageReceived?(messageDTO, contact)
                }
            } catch {
                self.logger.error("Failed to save contact message: \(error)")
            }
        }

        // Channel message handler
        await services.messagePollingService.setChannelMessageHandler { [weak self] message, channel in
            guard let self else { return }

            // Parse "NodeName: text" format for sender name
            let (senderNodeName, messageText) = Self.parseChannelMessage(message.text)

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            // Correct invalid timestamps (sender clock wrong)
            let receiveTime = Date()
            let (finalTimestamp, timestampCorrected) = Self.correctTimestampIfNeeded(timestamp, receiveTime: receiveTime)
            if timestampCorrected {
                self.logger.debug("Corrected invalid channel message timestamp from \(Date(timeIntervalSince1970: TimeInterval(timestamp))) to \(receiveTime)")
            }

            // Look up path data from RxLogEntry using sender timestamp (stored during decryption)
            var pathNodes: Data?
            var pathLength = message.pathLength
            self.logger.debug("Looking up RxLogEntry for channel \(message.channelIndex) with senderTimestamp: \(timestamp)")
            do {
                if let rxEntry = try await services.dataStore.findRxLogEntry(
                    channelIndex: message.channelIndex,
                    senderTimestamp: timestamp,
                    withinSeconds: 10
                ) {
                    pathNodes = rxEntry.pathNodes
                    pathLength = rxEntry.pathLength  // Use RxLogEntry pathLength for consistency
                    self.logger.info("Correlated channel message to RxLogEntry: pathLength=\(pathLength), pathNodes=\(pathNodes?.count ?? 0) bytes")
                } else {
                    self.logger.warning("No RxLogEntry found for channel \(message.channelIndex), senderTimestamp: \(timestamp)")
                }
            } catch {
                self.logger.error("Failed to lookup RxLogEntry for channel message: \(error)")
            }

            // Check for self-mention before creating DTO
            // Filter out messages where user mentions themselves
            let hasSelfMention = !selfNodeName.isEmpty &&
                senderNodeName != selfNodeName &&
                MentionUtilities.containsSelfMention(in: messageText, selfName: selfNodeName)

            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: nil,
                channelIndex: message.channelIndex,
                text: messageText,
                timestamp: finalTimestamp,
                createdAt: receiveTime,
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: pathLength,
                snr: message.snr,
                pathNodes: pathNodes,
                senderKeyPrefix: nil,
                senderNodeName: senderNodeName,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0,
                containsSelfMention: hasSelfMention,
                mentionSeen: false,
                timestampCorrected: timestampCorrected,
                senderTimestamp: timestampCorrected ? timestamp : nil
            )

            // Check for duplicate before saving
            if await self.deduplicationCache.isDuplicateChannelMessage(
                channelIndex: message.channelIndex,
                timestamp: timestamp,
                username: senderNodeName ?? "",
                content: messageText
            ) {
                self.logger.info("Skipping duplicate channel message")
                return
            }

            // Check if this is a reaction
            if let parsed = services.reactionService.tryProcessAsReaction(messageText) {
                if let targetMessageID = await services.reactionService.findTargetMessage(
                    parsed: parsed,
                    channelIndex: message.channelIndex
                ) {
                    // Check for duplicate
                    let senderName = senderNodeName ?? "Unknown"
                    let exists = try? await services.dataStore.reactionExists(
                        messageID: targetMessageID,
                        senderName: senderName,
                        emoji: parsed.emoji
                    )

                    if exists != true {
                        // Save reaction
                        let reactionDTO = ReactionDTO(
                            messageID: targetMessageID,
                            emoji: parsed.emoji,
                            senderName: senderName,
                            messageHash: parsed.messageHash,
                            rawText: messageText,
                            channelIndex: message.channelIndex,
                            deviceID: deviceID
                        )
                        if let result = await services.reactionService.persistReactionAndUpdateSummary(
                            reactionDTO,
                            using: services.dataStore
                        ) {
                            await self.onReactionReceived?(result.messageID, result.summary)
                        }

                        self.logger.debug("Saved reaction \(parsed.emoji) to message \(targetMessageID)")
                    }

                    return  // Don't save as regular message
                }
                let now = UInt32(receiveTime.timeIntervalSince1970)
                let windowStart = now > reactionTimestampWindowSeconds ? now - reactionTimestampWindowSeconds : 0
                let windowEnd = now + reactionTimestampWindowSeconds

                self.logger.debug("[REACTION-DEBUG] DB lookup: selfNodeName='\(selfNodeName)', targetSender=\(parsed.targetSender), hash=\(parsed.messageHash)")

                if let targetMessage = try? await services.dataStore.findChannelMessageForReaction(
                    deviceID: deviceID,
                    channelIndex: message.channelIndex,
                    parsedReaction: parsed,
                    localNodeName: selfNodeName.isEmpty ? nil : selfNodeName,
                    timestampWindow: windowStart...windowEnd,
                    limit: 200
                ) {
                    let targetMessageID = targetMessage.id
                    let senderName = senderNodeName ?? "Unknown"
                    let exists = try? await services.dataStore.reactionExists(
                        messageID: targetMessageID,
                        senderName: senderName,
                        emoji: parsed.emoji
                    )

                    if exists != true {
                        let reactionDTO = ReactionDTO(
                            messageID: targetMessageID,
                            emoji: parsed.emoji,
                            senderName: senderName,
                            messageHash: parsed.messageHash,
                            rawText: messageText,
                            channelIndex: message.channelIndex,
                            deviceID: deviceID
                        )
                        if let result = await services.reactionService.persistReactionAndUpdateSummary(
                            reactionDTO,
                            using: services.dataStore
                        ) {
                            await self.onReactionReceived?(result.messageID, result.summary)
                        }

                        let targetSenderName: String?
                        if targetMessage.direction == .outgoing {
                            targetSenderName = selfNodeName.isEmpty ? nil : selfNodeName
                        } else {
                            targetSenderName = targetMessage.senderNodeName
                        }

                        if let targetSenderName {
                            // Index for future reactions (pending matches not needed here since
                            // message exists in DB, so pending reactions would also match via DB fallback)
                            _ = await services.reactionService.indexMessage(
                                id: targetMessageID,
                                channelIndex: message.channelIndex,
                                senderName: targetSenderName,
                                text: targetMessage.text,
                                timestamp: targetMessage.reactionTimestamp
                            )
                        }

                        self.logger.debug("Saved reaction \(parsed.emoji) to message \(targetMessageID) via DB lookup")
                    }

                    return  // Don't save as regular message
                }

                // Queue reaction for later matching when target message arrives
                await services.reactionService.queuePendingReaction(
                    parsed: parsed,
                    channelIndex: message.channelIndex,
                    senderNodeName: senderNodeName ?? "Unknown",
                    rawText: messageText,
                    deviceID: deviceID
                )
                return  // Don't save as regular message
            }

            do {
                try await services.dataStore.saveMessage(messageDTO)

                // Index message for reaction matching and process any pending reactions
                // Use original timestamp for indexing so pending reactions can match
                if let senderName = senderNodeName {
                    let pendingMatches = await services.reactionService.indexMessage(
                        id: messageDTO.id,
                        channelIndex: message.channelIndex,
                        senderName: senderName,
                        text: messageText,
                        timestamp: timestamp
                    )

                    // Process any pending reactions that now have their target
                    for pending in pendingMatches {
                        let exists = try? await services.dataStore.reactionExists(
                            messageID: messageDTO.id,
                            senderName: pending.senderNodeName,
                            emoji: pending.parsed.emoji
                        )

                        if exists != true {
                            let reactionDTO = ReactionDTO(
                                messageID: messageDTO.id,
                                emoji: pending.parsed.emoji,
                                senderName: pending.senderNodeName,
                                messageHash: pending.parsed.messageHash,
                                rawText: pending.rawText,
                                channelIndex: pending.channelIndex,
                                deviceID: pending.deviceID
                            )
                            if let result = await services.reactionService.persistReactionAndUpdateSummary(
                                reactionDTO,
                                using: services.dataStore
                            ) {
                                await self.onReactionReceived?(result.messageID, result.summary)
                            }
                        }
                    }
                }

                // Update channel's last message date
                if let channelID = channel?.id {
                    try await services.dataStore.updateChannelLastMessage(channelID: channelID, date: Date())
                }

                // Only update unread count, badges, and notify UI for non-blocked senders
                if await !self.isBlockedSender(senderNodeName) {
                    if let channelID = channel?.id {
                        // Only increment unread if user is NOT currently viewing this channel
                        let activeIndex = await services.notificationService.activeChannelIndex
                        let activeDeviceID = await services.notificationService.activeChannelDeviceID
                        let isViewingChannel = activeIndex == channel?.index && activeDeviceID == channel?.deviceID
                        if !isViewingChannel {
                            try await services.dataStore.incrementChannelUnreadCount(channelID: channelID)

                            // Increment unread mention count if message contains self-mention
                            if hasSelfMention {
                                try await services.dataStore.incrementChannelUnreadMentionCount(channelID: channelID)
                            }
                        }
                    }
                    if channel == nil {
                        await self.recordUnresolvedChannelNotification(
                            channelIndex: message.channelIndex,
                            deviceID: deviceID,
                            senderTimestamp: timestamp
                        )
                    }

                    await services.notificationService.postChannelMessageNotification(
                        channelName: channel?.name ?? "Channel \(message.channelIndex)",
                        channelIndex: message.channelIndex,
                        deviceID: deviceID,
                        senderName: senderNodeName,
                        messageText: messageText,
                        messageID: messageDTO.id,
                        notificationLevel: channel?.notificationLevel ?? .all,
                        hasSelfMention: hasSelfMention
                    )
                    await services.notificationService.updateBadgeCount()

                    // Notify MessageEventBroadcaster for real-time chat updates
                    await self.onChannelMessageReceived?(messageDTO, message.channelIndex)
                }

                // Notify conversation list of changes
                await self.notifyConversationsChanged()
            } catch {
                self.logger.error("Failed to save channel message: \(error)")
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
                let savedMessage = try await services.roomServerService.handleIncomingMessage(
                    senderPublicKeyPrefix: message.senderPublicKeyPrefix,
                    timestamp: timestamp,
                    authorPrefix: Data(authorPrefix),
                    text: message.text
                )

                // If message was saved (not a duplicate), notify UI and post notification
                if let savedMessage {
                    // Fetch session for room name and mute status
                    let session = try? await services.dataStore.fetchRemoteNodeSession(id: savedMessage.sessionID)

                    // Post notification for room message
                    await services.notificationService.postRoomMessageNotification(
                        roomName: session?.name ?? "Room",
                        senderName: savedMessage.authorName,
                        messageText: savedMessage.text,
                        messageID: savedMessage.id,
                        notificationLevel: session?.notificationLevel ?? .all
                    )
                    await services.notificationService.updateBadgeCount()

                    await self.notifyConversationsChanged()
                    await self.onRoomMessageReceived?(savedMessage)
                }
            } catch {
                self.logger.error("Failed to handle room message: \(error)")
            }
        }

        // CLI message handler (repeater admin responses)
        await services.messagePollingService.setCLIMessageHandler { [weak self] message, contact in
            guard let self else { return }

            if let contact {
                await services.repeaterAdminService.invokeCLIHandler(message, fromContact: contact)
            } else {
                self.logger.warning("Dropping CLI response: no contact found for sender")
            }
        }

        logger.info("Message handlers wired successfully")
    }

    // MARK: - Discovery Handler Wiring

    private func wireDiscoveryHandlers(services: ServiceContainer, deviceID: UUID) async {
        logger.info("Wiring discovery handlers for device \(deviceID)")

        // New contact discovered handler (manual-add mode)
        // Posts notification when a new contact is discovered via advertisement
        await services.advertisementService.setNewContactDiscoveredHandler { [weak self] contactName, contactID, contactType in
            guard let self else { return }

            await services.notificationService.postNewContactNotification(
                contactName: contactName,
                contactID: contactID,
                contactType: contactType
            )

            await self.notifyContactsChanged()
        }

        // Contact sync request handler (auto-add mode)
        // AdvertisementService fetches and saves the new contact directly,
        // this handler just triggers UI refresh
        await services.advertisementService.setContactSyncRequestHandler { [weak self] _ in
            guard let self else { return }
            await self.notifyContactsChanged()
        }

        logger.info("Discovery handlers wired successfully")
    }

    // MARK: - Helpers

    private nonisolated static func parseChannelMessage(_ text: String) -> (senderNodeName: String?, messageText: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        if parts.count > 1 {
            let senderName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let messageText = String(parts[1]).trimmingCharacters(in: .whitespaces)
            return (senderName, messageText)
        }
        return (nil, text)
    }

    // MARK: - Timestamp Correction

    /// Maximum acceptable time in the future for a sender timestamp (5 minutes)
    private static let timestampToleranceFuture: TimeInterval = 5 * 60

    /// Maximum acceptable time in the past for a sender timestamp (6 months)
    private static let timestampTolerancePast: TimeInterval = 6 * 30 * 24 * 60 * 60

    /// Corrects invalid timestamps from senders with broken clocks.
    ///
    /// MeshCore protocol does not specify timestamp validation. This is a client-side
    /// policy to prevent timeline corruption when devices have severely incorrect clocks
    /// (a common issue per MeshCore FAQ 6.1, 6.2). Original timestamps are preserved
    /// for ACK deduplication (per payloads.md:65).
    ///
    /// Returns the corrected timestamp and whether correction was applied.
    /// Timestamps are considered invalid if:
    /// - More than 5 minutes in the future (relative to receive time)
    /// - More than 6 months in the past (relative to receive time)
    ///
    /// - Parameters:
    ///   - timestamp: The sender's claimed timestamp
    ///   - receiveTime: When the message was received (defaults to now)
    /// - Returns: Tuple of (corrected timestamp, was corrected flag)
    nonisolated static func correctTimestampIfNeeded(
        _ timestamp: UInt32,
        receiveTime: Date = Date()
    ) -> (correctedTimestamp: UInt32, wasCorrected: Bool) {
        let receiveSeconds = receiveTime.timeIntervalSince1970
        let timestampSeconds = TimeInterval(timestamp)

        let isTooFarInFuture = timestampSeconds > receiveSeconds + timestampToleranceFuture
        let isTooFarInPast = timestampSeconds < receiveSeconds - timestampTolerancePast

        if isTooFarInFuture || isTooFarInPast {
            return (UInt32(receiveSeconds), true)
        }
        return (timestamp, false)
    }
}
