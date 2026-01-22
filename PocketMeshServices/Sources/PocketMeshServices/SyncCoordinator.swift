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
        onRoomMessageReceived: @escaping @Sendable (_ message: RoomMessageDTO) async -> Void
    ) {
        self.onDirectMessageReceived = onDirectMessageReceived
        self.onChannelMessageReceived = onChannelMessageReceived
        self.onRoomMessageReceived = onRoomMessageReceived
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
        logger.info("notifyConversationsChanged: version \(self.conversationsVersion) → \(self.conversationsVersion + 1)")
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
            await onSyncActivityStarted?()

            // Perform contacts and channels sync (activity should show pill)
            do {
                // Fetch device once for both contacts (lastContactSync) and channels (maxChannels)
                let device = try await dataStore.fetchDevice(id: deviceID)

                // Phase 1: Contacts (incremental unless forced full)
                let lastContactSync: Date? = forceFullSync ? nil : {
                    guard let timestamp = device?.lastContactSync, timestamp > 0 else { return nil }
                    return Date(timeIntervalSince1970: Double(timestamp))
                }()

                let contactResult = try await contactService.syncContacts(deviceID: deviceID, since: lastContactSync)
                let syncType = contactResult.isIncremental ? "incremental" : "full"
                logger.info("Synced \(contactResult.contactsReceived) contacts (\(syncType)\(forceFullSync ? ", forced" : ""))")
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
                let shouldSyncChannels: Bool
                if let provider = appStateProvider {
                    shouldSyncChannels = await provider.isInForeground
                } else {
                    shouldSyncChannels = true
                }
                if shouldSyncChannels {
                    await setState(.syncing(progress: SyncProgress(phase: .channels, current: 0, total: 0)))
                    let maxChannels = device?.maxChannels ?? 0

                    let channelResult = try await channelService.syncChannels(deviceID: deviceID, maxChannels: maxChannels)
                    logger.info("Synced \(channelResult.channelsSynced) channels (device capacity: \(maxChannels))")

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
                } else {
                    logger.info("Skipping channel sync (app in background)")
                }
            } catch {
                // End sync activity on error during contacts/channels phase
                await onSyncActivityEnded?()
                throw error
            }

            // End sync activity before messages phase (pill should hide)
            await onSyncActivityEnded?()

            // Phase 3: Messages (no pill for this phase)
            await setState(.syncing(progress: SyncProgress(phase: .messages, current: 0, total: 0)))
            let messageCount = try await messagePollingService.pollAllMessages()
            logger.info("Polled \(messageCount) messages")
            await notifyConversationsChanged()

            // Complete
            await setState(.synced)
            await setLastSyncDate(Date())

            logger.info("Full sync complete")
        } catch {
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

        do {
            // 1. Wire message handlers FIRST (before events can arrive)
            await wireMessageHandlers(services: services, deviceID: deviceID)

            // 2. NOW start event monitoring (handlers are ready)
            await services.startEventMonitoring(deviceID: deviceID)

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

            // 5. Wire discovery handlers (for ongoing contact discovery)
            await wireDiscoveryHandlers(services: services, deviceID: deviceID)

            // 6. Wait for any pending message handlers to complete
            // Message events are processed asynchronously by the event monitor - we need to ensure
            // all handlers finish before resuming notifications, otherwise sync-time messages
            // may trigger notifications after suppression is lifted
            let pendingHandlerDrainTimeout: Duration = .seconds(2)
            let didDrainPendingHandlers = await services.messagePollingService.waitForPendingHandlers(timeout: pendingHandlerDrainTimeout)
            if !didDrainPendingHandlers {
                logger.warning("Timed out waiting for pending message handlers")
            }

            // Resume notifications on success - synchronously before return
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
            await MainActor.run {
                logger.info("Resuming message notifications (sync failed)")
                services.notificationService.isSuppressingNotifications = false
            }
            throw error
        }
    }

    /// Called when disconnecting from device
    ///
    /// If disconnect occurs mid-sync (during contacts or channels phase), we must call
    /// onSyncActivityEnded to decrement the activity count, otherwise the pill stays stuck.
    public func onDisconnected(services: ServiceContainer) async {
        await deduplicationCache.clear()

        // If we're mid-sync in contacts or channels phase, end the activity to hide the pill
        let currentState = await state
        if case .syncing(let progress) = currentState,
           progress.phase == .contacts || progress.phase == .channels {
            await onSyncActivityEnded?()
        }

        await setState(.idle)

        // Safety net: ensure suppression is cleared on disconnect
        // Handles edge cases like connection dropping mid-sync or force-quit
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
                timestamp: timestamp,
                createdAt: Date(),
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
                mentionSeen: false
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

            do {
                try await services.dataStore.saveMessage(messageDTO)

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

            // Look up path data from RxLogEntry using sender timestamp (stored during decryption)
            var pathNodes: Data?
            var pathLength = message.pathLength
            self.logger.debug("Looking up RxLogEntry for channel \(channel?.index ?? 255) with senderTimestamp: \(timestamp)")
            do {
                if let rxEntry = try await services.dataStore.findRxLogEntry(
                    channelIndex: channel?.index,
                    senderTimestamp: timestamp,
                    withinSeconds: 10
                ) {
                    pathNodes = rxEntry.pathNodes
                    pathLength = rxEntry.pathLength  // Use RxLogEntry pathLength for consistency
                    self.logger.info("Correlated channel message to RxLogEntry: pathLength=\(pathLength), pathNodes=\(pathNodes?.count ?? 0) bytes")
                } else {
                    self.logger.warning("No RxLogEntry found for channel \(channel?.index ?? 255), senderTimestamp: \(timestamp)")
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
                timestamp: timestamp,
                createdAt: Date(),
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
                mentionSeen: false
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

            do {
                try await services.dataStore.saveMessage(messageDTO)

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

                    await services.notificationService.postChannelMessageNotification(
                        channelName: channel?.name ?? "Channel \(message.channelIndex)",
                        channelIndex: message.channelIndex,
                        deviceID: deviceID,
                        senderName: senderNodeName,
                        messageText: messageText,
                        messageID: messageDTO.id,
                        isMuted: channel?.isMuted ?? false
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
                        isMuted: session?.isMuted ?? false
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
        await services.advertisementService.setNewContactDiscoveredHandler { [weak self] contactName, contactID in
            guard let self else { return }

            await services.notificationService.postNewContactNotification(
                contactName: contactName,
                contactID: contactID
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
}
