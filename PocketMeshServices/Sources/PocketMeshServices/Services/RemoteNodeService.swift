import Foundation
import MeshCore
import os

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
    case sessionError(MeshCoreError)

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
        case .sessionError(let error):
            return "Session error: \(error.localizedDescription)"
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

// MARK: - Login Result

public struct LoginResult: Sendable {
    public let success: Bool
    public let isAdmin: Bool
    public let aclPermissions: UInt8?
    public let publicKeyPrefix: Data

    public init(success: Bool, isAdmin: Bool, aclPermissions: UInt8?, publicKeyPrefix: Data) {
        self.success = success
        self.isAdmin = isAdmin
        self.aclPermissions = aclPermissions
        self.publicKeyPrefix = publicKeyPrefix
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

    private let session: MeshCoreSession
    private let dataStore: PersistenceStore
    private let keychainService: KeychainService
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "RemoteNode")

    /// Pending login continuations keyed by 6-byte public key prefix.
    /// Using 6-byte prefix matches MeshCore protocol format for login results.
    private var pendingLogins: [Data: CheckedContinuation<LoginResult, Error>] = [:]

    /// Keep-alive timer tasks
    private var keepAliveTasks: [UUID: Task<Void, Never>] = [:]

    /// Keep-alive intervals per session (from login response, in seconds)
    /// Default to 90 seconds if not specified
    private var keepAliveIntervals: [UUID: Duration] = [:]
    private static let defaultKeepAliveInterval: Duration = .seconds(90)

    /// Reentrancy guard for BLE reconnection handling
    private var isReauthenticating = false

    /// Event monitoring task
    private var eventMonitorTask: Task<Void, Never>?

    // MARK: - Handlers

    /// Handler for keep-alive ACK responses
    /// Called when ACK with unsynced count is received
    public var keepAliveResponseHandler: (@Sendable (UUID, Int) async -> Void)?

    // MARK: - Initialization

    public init(
        session: MeshCoreSession,
        dataStore: PersistenceStore,
        keychainService: KeychainService
    ) {
        self.session = session
        self.dataStore = dataStore
        self.keychainService = keychainService
    }

    deinit {
        eventMonitorTask?.cancel()
    }

    // MARK: - Event Monitoring

    /// Start monitoring MeshCore events for login results
    public func startEventMonitoring() {
        eventMonitorTask?.cancel()

        eventMonitorTask = Task { [weak self] in
            guard let self else { return }
            let events = await session.events()

            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }

    /// Stop monitoring events
    public func stopEventMonitoring() {
        eventMonitorTask?.cancel()
        eventMonitorTask = nil
    }

    /// Handle incoming MeshCore event
    private func handleEvent(_ event: MeshEvent) async {
        switch event {
        case .loginSuccess(let info):
            let prefixHex = info.publicKeyPrefix.map { String(format: "%02x", $0) }.joined()
            logger.info("loginSuccess received for prefix \(prefixHex)")
            let result = LoginResult(
                success: true,
                isAdmin: info.isAdmin,
                aclPermissions: info.permissions,
                publicKeyPrefix: info.publicKeyPrefix
            )
            await handleLoginResult(result, fromPublicKeyPrefix: info.publicKeyPrefix)

        case .loginFailed(let publicKeyPrefix):
            if let prefix = publicKeyPrefix {
                let result = LoginResult(
                    success: false,
                    isAdmin: false,
                    aclPermissions: nil,
                    publicKeyPrefix: prefix
                )
                await handleLoginResult(result, fromPublicKeyPrefix: prefix)
            }

        default:
            break
        }
    }

    // MARK: - Session Management

    /// Create a session DTO for a contact, optionally preserving data from an existing session.
    private func makeSessionDTO(
        deviceID: UUID,
        contact: ContactDTO,
        role: RemoteNodeRole,
        preserving existing: RemoteNodeSessionDTO? = nil
    ) -> RemoteNodeSessionDTO {
        RemoteNodeSessionDTO(
            id: existing?.id ?? UUID(),
            deviceID: deviceID,
            publicKey: contact.publicKey,
            name: contact.displayName,
            role: role,
            latitude: contact.latitude,
            longitude: contact.longitude,
            isConnected: false,
            permissionLevel: existing?.permissionLevel ?? .guest,
            lastConnectedDate: existing?.lastConnectedDate,
            lastBatteryMillivolts: existing?.lastBatteryMillivolts,
            lastUptimeSeconds: existing?.lastUptimeSeconds,
            lastNoiseFloor: existing?.lastNoiseFloor,
            unreadCount: existing?.unreadCount ?? 0,
            lastRxAirtimeSeconds: existing?.lastRxAirtimeSeconds,
            neighborCount: existing?.neighborCount ?? 0
        )
    }

    /// Create a new session for a remote node.
    public func createSession(
        deviceID: UUID,
        contact: ContactDTO,
        password: String?,
        rememberPassword: Bool = true
    ) async throws -> RemoteNodeSessionDTO {
        guard let role = RemoteNodeRole(contactType: contact.type) else {
            throw RemoteNodeError.invalidResponse
        }

        guard contact.publicKey.count == 32 else {
            throw RemoteNodeError.loginFailed("Invalid public key length: expected 32 bytes, got \(contact.publicKey.count)")
        }

        let pubKeyHex = contact.publicKey.prefix(6).map { String(format: "%02x", $0) }.joined()

        // Check for existing session - reuse to avoid duplicates
        let existing = try? await dataStore.fetchRemoteNodeSession(publicKey: contact.publicKey)

        if let existing {
            logger.info("createSession: reusing existing session \(existing.id) for \(pubKeyHex), isConnected=\(existing.isConnected)")
        } else {
            logger.info("createSession: creating new session for \(pubKeyHex)")
        }

        let dto = makeSessionDTO(deviceID: deviceID, contact: contact, role: role, preserving: existing)

        try await dataStore.saveRemoteNodeSessionDTO(dto)

        // Clean up any duplicate sessions with the same public key but different IDs
        try await dataStore.cleanupDuplicateRemoteNodeSessions(publicKey: contact.publicKey, keepID: dto.id)

        guard let saved = try await dataStore.fetchRemoteNodeSession(publicKey: contact.publicKey) else {
            logger.error("createSession: failed to fetch saved session for \(pubKeyHex)")
            throw RemoteNodeError.sessionNotFound
        }

        logger.info("createSession: saved session \(saved.id) for \(pubKeyHex)")
        return saved
    }

    /// Remove a session and its associated data
    public func removeSession(id: UUID, publicKey: Data) async throws {
        stopKeepAlive(sessionID: id)
        try await keychainService.deletePassword(forNodeKey: publicKey)
        try await dataStore.deleteRemoteNodeSession(id: id)
    }

    /// Check if a password is stored for a contact's public key.
    public func hasPassword(forContact contact: ContactDTO) async -> Bool {
        await keychainService.hasPassword(forNodeKey: contact.publicKey)
    }

    /// Store a password for a remote node.
    /// Call this after successful login to save correct passwords only.
    public func storePassword(_ password: String, forNodeKey publicKey: Data) async throws {
        try await keychainService.storePassword(password, forNodeKey: publicKey)
    }

    // MARK: - Login

    /// Login to a remote node.
    /// Works for both room servers and repeaters.
    /// - Parameters:
    ///   - sessionID: The remote session ID.
    ///   - password: Optional password (uses stored password if nil).
    ///   - pathLength: Path length hint for timeout calculation.
    public func login(
        sessionID: UUID,
        password: String? = nil,
        pathLength: UInt8 = 0
    ) async throws -> LoginResult {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        // Get password from parameter or keychain
        let pwd: String
        if let password {
            pwd = password
        } else if let stored = try await keychainService.retrievePassword(forNodeKey: remoteSession.publicKey) {
            pwd = stored
        } else {
            throw RemoteNodeError.passwordNotFound
        }

        // Calculate timeout based on path length
        let timeout = LoginTimeoutConfig.timeout(forPathLength: pathLength)
        let prefix = Data(remoteSession.publicKey.prefix(6))

        // Cancel any existing pending login for this prefix
        if let existing = pendingLogins.removeValue(forKey: prefix) {
            let prefixHex = prefix.map { String(format: "%02x", $0) }.joined()
            logger.warning("Overwriting pending login for prefix \(prefixHex)")
            existing.resume(throwing: RemoteNodeError.cancelled)
        }

        // Register continuation BEFORE sending to avoid race condition with loginSuccess event
        let prefixHex = prefix.map { String(format: "%02x", $0) }.joined()
        logger.info("login: registering pending login for prefix \(prefixHex)")
        return try await withCheckedThrowingContinuation { continuation in
            pendingLogins[prefix] = continuation

            Task { [self] in
                // Send login via MeshCore session
                do {
                    _ = try await session.sendLogin(to: remoteSession.publicKey, password: pwd)
                } catch {
                    // Send failed - remove pending and resume with error
                    if let pending = pendingLogins.removeValue(forKey: prefix) {
                        let meshError = error as? MeshCoreError ?? MeshCoreError.connectionLost(underlying: error)
                        pending.resume(throwing: RemoteNodeError.sessionError(meshError))
                    }
                    return
                }

                // Send succeeded - start timeout countdown
                logger.info("login: send succeeded, starting \(timeout) timeout for prefix \(prefixHex)")
                try? await Task.sleep(for: timeout)
                if let pending = pendingLogins.removeValue(forKey: prefix) {
                    logger.warning("Login timeout after \(timeout) for session \(sessionID), prefix \(prefixHex)")
                    pending.resume(throwing: RemoteNodeError.timeout)
                } else {
                    logger.info("login: timeout elapsed but continuation already consumed for prefix \(prefixHex)")
                }
            }
        }
    }

    /// Handle login result push from device.
    private func handleLoginResult(_ result: LoginResult, fromPublicKeyPrefix: Data) async {
        guard fromPublicKeyPrefix.count >= 6 else {
            logger.warning("Login result has invalid prefix length: \(fromPublicKeyPrefix.count)")
            return
        }

        let prefix = Data(fromPublicKeyPrefix.prefix(6))
        let prefixHex = prefix.map { String(format: "%02x", $0) }.joined()
        let pendingKeys = pendingLogins.keys.map { $0.map { String(format: "%02x", $0) }.joined() }
        logger.info("handleLoginResult: looking for prefix \(prefixHex), pending keys: \(pendingKeys)")
        guard let continuation = pendingLogins.removeValue(forKey: prefix) else {
            logger.warning("Login result with no pending request. Prefix: \(prefixHex)")
            return
        }
        logger.info("handleLoginResult: found continuation for prefix \(prefixHex)")

        if result.success {
            // Update session state
            do {
                guard let remoteSession = try await dataStore.fetchRemoteNodeSessionByPrefix(prefix) else {
                    logger.error("handleLoginResult: no session found for prefix \(prefixHex) - database may be corrupted")
                    continuation.resume(returning: result)
                    return
                }

                let permission: RoomPermissionLevel = result.isAdmin ? .admin :
                    (RoomPermissionLevel(rawValue: result.aclPermissions ?? 0) ?? .guest)

                logger.info("handleLoginResult: updating session \(remoteSession.id) isConnected=true, permission=\(permission.rawValue)")

                try await dataStore.updateRemoteNodeSessionConnection(
                    id: remoteSession.id,
                    isConnected: true,
                    permissionLevel: permission
                )

                // Verify the update succeeded
                if let verifySession = try await dataStore.fetchRemoteNodeSession(id: remoteSession.id) {
                    if verifySession.isConnected {
                        logger.info("handleLoginResult: verified session \(remoteSession.id) isConnected=true")
                    } else {
                        logger.error("handleLoginResult: session \(remoteSession.id) still shows isConnected=false after update!")
                    }
                }

                keepAliveIntervals[remoteSession.id] = Self.defaultKeepAliveInterval

                // Start keep-alive for room servers
                if remoteSession.isRoom {
                    startKeepAlive(sessionID: remoteSession.id, publicKey: remoteSession.publicKey)
                }
            } catch {
                logger.error("handleLoginResult: failed to update session state: \(error)")
            }
        }

        continuation.resume(returning: result)
    }

    // MARK: - Keep-Alive (Room Servers)

    /// Start periodic keep-alive for a room server session.
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
                    self?.logger.info("Skipping keep-alive for flood-routed session \(sessionID)")
                    continue
                } catch {
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
    private func sendKeepAliveIfDirectRouted(sessionID: UUID, publicKey: Data) async throws {
        // Fetch session to get deviceID
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        // Check contact's routing status
        guard let contact = try await dataStore.fetchContact(deviceID: remoteSession.deviceID, publicKey: publicKey) else {
            throw RemoteNodeError.contactNotFound
        }

        // Keep-alive only works with direct routing
        if contact.outPathLength < 0 {
            throw RemoteNodeError.floodRouted
        }

        // Send status request as keep-alive
        do {
            _ = try await session.requestStatus(from: publicKey)
        } catch let error as MeshCoreError {
            throw RemoteNodeError.sessionError(error)
        }
    }

    /// Public method to send keep-alive (for manual refresh).
    public func sendKeepAlive(sessionID: UUID) async throws {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }
        try await sendKeepAliveIfDirectRouted(sessionID: sessionID, publicKey: remoteSession.publicKey)
    }

    // MARK: - History Sync

    /// Request message history from a room server.
    public func requestHistorySync(sessionID: UUID, since: UInt32 = 1) async throws {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        guard remoteSession.isRoom else {
            throw RemoteNodeError.invalidResponse
        }

        // Check for direct route
        guard let contact = try await dataStore.fetchContact(deviceID: remoteSession.deviceID, publicKey: remoteSession.publicKey) else {
            throw RemoteNodeError.contactNotFound
        }

        if contact.outPathLength < 0 {
            throw RemoteNodeError.floodRouted
        }

        // Request status (which triggers sync)
        do {
            _ = try await session.requestStatus(from: remoteSession.publicKey)
        } catch let error as MeshCoreError {
            throw RemoteNodeError.sessionError(error)
        }

        logger.info("Requested history sync for room \(remoteSession.name) since \(since)")
    }

    // MARK: - Logout

    /// Explicitly logout from a remote node.
    public func logout(sessionID: UUID) async throws {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        stopKeepAlive(sessionID: sessionID)

        do {
            try await session.sendLogout(to: remoteSession.publicKey)
        } catch {
            // Ignore errors - we're disconnecting anyway
            logger.info("Logout send failed (ignoring): \(error)")
        }

        try await dataStore.updateRemoteNodeSessionConnection(
            id: sessionID,
            isConnected: false,
            permissionLevel: .guest
        )
    }

    // MARK: - Status

    /// Request status from a remote node.
    public func requestStatus(sessionID: UUID) async throws -> StatusResponse {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        do {
            return try await session.requestStatus(from: remoteSession.publicKey)
        } catch let error as MeshCoreError {
            throw RemoteNodeError.sessionError(error)
        }
    }

    // MARK: - Telemetry

    /// Request telemetry from a remote node
    public func requestTelemetry(sessionID: UUID) async throws -> TelemetryResponse {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        do {
            return try await session.requestTelemetry(from: remoteSession.publicKey)
        } catch let error as MeshCoreError {
            throw RemoteNodeError.sessionError(error)
        }
    }

    // MARK: - CLI Commands

    /// Send a CLI command to a remote node (admin only)
    public func sendCLICommand(sessionID: UUID, command: String) async throws -> String {
        guard let remoteSession = try await dataStore.fetchRemoteNodeSession(id: sessionID) else {
            throw RemoteNodeError.sessionNotFound
        }

        guard remoteSession.isAdmin else {
            throw RemoteNodeError.permissionDenied
        }

        do {
            _ = try await session.sendCommand(to: remoteSession.publicKey, command: command)
        } catch let error as MeshCoreError {
            throw RemoteNodeError.sessionError(error)
        }

        // CLI response handling to be implemented
        return ""
    }

    // MARK: - Disconnect

    /// Mark session as disconnected without sending logout.
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
    public func handleBLEReconnection() async {
        guard !isReauthenticating else {
            logger.info("Skipping re-auth: already in progress")
            return
        }

        guard let connectedSessions = try? await dataStore.fetchConnectedRemoteNodeSessions(),
              !connectedSessions.isEmpty else {
            return
        }

        isReauthenticating = true
        defer { isReauthenticating = false }

        await withTaskGroup(of: Void.self) { group in
            for remoteSession in connectedSessions {
                group.addTask { [self] in
                    do {
                        _ = try await self.login(sessionID: remoteSession.id)
                    } catch {
                        self.logger.warning("Re-auth failed for session \(remoteSession.id): \(error)")
                        try? await self.dataStore.updateRemoteNodeSessionConnection(
                            id: remoteSession.id,
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
