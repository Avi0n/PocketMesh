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

    private let logger = Logger(subsystem: "com.pocketmesh.services", category: "SyncCoordinator")

    // MARK: - Observable State (@MainActor for SwiftUI)

    /// Current sync state
    @MainActor public private(set) var state: SyncState = .idle

    /// Incremented when contacts data changes
    @MainActor public private(set) var contactsVersion: Int = 0

    /// Incremented when conversations data changes
    @MainActor public private(set) var conversationsVersion: Int = 0

    /// Last successful sync date
    @MainActor public private(set) var lastSyncDate: Date?

    // MARK: - Initialization

    public init() {}

    // MARK: - State Setters

    @MainActor
    private func setState(_ newState: SyncState) {
        state = newState
    }

    @MainActor
    private func setLastSyncDate(_ date: Date) {
        lastSyncDate = date
    }

    // MARK: - Notifications

    /// Notify that contacts data changed (triggers UI refresh)
    @MainActor
    public func notifyContactsChanged() {
        contactsVersion += 1
    }

    /// Notify that conversations data changed (triggers UI refresh)
    @MainActor
    public func notifyConversationsChanged() {
        conversationsVersion += 1
    }

    // MARK: - Full Sync

    /// Performs full sync of contacts, channels, and messages from device.
    ///
    /// This is the core sync method that ensures all data is pulled from the device.
    /// It syncs in order: contacts → channels → messages.
    ///
    /// - Parameters:
    ///   - deviceID: The connected device UUID
    ///   - contactService: Service for contact sync
    ///   - channelService: Service for channel sync
    ///   - messagePollingService: Service for message polling
    public func performFullSync(
        deviceID: UUID,
        contactService: ContactService,
        channelService: ChannelService,
        messagePollingService: MessagePollingService
    ) async throws {
        logger.info("Starting full sync for device \(deviceID)")

        // Phase 1: Contacts
        await setState(.syncing(progress: SyncProgress(phase: .contacts, current: 0, total: 0)))
        let contactResult = try await contactService.syncContacts(deviceID: deviceID)
        logger.info("Synced \(contactResult.contactsReceived) contacts")

        // Phase 2: Channels
        await setState(.syncing(progress: SyncProgress(phase: .channels, current: 0, total: 0)))
        let channelResult = try await channelService.syncChannels(deviceID: deviceID)
        logger.info("Synced \(channelResult.channelsSynced) channels")

        // Phase 3: Messages (the missing piece in the old sync!)
        await setState(.syncing(progress: SyncProgress(phase: .messages, current: 0, total: 0)))
        let messageCount = try await messagePollingService.pollAllMessages()
        logger.info("Polled \(messageCount) messages")

        // Complete
        await setState(.synced)
        await setLastSyncDate(Date())

        // Notify UI
        await notifyContactsChanged()
        await notifyConversationsChanged()

        logger.info("Full sync complete")
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
    public func onConnectionEstablished(deviceID: UUID, services: ServiceContainer) async throws {
        logger.info("Connection established for device \(deviceID)")

        // 1. Wire message handlers FIRST (before events can arrive)
        await wireMessageHandlers(services: services, deviceID: deviceID)

        // 2. NOW start event monitoring (handlers are ready)
        await services.startEventMonitoring(deviceID: deviceID)

        // 3. Perform full sync
        try await performFullSync(
            deviceID: deviceID,
            contactService: services.contactService,
            channelService: services.channelService,
            messagePollingService: services.messagePollingService
        )

        // 4. Wire discovery handlers (for ongoing contact discovery)
        await wireDiscoveryHandlers(services: services, deviceID: deviceID)

        logger.info("Connection setup complete for device \(deviceID)")
    }

    /// Called when disconnecting from device
    public func onDisconnected() async {
        await setState(.idle)
        logger.info("Disconnected, sync state reset to idle")
    }

    // MARK: - Message Handler Wiring

    private func wireMessageHandlers(services: ServiceContainer, deviceID: UUID) async {
        logger.debug("Wiring message handlers for device \(deviceID)")

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
                try await services.dataStore.saveMessage(messageDTO)

                // Update contact's last message date and unread count
                if let contactID = contact?.id {
                    try await services.dataStore.updateContactLastMessage(contactID: contactID, date: Date())
                    try await services.dataStore.incrementUnreadCount(contactID: contactID)
                }

                // Post notification (only for known contacts)
                if let contactID = contact?.id {
                    await services.notificationService.postDirectMessageNotification(
                        from: contact?.displayName ?? "Unknown",
                        contactID: contactID,
                        messageText: message.text,
                        messageID: messageDTO.id
                    )
                }
                await services.notificationService.updateBadgeCount()

                // Notify UI via SyncCoordinator
                await self.notifyConversationsChanged()
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
                try await services.dataStore.saveMessage(messageDTO)

                // Update channel's last message date and unread count
                if let channelID = channel?.id {
                    try await services.dataStore.updateChannelLastMessage(channelID: channelID, date: Date())
                    try await services.dataStore.incrementChannelUnreadCount(channelID: channelID)
                }

                // Post notification
                await services.notificationService.postChannelMessageNotification(
                    channelName: channel?.name ?? "Channel \(message.channelIndex)",
                    channelIndex: message.channelIndex,
                    deviceID: deviceID,
                    senderName: senderNodeName,
                    messageText: messageText,
                    messageID: messageDTO.id
                )
                await services.notificationService.updateBadgeCount()

                // Notify UI via SyncCoordinator
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
        logger.debug("Wiring discovery handlers for device \(deviceID)")

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
        // When auto-add is enabled, device sends sync requests after discovering new contacts
        // We debounce these by syncing contacts and notifying UI
        await services.advertisementService.setContactSyncRequestHandler { [weak self] _ in
            guard let self else { return }

            do {
                _ = try await services.contactService.syncContacts(deviceID: deviceID)
                await self.notifyContactsChanged()
            } catch {
                self.logger.warning("Auto-sync after discovery failed: \(error.localizedDescription)")
            }
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
