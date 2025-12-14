import Foundation
import OSLog

/// Service for room server interactions.
/// Handles joining rooms, posting messages, and receiving room messages.
public actor RoomServerService {

    // MARK: - Properties

    private let remoteNodeService: RemoteNodeService
    private let bleTransport: any BLETransport
    private let dataStore: DataStore
    private let logger = Logger(subsystem: "com.pocketmesh", category: "RoomServer")

    /// Self public key prefix for author comparison.
    /// Set from SelfInfo when device connects.
    private var selfPublicKeyPrefix: Data?

    /// Handler for incoming room messages
    public var roomMessageHandler: (@Sendable (RoomMessageDTO) async -> Void)?

    // MARK: - Initialization

    public init(
        remoteNodeService: RemoteNodeService,
        bleTransport: any BLETransport,
        dataStore: DataStore
    ) {
        self.remoteNodeService = remoteNodeService
        self.bleTransport = bleTransport
        self.dataStore = dataStore
    }

    /// Set self public key prefix from SelfInfo.
    /// Call this when device info is received.
    public func setSelfPublicKeyPrefix(_ prefix: Data) {
        self.selfPublicKeyPrefix = prefix.prefix(4)
    }

    // MARK: - Room Management

    /// Join a room server by creating a session and authenticating.
    /// - Parameters:
    ///   - deviceID: The companion radio device ID
    ///   - contact: The room server contact
    ///   - password: Authentication password
    ///   - rememberPassword: Whether to store password in keychain
    ///   - pathLength: Path length for timeout calculation (0 = direct)
    /// - Returns: The authenticated session
    public func joinRoom(
        deviceID: UUID,
        contact: ContactDTO,
        password: String,
        rememberPassword: Bool = true,
        pathLength: UInt8 = 0
    ) async throws -> RemoteNodeSessionDTO {
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: contact,
            password: password,
            rememberPassword: rememberPassword
        )

        // Login to the room with appropriate timeout
        _ = try await remoteNodeService.login(
            sessionID: session.id,
            password: password,
            pathLength: pathLength
        )

        guard let updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id) else {
            throw RemoteNodeError.sessionNotFound
        }
        return updatedSession
    }

    /// Leave a room by sending logout and removing the session.
    /// - Parameters:
    ///   - sessionID: The session to leave
    ///   - publicKey: The room's public key (for keychain cleanup)
    public func leaveRoom(sessionID: UUID, publicKey: Data) async throws {
        // Send explicit logout before removing session
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
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        guard session.canPost else {
            throw RemoteNodeError.permissionDenied
        }

        let timestamp = UInt32(Date().timeIntervalSince1970)

        let frameData = FrameCodec.encodeSendTextMessage(
            textType: .plain,
            attempt: 1,
            timestamp: timestamp,
            recipientKeyPrefix: session.publicKeyPrefix,
            text: text
        )

        guard let response = try await bleTransport.send(frameData) else {
            throw RemoteNodeError.sendFailed("No response")
        }

        guard response.first == ResponseCode.sent.rawValue else {
            throw RemoteNodeError.sendFailed("Send rejected")
        }

        // Create local message record immediately
        // Room server won't push this message back to us
        let messageDTO = RoomMessageDTO(
            sessionID: sessionID,
            authorKeyPrefix: selfPublicKeyPrefix ?? Data(repeating: 0, count: 4),
            authorName: "Me",
            text: text,
            timestamp: timestamp,
            isFromSelf: true
        )

        try await dataStore.saveRoomMessage(messageDTO)

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
    public func handleIncomingMessage(
        senderPublicKeyPrefix: Data,
        timestamp: UInt32,
        authorPrefix: Data,
        text: String
    ) async throws {
        // Find session by room server's key prefix
        guard let session = try await dataStore.fetchRemoteNodeSessionByPrefix(senderPublicKeyPrefix),
              session.isRoom else {
            return  // Not from a known room
        }

        // Generate deduplication key
        let dedupKey = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        // Check for duplicate using deduplication key
        if try await dataStore.isDuplicateRoomMessage(
            sessionID: session.id,
            deduplicationKey: dedupKey
        ) {
            return
        }

        // Defensive check: room servers shouldn't push our own messages back
        let isFromSelf = selfPublicKeyPrefix?.prefix(4) == authorPrefix.prefix(4)
        if isFromSelf {
            logger.debug("Received self message from room server (unexpected)")
        }

        let authorName = try await resolveAuthorName(keyPrefix: authorPrefix)

        let messageDTO = RoomMessageDTO(
            sessionID: session.id,
            authorKeyPrefix: authorPrefix,
            authorName: authorName,
            text: text,
            timestamp: timestamp,
            isFromSelf: isFromSelf
        )

        try await dataStore.saveRoomMessage(messageDTO)

        // Increment unread count if not from self
        if !isFromSelf {
            try await dataStore.incrementRoomUnreadCount(session.id)
        }

        await roomMessageHandler?(messageDTO)
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
        guard let session = try await dataStore.fetchRemoteNodeSessionByPrefix(publicKeyPrefix),
              session.isRoom && session.isConnected else {
            return nil
        }
        return session
    }

    // MARK: - Private Helpers

    private func resolveAuthorName(keyPrefix: Data) async throws -> String? {
        // Try to find contact with matching public key prefix
        // Returns nil if no matching contact found
        try await dataStore.findContactNameByKeyPrefix(keyPrefix)
    }
}
