import Foundation
import OSLog

// MARK: - Remote Node Errors

public enum RemoteNodeError: Error, LocalizedError, Sendable {
    case notConnected
    case loginFailed(String)
    case sendFailed(String)
    case invalidResponse
    case permissionDenied
    case timeout
    case sessionNotFound
    case passwordNotFound
    case floodRouted  // Keep-alive requires direct path
    case pathDiscoveryFailed
    case contactNotFound
    case cancelled  // Login cancelled due to duplicate attempt or shutdown

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to mesh device"
        case .loginFailed(let reason):
            return "Login failed: \(reason)"
        case .sendFailed(let reason):
            return "Failed to send: \(reason)"
        case .invalidResponse:
            return "Invalid response from remote node"
        case .permissionDenied:
            return "Permission denied"
        case .timeout:
            return "Request timed out or incorrect password"
        case .sessionNotFound:
            return "Remote node session not found"
        case .passwordNotFound:
            return "Password not found in keychain"
        case .floodRouted:
            return "Keep-alive requires direct routing path"
        case .pathDiscoveryFailed:
            return "Failed to establish direct path"
        case .contactNotFound:
            return "Contact not found in database"
        case .cancelled:
            return "Login cancelled"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timeout, .notConnected, .floodRouted:
            return true
        default:
            return false
        }
    }
}

// MARK: - Login Timeout Configuration

/// Configuration for login timeout based on path length
public enum LoginTimeoutConfig {
    /// Base timeout for direct (0-hop) connections
    public static let directTimeout: Duration = .seconds(5)

    /// Additional timeout per hop in the path
    public static let perHopTimeout: Duration = .seconds(10)

    /// Maximum timeout regardless of path length
    public static let maximumTimeout: Duration = .seconds(60)

    /// Calculate appropriate timeout based on path length
    public static func timeout(forPathLength pathLength: UInt8) -> Duration {
        let base = directTimeout
        let additional = Duration.seconds(Int(pathLength) * 10)
        let total = base + additional
        return min(total, maximumTimeout)
    }
}

// MARK: - Remote Node Service

/// Shared service for remote node operations.
/// Handles login, keep-alive, status, telemetry, and CLI for both room servers and repeaters.
public actor RemoteNodeService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private let binaryProtocol: BinaryProtocolService
    private let dataStore: DataStore
    private let keychainService: any KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.pocketmesh", category: "RemoteNode")

    /// Pending login continuations keyed by 6-byte public key prefix.
    /// Using 6-byte prefix matches MeshCore protocol format for login results.
    /// Collision risk is ~1 in 281 trillion per pair - negligible for practical use.
    private var pendingLogins: [Data: CheckedContinuation<LoginResult, Error>] = [:]

    /// Keep-alive timer tasks
    private var keepAliveTasks: [UUID: Task<Void, Never>] = [:]

    /// Keep-alive intervals per session (from login response, in seconds)
    /// Default to 90 seconds if not specified
    private var keepAliveIntervals: [UUID: Duration] = [:]
    private static let defaultKeepAliveInterval: Duration = .seconds(90)

    /// Reentrancy guard for BLE reconnection handling
    private var isReauthenticating = false

    // MARK: - Handlers

    /// Handler for keep-alive ACK responses
    /// Called when ACK with unsynced count is received
    public var keepAliveResponseHandler: (@Sendable (UUID, Int) async -> Void)?

    // MARK: - Initialization

    public init(
        bleTransport: any BLETransport,
        binaryProtocol: BinaryProtocolService,
        dataStore: DataStore,
        keychainService: any KeychainServiceProtocol = KeychainService.shared
    ) {
        self.bleTransport = bleTransport
        self.binaryProtocol = binaryProtocol
        self.dataStore = dataStore
        self.keychainService = keychainService
    }

    // MARK: - Session Management

    /// Create a new session for a remote node
    public func createSession(
        deviceID: UUID,
        contact: ContactDTO,
        password: String,
        rememberPassword: Bool = true
    ) async throws -> RemoteNodeSessionDTO {
        guard let role = RemoteNodeRole(contactType: contact.type) else {
            throw RemoteNodeError.invalidResponse
        }

        guard contact.publicKey.count == 32 else {
            throw RemoteNodeError.loginFailed("Invalid public key length")
        }

        if rememberPassword {
            try await keychainService.storePassword(password, forNodeKey: contact.publicKey)
        }

        let dto = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: contact.publicKey,
            name: contact.displayName,
            role: role,
            latitude: contact.latitude,
            longitude: contact.longitude
        )

        try await dataStore.saveRemoteNodeSessionDTO(dto)
        guard let saved = try await dataStore.fetchRemoteNodeSession(publicKey: contact.publicKey) else {
            throw RemoteNodeError.sessionNotFound
        }
        return saved
    }

    /// Remove a session and its associated data
    public func removeSession(id: UUID, publicKey: Data) async throws {
        stopKeepAlive(sessionID: id)
        try await keychainService.deletePassword(forNodeKey: publicKey)
        try await dataStore.deleteRemoteNodeSession(id: id)
    }

    // MARK: - Login

    /// Login to a remote node.
    /// Works for both room servers and repeaters.
    /// - Parameters:
    ///   - sessionID: The session to authenticate
    ///   - password: Optional password (uses keychain if not provided)
    ///   - pathLength: Path length for timeout calculation (0 = direct)
    public func login(
        sessionID: UUID,
        password: String? = nil,
        pathLength: UInt8 = 0
    ) async throws -> LoginResult {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        // Get password from parameter or keychain
        let pwd: String
        if let password {
            pwd = password
        } else if let stored = try await keychainService.retrievePassword(forNodeKey: session.publicKey) {
            pwd = stored
        } else {
            throw RemoteNodeError.passwordNotFound
        }

        // Use existing login encoding method
        let frameData = FrameCodec.encodeSendLogin(
            publicKey: session.publicKey,
            password: pwd
        )

        guard let response = try await bleTransport.send(frameData) else {
            throw RemoteNodeError.timeout
        }

        guard response.first == ResponseCode.sent.rawValue else {
            throw RemoteNodeError.sendFailed("Login request rejected")
        }

        // Calculate timeout based on path length
        let timeout = LoginTimeoutConfig.timeout(forPathLength: pathLength)

        // Wait for login result push (keyed by 6-byte prefix to match MeshCore protocol)
        return try await withCheckedThrowingContinuation { continuation in
            let prefix = Data(session.publicKey.prefix(6))

            // Cancel any existing pending login for this prefix (collision or duplicate attempt)
            if let existing = pendingLogins.removeValue(forKey: prefix) {
                let prefixHex = prefix.map { String(format: "%02x", $0) }.joined()
                logger.warning("Overwriting pending login for prefix \(prefixHex) - possible collision or duplicate attempt")
                existing.resume(throwing: RemoteNodeError.cancelled)
            }

            pendingLogins[prefix] = continuation

            Task {
                try await Task.sleep(for: timeout)
                if let pending = pendingLogins.removeValue(forKey: prefix) {
                    logger.warning("Login timeout after \(timeout) for session \(sessionID) (path length: \(pathLength))")
                    pending.resume(throwing: RemoteNodeError.timeout)
                }
            }
        }
    }

    /// Handle login result push from device.
    ///
    /// Accepts the 6-byte public key prefix directly from the protocol message.
    /// No contact lookup needed - pending logins are keyed by prefix.
    ///
    /// - Parameters:
    ///   - result: The login result from the remote node
    ///   - fromPublicKeyPrefix: 6-byte public key prefix identifying the node
    public func handleLoginResult(_ result: LoginResult, fromPublicKeyPrefix: Data) async {
        guard fromPublicKeyPrefix.count >= 6 else {
            logger.warning("Login result has invalid prefix length: \(fromPublicKeyPrefix.count)")
            return
        }

        let prefix = Data(fromPublicKeyPrefix.prefix(6))
        guard let continuation = pendingLogins.removeValue(forKey: prefix) else {
            // This can happen if:
            // 1. Response arrived after timeout
            // 2. Prefix collision (astronomically unlikely)
            // 3. Spurious login result from network
            let prefixHex = prefix.map { String(format: "%02x", $0) }.joined()
            logger.warning("Login result with no pending request. Prefix: \(prefixHex). Possible late response or collision.")
            return
        }

        if result.success {
            // Update session state - use prefix-based lookup since we only have the prefix
            if let session = try? await dataStore.fetchRemoteNodeSessionByPrefix(prefix) {
                let permission = RoomPermissionLevel(rawValue: result.aclPermissions ?? 0) ?? .guest
                try? await dataStore.updateRemoteNodeSessionConnection(
                    id: session.id,
                    isConnected: true,
                    permissionLevel: permission
                )

                // Use default keep-alive interval (90 seconds)
                // Firmware marks the interval multiplier as legacy and always sends 0
                keepAliveIntervals[session.id] = Self.defaultKeepAliveInterval

                // Start keep-alive for room servers
                if session.isRoom {
                    startKeepAlive(sessionID: session.id, publicKey: session.publicKey)
                }
            }
        }

        continuation.resume(returning: result)
    }

    // MARK: - Keep-Alive (Room Servers)

    /// Start periodic keep-alive for a room server session.
    ///
    /// **CRITICAL**: Keep-alive only works with direct routing. The firmware ignores
    /// keep-alive requests that arrive via flood routing. This method checks routing
    /// status before each keep-alive attempt.
    ///
    /// Room servers track client activity and may mark inactive clients as disconnected.
    private func startKeepAlive(sessionID: UUID, publicKey: Data) {
        stopKeepAlive(sessionID: sessionID)

        let interval = keepAliveIntervals[sessionID] ?? Self.defaultKeepAliveInterval

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)

                guard !Task.isCancelled else { break }

                do {
                    try await self?.sendKeepAliveIfDirectRouted(sessionID: sessionID, publicKey: publicKey)
                } catch RemoteNodeError.floodRouted {
                    // Cannot send keep-alive on flood route - log and continue
                    // The server will eventually mark us inactive, but we'll
                    // re-authenticate on next message or explicit reconnect
                    self?.logger.info("Skipping keep-alive for flood-routed session \(sessionID)")
                    continue
                } catch {
                    // Other error - keep-alive failed
                    self?.logger.warning("Keep-alive failed for session \(sessionID): \(error)")
                    break
                }
            }
        }

        keepAliveTasks[sessionID] = task
    }

    /// Stop keep-alive for a session
    private func stopKeepAlive(sessionID: UUID) {
        keepAliveTasks[sessionID]?.cancel()
        keepAliveTasks.removeValue(forKey: sessionID)
    }

    /// Send keep-alive only if the session has a direct routing path.
    ///
    /// The firmware ONLY processes keep-alive requests that arrive via direct routing
    /// (packet->isRouteDirect()). Flood-routed keep-alive requests are silently ignored.
    ///
    /// - Throws: `RemoteNodeError.floodRouted` if contact is flood-routed
    /// - Throws: `RemoteNodeError.contactNotFound` if contact not in database
    private func sendKeepAliveIfDirectRouted(sessionID: UUID, publicKey: Data) async throws {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        // Check contact's routing status
        guard let contact = try await dataStore.findContactByPublicKey(publicKey) else {
            throw RemoteNodeError.contactNotFound
        }

        // Keep-alive only works with direct routing
        // outPathLength: -1 = flood, 0 = direct, >0 = path-based (also direct to first hop)
        if contact.outPathLength < 0 {
            throw RemoteNodeError.floodRouted
        }

        // Send keep-alive request
        let frameData = FrameCodec.encodeBinaryRequest(
            recipientPublicKey: publicKey,
            requestType: .keepAlive
        )

        guard let response = try await bleTransport.send(frameData) else {
            throw RemoteNodeError.timeout
        }

        guard response.first == ResponseCode.sent.rawValue else {
            throw RemoteNodeError.sendFailed("Keep-alive rejected")
        }

        // Note: The actual ACK response with unsynced count arrives as a push
        // and is handled by handleKeepAliveACK()
    }

    /// Handle keep-alive ACK response from server.
    ///
    /// Keep-alive responses are ACK packets with an appended byte containing
    /// the count of unsynced (waiting) messages on the server.
    ///
    /// Frame format: [ACK_hash:4][unsynced_count:1]
    public func handleKeepAliveACK(fromPublicKeyPrefix: Data, unsyncedCount: UInt8) async {
        guard let session = try? await dataStore.fetchRemoteNodeSessionByPrefix(fromPublicKeyPrefix),
              session.isRoom else {
            return
        }

        logger.debug("Keep-alive ACK from \(session.name): \(unsyncedCount) unsynced messages")

        // Notify handler if there are waiting messages
        if unsyncedCount > 0 {
            await keepAliveResponseHandler?(session.id, Int(unsyncedCount))
        }
    }

    /// Public method to send keep-alive (for manual refresh).
    /// Only succeeds if contact has direct routing path.
    public func sendKeepAlive(sessionID: UUID) async throws {
        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }
        try await sendKeepAliveIfDirectRouted(sessionID: sessionID, publicKey: session.publicKey)
    }

    // MARK: - Logout

    /// Explicitly logout from a remote node.
    /// Sends CMD_LOGOUT to terminate the persistent connection.
    public func logout(sessionID: UUID) async throws {
        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        stopKeepAlive(sessionID: sessionID)

        let connectionState = await bleTransport.connectionState
        if connectionState == .ready {
            let frameData = FrameCodec.encodeLogout(recipientPublicKey: session.publicKey)
            _ = try await bleTransport.send(frameData)
        }

        try await dataStore.updateRemoteNodeSessionConnection(
            id: sessionID,
            isConnected: false,
            permissionLevel: .guest
        )
    }

    // MARK: - Status

    /// Request status from a remote node.
    /// Uses binary protocol request via BinaryProtocolService.
    public func requestStatus(sessionID: UUID) async throws -> Data? {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        // Use existing binary protocol service
        // Returns tag for correlating response in handleBinaryResponse
        return try await binaryProtocol.requestStatus(from: session.publicKey)
    }

    // MARK: - Telemetry

    /// Request telemetry from a remote node
    public func requestTelemetry(sessionID: UUID) async throws {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        let frameData = FrameCodec.encodeTelemetryRequest(recipientPublicKey: session.publicKey)

        guard let response = try await bleTransport.send(frameData) else {
            throw RemoteNodeError.timeout
        }

        guard response.first == ResponseCode.sent.rawValue else {
            throw RemoteNodeError.sendFailed("Telemetry request rejected")
        }

        // Response will arrive via push notification
    }

    // MARK: - CLI Commands

    /// Send a CLI command to a remote node (admin only)
    public func sendCLICommand(sessionID: UUID, command: String) async throws -> String {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw RemoteNodeError.notConnected
        }

        guard let session = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        guard session.isAdmin else {
            throw RemoteNodeError.permissionDenied
        }

        // Encode as text message with CLI_DATA type
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let frameData = FrameCodec.encodeSendTextMessage(
            textType: .cliData,
            attempt: 1,
            timestamp: timestamp,
            recipientKeyPrefix: session.publicKeyPrefix,
            text: command
        )

        guard let response = try await bleTransport.send(frameData) else {
            throw RemoteNodeError.timeout
        }

        guard response.first == ResponseCode.sent.rawValue else {
            throw RemoteNodeError.sendFailed("CLI command rejected")
        }

        // Response will arrive via text message push
        return ""  // CLI response handling to be implemented
    }

    // MARK: - Disconnect

    /// Mark session as disconnected without sending logout.
    /// Use logout() for explicit disconnection when BLE is available.
    public func disconnect(sessionID: UUID) async {
        stopKeepAlive(sessionID: sessionID)
        try? await dataStore.updateRemoteNodeSessionConnection(
            id: sessionID,
            isConnected: false,
            permissionLevel: .guest
        )
    }

    // MARK: - BLE Reconnection

    /// Called when BLE connection is re-established.
    /// Re-authenticates all previously connected sessions in parallel.
    ///
    /// Includes reentrancy guard to prevent multiple simultaneous re-auth attempts
    /// if BLE connection flaps rapidly.
    public func handleBLEReconnection() async {
        guard !isReauthenticating else {
            logger.debug("Skipping re-auth: already in progress")
            return
        }

        guard let connectedSessions = try? await dataStore.fetchConnectedRemoteNodeSessions(),
              !connectedSessions.isEmpty else {
            return
        }

        isReauthenticating = true
        defer { isReauthenticating = false }

        // Re-authenticate all sessions in parallel
        await withTaskGroup(of: Void.self) { group in
            for session in connectedSessions {
                group.addTask { [self] in
                    do {
                        _ = try await self.login(sessionID: session.id)
                    } catch {
                        self.logger.warning("Re-auth failed for session \(session.id): \(error)")
                        try? await self.dataStore.updateRemoteNodeSessionConnection(
                            id: session.id,
                            isConnected: false,
                            permissionLevel: .guest
                        )
                    }
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Stop all keep-alive timers (call on app termination)
    public func stopAllKeepAlives() {
        for task in keepAliveTasks.values {
            task.cancel()
        }
        keepAliveTasks.removeAll()
    }
}
