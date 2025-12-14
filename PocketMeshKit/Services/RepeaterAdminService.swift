import Foundation
import OSLog

// MARK: - Neighbor Sort Order

/// Sort order options for neighbor queries
public enum NeighborSortOrder: UInt8, Sendable {
    case newestFirst = 0
    case oldestFirst = 1
    case strongestFirst = 2
    case weakestFirst = 3
}

// MARK: - Repeater Admin Service

/// Service for repeater admin interactions.
/// Handles connecting as admin, viewing status/telemetry/neighbors, and sending CLI commands.
public actor RepeaterAdminService {

    // MARK: - Properties

    private let remoteNodeService: RemoteNodeService
    private let binaryProtocol: BinaryProtocolService
    private let dataStore: DataStore
    private let logger = Logger(subsystem: "com.pocketmesh", category: "RepeaterAdmin")

    /// Handler for neighbor responses
    public var neighborsResponseHandler: (@Sendable (NeighboursResponse) async -> Void)?

    /// Handler for telemetry responses
    public var telemetryResponseHandler: (@Sendable (TelemetryResponse) async -> Void)?

    /// Handler for status responses
    public var statusResponseHandler: (@Sendable (RemoteNodeStatus) async -> Void)?

    /// Default pubkey prefix length for neighbor queries.
    /// Stored to ensure response parsing uses matching length.
    public static let defaultPubkeyPrefixLength: UInt8 = 6

    // MARK: - Initialization

    public init(
        remoteNodeService: RemoteNodeService,
        binaryProtocol: BinaryProtocolService,
        dataStore: DataStore
    ) {
        self.remoteNodeService = remoteNodeService
        self.binaryProtocol = binaryProtocol
        self.dataStore = dataStore
    }

    // MARK: - Admin Connection

    /// Connect to a repeater as admin by creating a session and authenticating.
    /// - Parameters:
    ///   - deviceID: The companion radio device ID
    ///   - contact: The repeater contact
    ///   - password: Admin password
    ///   - rememberPassword: Whether to store password in keychain
    ///   - pathLength: Path length for timeout calculation (0 = direct)
    /// - Returns: The authenticated session
    public func connectAsAdmin(
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

        // Login to the repeater with appropriate timeout
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

    /// Disconnect from a repeater by sending logout and removing the session.
    /// - Parameters:
    ///   - sessionID: The session to disconnect
    ///   - publicKey: The repeater's public key (for keychain cleanup)
    public func disconnect(sessionID: UUID, publicKey: Data) async throws {
        // Send explicit logout before removing session
        try await remoteNodeService.logout(sessionID: sessionID)
        try await remoteNodeService.removeSession(id: sessionID, publicKey: publicKey)
    }

    // MARK: - Neighbors (Repeater-Specific)

    /// Request neighbors list from repeater.
    ///
    /// The `pubkeyPrefixLength` parameter must match between request and response
    /// parsing. BinaryProtocolService tracks this in the pending request context.
    /// - Parameters:
    ///   - sessionID: The repeater session ID
    ///   - count: Maximum number of neighbors to return (default 20)
    ///   - offset: Pagination offset
    ///   - orderBy: Sort order for results
    ///   - pubkeyPrefixLength: Length of public key prefix in response
    /// - Returns: Tag data for tracking the request, or nil if send failed
    public func requestNeighbors(
        sessionID: UUID,
        count: UInt8 = 20,
        offset: UInt16 = 0,
        orderBy: NeighborSortOrder = .newestFirst,
        pubkeyPrefixLength: UInt8 = defaultPubkeyPrefixLength
    ) async throws -> Data? {
        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID),
              session.isRepeater else {
            throw RemoteNodeError.sessionNotFound
        }

        // BinaryProtocolService.requestNeighbours stores pubkeyPrefixLength
        // in the pending request context for response parsing
        return try await binaryProtocol.requestNeighbours(
            from: session.publicKey,
            count: count,
            offset: offset,
            pubkeyPrefixLength: pubkeyPrefixLength
        )
    }

    // MARK: - Status

    /// Request status from a repeater.
    /// - Parameter sessionID: The repeater session ID
    /// - Returns: Tag data for tracking the request, or nil if send failed
    public func requestStatus(sessionID: UUID) async throws -> Data? {
        try await remoteNodeService.requestStatus(sessionID: sessionID)
    }

    // MARK: - Telemetry

    /// Request telemetry from a repeater.
    /// Response arrives via push notification.
    /// - Parameter sessionID: The repeater session ID
    public func requestTelemetry(sessionID: UUID) async throws {
        try await remoteNodeService.requestTelemetry(sessionID: sessionID)
    }

    // MARK: - CLI Commands

    /// Send a CLI command to a repeater (admin only).
    /// - Parameters:
    ///   - sessionID: The repeater session ID
    ///   - command: The CLI command string
    /// - Returns: Command response (response handling to be implemented)
    public func sendCommand(sessionID: UUID, command: String) async throws -> String {
        try await remoteNodeService.sendCLICommand(sessionID: sessionID, command: command)
    }

    // MARK: - Session Queries

    /// Fetch all repeater sessions for a device.
    /// - Parameter deviceID: The companion radio device ID
    /// - Returns: Array of repeater session DTOs
    public func fetchRepeaterSessions(deviceID: UUID) async throws -> [RemoteNodeSessionDTO] {
        let sessions = try await dataStore.fetchRemoteNodeSessions(deviceID: deviceID)
        return sessions.filter { $0.isRepeater }
    }

    /// Check if a contact is a known repeater with an active session.
    /// - Parameter publicKeyPrefix: The 6-byte public key prefix
    /// - Returns: The session if found and connected, nil otherwise
    public func getConnectedSession(publicKeyPrefix: Data) async throws -> RemoteNodeSessionDTO? {
        guard let session = try await dataStore.fetchRemoteNodeSessionByPrefix(publicKeyPrefix),
              session.isRepeater && session.isConnected else {
            return nil
        }
        return session
    }
}
