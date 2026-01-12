import Foundation
import MeshCore
import os

// MARK: - Room Server Errors

public enum RoomServerError: Error, Sendable {
    case notConnected
    case sessionNotFound
    case sendFailed(String)
    case permissionDenied
    case invalidResponse
    case sessionError(MeshCoreError)
}

// MARK: - Room Server Service

/// Service for room server interactions.
/// Handles joining rooms, posting messages, and receiving room messages.
public actor RoomServerService {

    // MARK: - Properties

    private let session: MeshCoreSession
    private let remoteNodeService: RemoteNodeService
    private let dataStore: PersistenceStore
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "RoomServer")
    private let auditLogger = CommandAuditLogger()

    /// Self public key prefix for author comparison.
    /// Set from SelfInfo when device connects.
    private var selfPublicKeyPrefix: Data?

    /// Handler for incoming room messages
    public var roomMessageHandler: (@Sendable (RoomMessageDTO) async -> Void)?

    // MARK: - Initialization

    public init(
        session: MeshCoreSession,
        remoteNodeService: RemoteNodeService,
        dataStore: PersistenceStore
    ) {
        self.session = session
        self.remoteNodeService = remoteNodeService
        self.dataStore = dataStore
    }

    /// Set self public key prefix from SelfInfo.
    /// Call this when device info is received.
    public func setSelfPublicKeyPrefix(_ prefix: Data) {
        self.selfPublicKeyPrefix = prefix.prefix(4)
    }

    // MARK: - Handler Setters

    /// Set handler for incoming room messages
    public func setRoomMessageHandler(_ handler: @escaping @Sendable (RoomMessageDTO) async -> Void) {
        roomMessageHandler = handler
    }

    // MARK: - Room Management

    /// Join a room server by creating a session and authenticating.
    /// Automatically syncs message history based on local state.
    /// - Parameters:
    ///   - deviceID: The companion radio device ID
    ///   - contact: The room server contact
    ///   - password: Authentication password (uses keychain if not provided)
    ///   - rememberPassword: Whether to store password in keychain
    ///   - pathLength: Path length for timeout calculation (0 = direct)
    /// - Returns: The authenticated session
    public func joinRoom(
        deviceID: UUID,
        contact: ContactDTO,
        password: String?,
        rememberPassword: Bool = true,
        pathLength: UInt8 = 0
    ) async throws -> RemoteNodeSessionDTO {
        // Check if this is a new session
        let existingSession = try? await dataStore.fetchRemoteNodeSession(publicKey: contact.publicKey)
        let isNewSession = existingSession == nil

        // Determine sync start point (used after login for history sync)
        let needsFullSync = existingSession == nil || existingSession?.lastSyncTimestamp == 0
        let syncSince: UInt32 = needsFullSync ? 1 : (existingSession?.lastSyncTimestamp ?? 1)

        let remoteSession = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: contact,
            password: password,
            rememberPassword: rememberPassword
        )

        // Login to the room
        _ = try await remoteNodeService.login(
            sessionID: remoteSession.id,
            password: password,
            pathLength: pathLength
        )

        // Store password only after successful login
        if let password, rememberPassword {
            try await remoteNodeService.storePassword(password, forNodeKey: contact.publicKey)
        }

        // Attempt additional history sync if needed (non-blocking)
        await syncHistoryIfPossible(sessionID: remoteSession.id, since: syncSince)

        guard let updatedSession = try await dataStore.fetchRemoteNodeSession(id: remoteSession.id) else {
            throw RemoteNodeError.sessionNotFound
        }
        return updatedSession
    }

    /// Reconnect to an existing room session and sync any missed messages.
    /// Use this when re-authenticating to a room after app restart or BLE reconnection.
    /// - Parameters:
    ///   - sessionID: The existing room session ID
    ///   - pathLength: Optional path length hint (0 = use shortest known path)
    /// - Returns: Updated session DTO
    /// - Throws: RemoteNodeError if reconnection fails
    public func reconnectRoom(
        sessionID: UUID,
        pathLength: UInt8 = 0
    ) async throws -> RemoteNodeSessionDTO {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        guard remoteSession.isRoom else {
            throw RemoteNodeError.invalidResponse
        }

        // Compute sync timestamp (used after login for history sync)
        let syncSince: UInt32 = remoteSession.lastSyncTimestamp > 0 ? remoteSession.lastSyncTimestamp : 1

        // Re-authenticate to the room
        _ = try await remoteNodeService.login(
            sessionID: sessionID,
            pathLength: pathLength
        )

        // Attempt additional history sync if needed (non-blocking)
        await syncHistoryIfPossible(sessionID: sessionID, since: syncSince)

        guard let updatedSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }
        return updatedSession
    }

    /// Leave a room by sending logout and removing the session.
    /// - Parameters:
    ///   - sessionID: The session to leave
    ///   - publicKey: The room's public key (for keychain cleanup)
    public func leaveRoom(sessionID: UUID, publicKey: Data) async throws {
        try await remoteNodeService.logout(sessionID: sessionID)
        try await remoteNodeService.removeSession(id: sessionID, publicKey: publicKey)
    }

    // MARK: - Message Posting

    /// Post a message to a room server.
    ///
    /// Posts use `TextType.plain`. The room server converts to `signedPlain`
    /// when pushing to other clients. The server does not push messages back
    /// to their authors, so the local message record is created immediately.
    /// - Parameters:
    ///   - sessionID: The room session
    ///   - text: The message text
    /// - Returns: The saved message DTO
    public func postMessage(sessionID: UUID, text: String) async throws -> RoomMessageDTO {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RoomServerError.sessionNotFound
        }

        guard remoteSession.canPost else {
            throw RoomServerError.permissionDenied
        }

        let timestamp = Date()

        // Send message via MeshCore session
        do {
            _ = try await session.sendMessage(
                to: remoteSession.publicKeyPrefix,
                text: text,
                timestamp: timestamp
            )
        } catch let error as MeshCoreError {
            throw RoomServerError.sessionError(error)
        }

        // Log room message posted (metadata only, no content)
        await auditLogger.logRoomMessagePosted(publicKey: remoteSession.publicKey, messageLength: text.count)

        // Create local message record immediately
        // Room server won't push this message back to us
        let messageDTO = RoomMessageDTO(
            sessionID: sessionID,
            authorKeyPrefix: selfPublicKeyPrefix ?? Data(repeating: 0, count: 4),
            authorName: "Me",
            text: text,
            timestamp: UInt32(timestamp.timeIntervalSince1970),
            isFromSelf: true
        )

        try await dataStore.saveRoomMessage(messageDTO)

        // Update sync timestamp with our own message's timestamp
        try await dataStore.updateRoomLastSyncTimestamp(sessionID, timestamp: messageDTO.timestamp)

        return messageDTO
    }

    // MARK: - Incoming Messages

    /// Handle incoming room message.
    /// Called by MessagePollingService when a signedPlain message arrives from a room.
    ///
    /// Messages arrive as `TextType.signedPlain` with the room server's key as
    /// `senderPublicKeyPrefix` and the original author's 4-byte key prefix in
    /// the payload (extracted to `extraData` by `decodeMessageV3`).
    ///
    /// Since room servers don't push messages back to their authors, incoming
    /// messages should not be from self. However, we check defensively.
    /// - Parameters:
    ///   - senderPublicKeyPrefix: The room server's 6-byte key prefix
    ///   - timestamp: Message timestamp from server
    ///   - authorPrefix: The original author's 4-byte key prefix
    ///   - text: The message text
    /// - Returns: The saved message DTO, or nil if the message was a duplicate
    @discardableResult
    public func handleIncomingMessage(
        senderPublicKeyPrefix: Data,
        timestamp: UInt32,
        authorPrefix: Data,
        text: String
    ) async throws -> RoomMessageDTO? {
        // Find session by room server's key prefix
        guard let remoteSession = try await dataStore.fetchRemoteNodeSessionByPrefix(senderPublicKeyPrefix),
              remoteSession.isRoom else {
            return nil  // Not from a known room
        }

        // Generate deduplication key
        let dedupKey = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        // Check for duplicate using deduplication key
        if try await dataStore.isDuplicateRoomMessage(
            sessionID: remoteSession.id,
            deduplicationKey: dedupKey
        ) {
            return nil
        }

        // Log room message received (metadata only, no content)
        await auditLogger.logRoomMessageReceived(
            roomPublicKey: senderPublicKeyPrefix,
            authorPrefix: authorPrefix,
            messageLength: text.count
        )

        // Defensive check: room servers shouldn't push our own messages back
        let isFromSelf = selfPublicKeyPrefix?.prefix(4) == authorPrefix.prefix(4)
        if isFromSelf {
            logger.info("Received self message from room server (unexpected)")
        }

        let authorName = try await resolveAuthorName(keyPrefix: authorPrefix)

        let messageDTO = RoomMessageDTO(
            sessionID: remoteSession.id,
            authorKeyPrefix: authorPrefix,
            authorName: authorName,
            text: text,
            timestamp: timestamp,
            isFromSelf: isFromSelf
        )

        try await dataStore.saveRoomMessage(messageDTO)

        // Update last sync timestamp to track sync progress
        try await dataStore.updateRoomLastSyncTimestamp(remoteSession.id, timestamp: timestamp)

        // Increment unread count if not from self
        if !isFromSelf {
            try await dataStore.incrementRoomUnreadCount(remoteSession.id)
        }

        await roomMessageHandler?(messageDTO)

        return messageDTO
    }

    // MARK: - Message Retrieval

    /// Fetch messages for a room session.
    /// - Parameters:
    ///   - sessionID: The room session ID
    ///   - limit: Maximum number of messages to return
    ///   - offset: Offset for pagination
    /// - Returns: Array of room message DTOs
    public func fetchMessages(sessionID: UUID, limit: Int? = nil, offset: Int? = nil) async throws -> [RoomMessageDTO] {
        try await dataStore.fetchRoomMessages(sessionID: sessionID, limit: limit, offset: offset)
    }

    /// Mark room as read (reset unread count).
    /// Call when user views the conversation.
    /// - Parameter sessionID: The room session ID
    public func markAsRead(sessionID: UUID) async throws {
        try await dataStore.resetRoomUnreadCount(sessionID)
    }

    // MARK: - Session Queries

    /// Fetch all room sessions for a device.
    /// - Parameter deviceID: The companion radio device ID
    /// - Returns: Array of room session DTOs
    public func fetchRoomSessions(deviceID: UUID) async throws -> [RemoteNodeSessionDTO] {
        let sessions = try await dataStore.fetchRemoteNodeSessions(deviceID: deviceID)
        return sessions.filter { $0.isRoom }
    }

    /// Check if a contact is a known room server with an active session.
    /// - Parameter publicKeyPrefix: The 6-byte public key prefix
    /// - Returns: The session if found and connected, nil otherwise
    public func getConnectedSession(publicKeyPrefix: Data) async throws -> RemoteNodeSessionDTO? {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSessionByPrefix(publicKeyPrefix),
              remoteSession.isRoom && remoteSession.isConnected else {
            return nil
        }
        return remoteSession
    }

    // MARK: - Private Helpers

    private func resolveAuthorName(keyPrefix: Data) async throws -> String? {
        // Try to find contact with matching public key prefix
        // Returns nil if no matching contact found
        try await dataStore.findContactNameByKeyPrefix(keyPrefix)
    }

    /// Attempt to sync history, using advert path first, then falling back to path discovery.
    private func syncHistoryIfPossible(sessionID: UUID, since: UInt32) async {
        do {
            guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID),
                  let contact = try await dataStore.findContactByPublicKey(remoteSession.publicKey) else {
                return
            }

            // Strategy:
            // 1. If contact has a path from advertisement (outPathLength >= 0), try it first
            // 2. If that fails or contact is flood-routed, trigger path discovery
            // 3. Wait for discovery result and retry

            if contact.outPathLength >= 0 {
                // Contact has a path from advertisement - try it directly
                logger.info("Trying advert path for room \(remoteSession.name)")
                do {
                    try await remoteNodeService.requestHistorySync(sessionID: sessionID, since: since)
                    logger.info("History sync succeeded using advert path")
                    return
                } catch {
                    // Advert path didn't work - fall through to path discovery
                    logger.info("Advert path failed for \(remoteSession.name): \(error), trying path discovery")
                }
            } else {
                logger.info("Room \(remoteSession.name) is flood-routed, attempting path discovery")
            }

            // Path discovery fallback
            let hasDirectRoute = try await discoverPathAndWait(sessionID: sessionID)
            if !hasDirectRoute {
                logger.info("Could not establish direct route for \(remoteSession.name), skipping history sync")
                return
            }

            // Retry with newly discovered path
            try await remoteNodeService.requestHistorySync(sessionID: sessionID, since: since)
            logger.info("History sync succeeded after path discovery")
        } catch {
            logger.warning("Failed to sync history for session \(sessionID): \(error)")
            // Don't fail the join - messages will arrive via normal flow
        }
    }

    /// Discover path and wait for direct route.
    private func discoverPathAndWait(sessionID: UUID, timeout: Duration = .seconds(10)) async throws -> Bool {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID),
              let contact = try await dataStore.findContactByPublicKey(remoteSession.publicKey) else {
            return false
        }

        // Already direct?
        if contact.outPathLength >= 0 {
            return true
        }

        // Trigger path discovery via MeshCore session
        do {
            _ = try await session.sendPathDiscovery(to: remoteSession.publicKey)
        } catch {
            logger.warning("Path discovery send failed: \(error)")
            return false
        }

        // Wait for result
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(500))

            if let updated = try await dataStore.findContactByPublicKey(remoteSession.publicKey),
               updated.outPathLength >= 0 {
                return true
            }
        }

        return false
    }
}
