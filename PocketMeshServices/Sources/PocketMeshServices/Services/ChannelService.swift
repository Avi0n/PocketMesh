import Foundation
import CryptoKit
import MeshCore
import os

// MARK: - Channel Service Errors

public enum ChannelServiceError: Error, Sendable {
    case notConnected
    case channelNotFound
    case invalidChannelIndex
    case secretHashingFailed
    case saveFailed(String)
    case sendFailed(String)
    case sessionError(MeshCoreError)
    case syncAlreadyInProgress
    case circuitBreakerOpen(consecutiveFailures: Int)
}

// MARK: - Channel Sync Error Details

/// Detailed error information for a failed channel sync
public struct ChannelSyncError: Sendable, Equatable {
    public let index: UInt8
    public let errorType: ErrorType
    public let description: String

    public enum ErrorType: Sendable, Equatable {
        case timeout
        case deviceError(code: UInt8)
        case databaseError
        case unknown
    }

    public init(index: UInt8, errorType: ErrorType, description: String) {
        self.index = index
        self.errorType = errorType
        self.description = description
    }

    /// Whether this error type is potentially recoverable with retry
    public var isRetryable: Bool {
        switch errorType {
        case .timeout:
            return true
        case .deviceError, .databaseError, .unknown:
            return false
        }
    }
}

// MARK: - Channel Sync Result

public struct ChannelSyncResult: Sendable, Equatable {
    public let channelsSynced: Int
    public let errors: [ChannelSyncError]

    /// Whether sync completed without errors
    public var isComplete: Bool { errors.isEmpty }

    /// Indices of channels that failed with retryable errors
    public var retryableIndices: [UInt8] {
        errors.filter { $0.isRetryable }.map { $0.index }
    }

    public init(channelsSynced: Int, errors: [ChannelSyncError] = []) {
        self.channelsSynced = channelsSynced
        self.errors = errors
    }
}

// MARK: - Channel Service Actor

/// Actor-isolated service for channel (group) management.
/// Handles channel CRUD operations, secret hashing, and broadcast messaging.
public actor ChannelService {

    // MARK: - Properties

    private let session: MeshCoreSession
    private let dataStore: PersistenceStore
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "ChannelService")

    /// Callback for channel updates
    private var channelUpdateHandler: (@Sendable ([ChannelDTO]) -> Void)?

    /// Tracks whether a sync operation is in progress
    private var isSyncing = false

    // MARK: - Initialization

    public init(
        session: MeshCoreSession,
        dataStore: PersistenceStore
    ) {
        self.session = session
        self.dataStore = dataStore
    }

    // MARK: - Secret Hashing

    /// Hashes a passphrase into a 16-byte channel secret using SHA-256.
    /// The firmware uses the first 16 bytes of the SHA-256 hash.
    /// - Parameter passphrase: The passphrase to hash
    /// - Returns: 16-byte secret data
    public static func hashSecret(_ passphrase: String) -> Data {
        guard !passphrase.isEmpty else {
            return Data(repeating: 0, count: ProtocolLimits.channelSecretSize)
        }

        let data = passphrase.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        return Data(hash.prefix(ProtocolLimits.channelSecretSize))
    }

    /// Validates that a secret has the correct size
    public static func validateSecret(_ secret: Data) -> Bool {
        secret.count == ProtocolLimits.channelSecretSize
    }

    // MARK: - Channel CRUD Operations

    /// Fetches all channels for a device from the remote device.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - maxChannels: Maximum number of channels to fetch (from device capacity)
    /// - Returns: Sync result with number of channels synced
    /// - Throws: `syncAlreadyInProgress` if another sync is running,
    ///           `circuitBreakerOpen` if too many consecutive timeouts
    public func syncChannels(deviceID: UUID, maxChannels: UInt8) async throws -> ChannelSyncResult {
        // Concurrency guard
        guard !isSyncing else {
            logger.warning("Channel sync already in progress, rejecting concurrent request")
            throw ChannelServiceError.syncAlreadyInProgress
        }

        isSyncing = true
        defer { isSyncing = false }

        var syncedCount = 0
        var syncErrors: [ChannelSyncError] = []
        var channels: [ChannelDTO] = []

        // Circuit breaker state
        var consecutiveTimeouts = 0
        let circuitBreakerThreshold = 3

        for index: UInt8 in 0..<maxChannels {
            // Circuit breaker: fail fast if connection is clearly broken
            if consecutiveTimeouts >= circuitBreakerThreshold {
                logger.error("Circuit breaker open: \(consecutiveTimeouts) consecutive timeouts, aborting sync")
                // Mark remaining channels as failed
                for remaining in index..<maxChannels {
                    syncErrors.append(ChannelSyncError(
                        index: remaining,
                        errorType: .timeout,
                        description: "Skipped due to circuit breaker"
                    ))
                }
                throw ChannelServiceError.circuitBreakerOpen(consecutiveFailures: consecutiveTimeouts)
            }

            do {
                if let channelInfo = try await fetchChannel(index: index) {
                    _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)
                    syncedCount += 1
                    consecutiveTimeouts = 0  // Reset on success

                    // Fetch the saved channel DTO
                    if let dto = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
                        channels.append(dto)
                    }
                } else {
                    // Channel not configured on device - delete any stale local entry
                    consecutiveTimeouts = 0  // Not-found is not a timeout
                    if let staleChannel = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
                        try await dataStore.deleteChannel(id: staleChannel.id)
                    }
                }
            } catch let error as ChannelServiceError {
                // Track consecutive timeouts for circuit breaker
                if case .sessionError(let meshError) = error, case .timeout = meshError {
                    consecutiveTimeouts += 1
                } else {
                    consecutiveTimeouts = 0
                }
                let syncError = classifyError(error, forIndex: index)
                logger.warning("Failed to sync channel \(index): \(syncError.description)")
                syncErrors.append(syncError)
            } catch {
                consecutiveTimeouts = 0
                let syncError = classifyError(error, forIndex: index)
                logger.warning("Failed to sync channel \(index): \(syncError.description)")
                syncErrors.append(syncError)
            }
        }

        // Clean up orphaned channels (index >= maxChannels)
        // This handles the case where device capacity decreased
        do {
            let allLocalChannels = try await dataStore.fetchChannels(deviceID: deviceID)
            for channel in allLocalChannels where channel.index >= maxChannels {
                logger.info("Removing orphaned channel \(channel.index) (maxChannels=\(maxChannels))")
                try await dataStore.deleteChannel(id: channel.id)
            }
        } catch {
            logger.warning("Failed to cleanup orphaned channels: \(error.localizedDescription)")
            // Non-fatal: continue with sync result
        }

        // Notify handler of updated channels
        channelUpdateHandler?(channels)

        return ChannelSyncResult(channelsSynced: syncedCount, errors: syncErrors)
    }

    /// Retries syncing only the channels that previously failed.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - indices: Channel indices to retry
    /// - Returns: Sync result for the retried channels
    public func retryFailedChannels(deviceID: UUID, indices: [UInt8]) async throws -> ChannelSyncResult {
        guard !isSyncing else {
            throw ChannelServiceError.syncAlreadyInProgress
        }

        guard !indices.isEmpty else {
            return ChannelSyncResult(channelsSynced: 0, errors: [])
        }

        isSyncing = true
        defer { isSyncing = false }

        logger.info("Retrying \(indices.count) failed channels: \(indices)")

        // Brief delay before retry to allow transient issues to resolve
        try await Task.sleep(for: .milliseconds(500))

        var syncedCount = 0
        var syncErrors: [ChannelSyncError] = []
        var channels: [ChannelDTO] = []

        // Circuit breaker for retry (stricter threshold than initial sync)
        var consecutiveTimeouts = 0
        let circuitBreakerThreshold = 2

        for index in indices {
            // Circuit breaker: stop retrying if connection is clearly broken
            if consecutiveTimeouts >= circuitBreakerThreshold {
                logger.warning("Retry circuit breaker open: \(consecutiveTimeouts) consecutive timeouts, stopping retry")
                // Mark remaining channels as failed
                let remainingIndices = indices.drop(while: { $0 != index })
                for remaining in remainingIndices {
                    syncErrors.append(ChannelSyncError(
                        index: remaining,
                        errorType: .timeout,
                        description: "Skipped due to retry circuit breaker"
                    ))
                }
                break
            }

            do {
                if let channelInfo = try await fetchChannel(index: index) {
                    _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)
                    syncedCount += 1
                    consecutiveTimeouts = 0  // Reset on success

                    if let dto = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
                        channels.append(dto)
                    }
                    logger.info("Retry succeeded for channel \(index)")
                } else {
                    consecutiveTimeouts = 0  // Not-found is not a timeout
                }
            } catch {
                let syncError = classifyError(error, forIndex: index)
                // Track consecutive timeouts for circuit breaker
                if case .timeout = syncError.errorType {
                    consecutiveTimeouts += 1
                } else {
                    consecutiveTimeouts = 0
                }
                logger.warning("Retry failed for channel \(index): \(syncError.description)")
                syncErrors.append(syncError)
            }
        }

        // Notify handler if we recovered any channels
        if !channels.isEmpty {
            let allChannels = try await dataStore.fetchChannels(deviceID: deviceID)
            channelUpdateHandler?(allChannels)
        }

        return ChannelSyncResult(channelsSynced: syncedCount, errors: syncErrors)
    }

    /// Fetches a single channel from the device with retry logic for transient BLE failures.
    /// - Parameter index: The channel index 
    /// - Returns: Channel info if found, nil if not configured
    public func fetchChannel(index: UInt8) async throws -> ChannelInfo? {
        // BLE operations can fail transiently due to RF interference or timing.
        // Retry with exponential backoff per industry best practices (BLE spec recommends 30s timeout,
        // but shorter retries with backoff are more responsive).
        let maxAttempts = 3
        var lastError: MeshCoreError = .timeout

        for attempt in 1...maxAttempts {
            do {
                let meshChannelInfo = try await session.getChannel(index: index)

                // Treat empty channels (cleared slots) as not configured
                if meshChannelInfo.name.isEmpty {
                    return nil
                }

                // Validate returned index matches requested
                guard meshChannelInfo.index == index else {
                    logger.error("Channel index mismatch: requested \(index), received \(meshChannelInfo.index)")
                    throw ChannelServiceError.invalidChannelIndex
                }

                // Convert MeshCore.ChannelInfo to PocketMeshServices.ChannelInfo
                return ChannelInfo(
                    index: meshChannelInfo.index,
                    name: meshChannelInfo.name,
                    secret: meshChannelInfo.secret
                )
            } catch let error as MeshCoreError {
                // Non-retryable: channel not found on device (permanent error)
                if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                    return nil
                }

                // Retryable: timeout errors are transient BLE issues
                if case .timeout = error {
                    lastError = error
                    if attempt < maxAttempts {
                        // Exponential backoff: 500ms, 1000ms, 2000ms with jitter
                        let baseDelayMs = 500 * (1 << (attempt - 1))
                        let jitterMs = Int.random(in: -100...100)
                        let delayMs = baseDelayMs + jitterMs
                        logger.info("Channel \(index) fetch timeout, retry \(attempt)/\(maxAttempts) in \(delayMs)ms")
                        try await Task.sleep(for: .milliseconds(delayMs))
                        continue
                    }
                }

                // Non-retryable: other MeshCore errors (device errors, parse errors, etc.)
                throw ChannelServiceError.sessionError(error)
            }
        }

        // All retries exhausted
        throw ChannelServiceError.sessionError(lastError)
    }

    /// Sets (creates or updates) a channel on the device.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - index: The channel index 
    ///   - name: The channel name
    ///   - passphrase: The passphrase to hash into a secret
    public func setChannel(
        deviceID: UUID,
        index: UInt8,
        name: String,
        passphrase: String
    ) async throws {
        let secret = Self.hashSecret(passphrase)

        do {
            try await session.setChannel(index: index, name: name, secret: secret)

            // Save to local database
            let channelInfo = ChannelInfo(index: index, name: name, secret: secret)
            _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

            // Notify handler of update
            let channels = try await dataStore.fetchChannels(deviceID: deviceID)
            channelUpdateHandler?(channels)
        } catch let error as MeshCoreError {
            throw ChannelServiceError.sessionError(error)
        }
    }

    /// Sets a channel with a pre-computed secret (for advanced use cases).
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - index: The channel index 
    ///   - name: The channel name
    ///   - secret: The 16-byte secret (must be exactly 16 bytes)
    public func setChannelWithSecret(
        deviceID: UUID,
        index: UInt8,
        name: String,
        secret: Data
    ) async throws {
        guard Self.validateSecret(secret) else {
            throw ChannelServiceError.secretHashingFailed
        }

        do {
            try await session.setChannel(index: index, name: name, secret: secret)

            // Save to local database
            let channelInfo = ChannelInfo(index: index, name: name, secret: secret)
            _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

            // Notify handler of update
            let channels = try await dataStore.fetchChannels(deviceID: deviceID)
            channelUpdateHandler?(channels)
        } catch let error as MeshCoreError {
            throw ChannelServiceError.sessionError(error)
        }
    }

    /// Clears a channel by setting it to empty name and zero secret.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - index: The channel index
    public func clearChannel(deviceID: UUID, index: UInt8) async throws {
        // Set empty name and zero secret to clear
        try await setChannelWithSecret(
            deviceID: deviceID,
            index: index,
            name: "",
            secret: Data(repeating: 0, count: ProtocolLimits.channelSecretSize)
        )

        // Delete from local database
        if let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
            try await dataStore.deleteChannel(id: channel.id)
        }
    }

    // MARK: - Local Database Operations

    /// Gets all channels from local database for a device.
    /// - Parameter deviceID: The device UUID
    /// - Returns: Array of channel DTOs
    public func getChannels(deviceID: UUID) async throws -> [ChannelDTO] {
        try await dataStore.fetchChannels(deviceID: deviceID)
    }

    /// Gets a specific channel from local database.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - index: The channel index
    /// - Returns: Channel DTO if found
    public func getChannel(deviceID: UUID, index: UInt8) async throws -> ChannelDTO? {
        try await dataStore.fetchChannel(deviceID: deviceID, index: index)
    }

    /// Gets channels that have messages (for chat list).
    /// - Parameter deviceID: The device UUID
    /// - Returns: Array of channel DTOs with lastMessageDate set
    public func getActiveChannels(deviceID: UUID) async throws -> [ChannelDTO] {
        let channels = try await dataStore.fetchChannels(deviceID: deviceID)
        return channels.filter { $0.lastMessageDate != nil }
    }

    /// Updates a channel's enabled state locally.
    /// - Parameters:
    ///   - channelID: The channel UUID
    ///   - isEnabled: Whether the channel is enabled
    public func setChannelEnabled(channelID: UUID, isEnabled: Bool) async throws {
        guard let dto = try await fetchChannelDTO(id: channelID) else {
            throw ChannelServiceError.channelNotFound
        }

        // Create updated channel and save
        let channel = Channel(
            id: dto.id,
            deviceID: dto.deviceID,
            index: dto.index,
            name: dto.name,
            secret: dto.secret,
            isEnabled: isEnabled,
            lastMessageDate: dto.lastMessageDate,
            unreadCount: dto.unreadCount
        )
        let updatedDTO = ChannelDTO(from: channel)
        try await dataStore.saveChannel(updatedDTO)
    }

    /// Clears unread count for a channel.
    /// - Parameter channelID: The channel UUID
    public func clearUnreadCount(channelID: UUID) async throws {
        guard let dto = try await fetchChannelDTO(id: channelID) else {
            throw ChannelServiceError.channelNotFound
        }

        let channel = Channel(
            id: dto.id,
            deviceID: dto.deviceID,
            index: dto.index,
            name: dto.name,
            secret: dto.secret,
            isEnabled: dto.isEnabled,
            lastMessageDate: dto.lastMessageDate,
            unreadCount: 0
        )
        let updatedDTO = ChannelDTO(from: channel)
        try await dataStore.saveChannel(updatedDTO)
    }

    // MARK: - Public Channel (Slot 0)

    private static let publicChannelSecret = Data([
        0x8b, 0x33, 0x87, 0xe9, 0xc5, 0xcd, 0xea, 0x6a,
        0xc9, 0xe5, 0xed, 0xba, 0xa1, 0x15, 0xcd, 0x72
    ])

    /// Creates or resets the public channel (slot 0).
    /// - Parameter deviceID: The device UUID
    public func setupPublicChannel(deviceID: UUID) async throws {
        try await setChannelWithSecret(
            deviceID: deviceID,
            index: 0,
            name: "Public",
            secret: Self.publicChannelSecret
        )
    }

    /// Checks if the public channel exists locally.
    /// - Parameter deviceID: The device UUID
    /// - Returns: True if public channel exists
    public func hasPublicChannel(deviceID: UUID) async throws -> Bool {
        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 0)
        return channel != nil
    }

    // MARK: - Handlers

    /// Sets a callback for channel updates.
    public func setChannelUpdateHandler(_ handler: @escaping @Sendable ([ChannelDTO]) -> Void) {
        channelUpdateHandler = handler
    }

    // MARK: - Private Helpers

    /// Classifies an error into a ChannelSyncError for the given index
    private func classifyError(_ error: Error, forIndex index: UInt8) -> ChannelSyncError {
        if let channelError = error as? ChannelServiceError {
            switch channelError {
            case .sessionError(let meshError):
                switch meshError {
                case .timeout:
                    return ChannelSyncError(
                        index: index,
                        errorType: .timeout,
                        description: "Request timed out"
                    )
                case .deviceError(let code):
                    return ChannelSyncError(
                        index: index,
                        errorType: .deviceError(code: code),
                        description: "Device error: \(code)"
                    )
                default:
                    return ChannelSyncError(
                        index: index,
                        errorType: .unknown,
                        description: meshError.localizedDescription
                    )
                }
            case .saveFailed(let reason):
                return ChannelSyncError(
                    index: index,
                    errorType: .databaseError,
                    description: "Save failed: \(reason)"
                )
            default:
                return ChannelSyncError(
                    index: index,
                    errorType: .unknown,
                    description: channelError.localizedDescription
                )
            }
        }

        return ChannelSyncError(
            index: index,
            errorType: .unknown,
            description: error.localizedDescription
        )
    }

    private func fetchChannelDTO(id: UUID) async throws -> ChannelDTO? {
        try await dataStore.fetchChannel(id: id)
    }
}

// MARK: - ChannelServiceProtocol Conformance

extension ChannelService: ChannelServiceProtocol {
    // Already implements syncChannels(deviceID:maxChannels:) -> ChannelSyncResult
}
