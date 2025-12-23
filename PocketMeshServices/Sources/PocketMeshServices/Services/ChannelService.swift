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
}

// MARK: - Channel Sync Result

public struct ChannelSyncResult: Sendable, Equatable {
    public let channelsSynced: Int
    public let errors: [UInt8]  // Channel indices that failed to sync

    public init(channelsSynced: Int, errors: [UInt8] = []) {
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
    private let logger = Logger(subsystem: "com.pocketmesh", category: "ChannelService")

    /// Callback for channel updates
    private var channelUpdateHandler: (@Sendable ([ChannelDTO]) -> Void)?

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
    ///   - maxChannels: Maximum number of channels to fetch (default: 8)
    /// - Returns: Sync result with number of channels synced
    public func syncChannels(deviceID: UUID, maxChannels: UInt8 = UInt8(ProtocolLimits.maxChannels)) async throws -> ChannelSyncResult {
        var syncedCount = 0
        var errorIndices: [UInt8] = []
        var channels: [ChannelDTO] = []

        for index: UInt8 in 0..<min(maxChannels, UInt8(ProtocolLimits.maxChannels)) {
            do {
                if let channelInfo = try await fetchChannel(index: index) {
                    _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)
                    syncedCount += 1

                    // Fetch the saved channel DTO
                    if let dto = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
                        channels.append(dto)
                    }
                } else {
                    // Channel not configured on device - delete any stale local entry
                    if let staleChannel = try await dataStore.fetchChannel(deviceID: deviceID, index: index) {
                        try await dataStore.deleteChannel(id: staleChannel.id)
                    }
                }
            } catch {
                logger.warning("Failed to sync channel \(index): \(error.localizedDescription)")
                errorIndices.append(index)
            }
        }

        // Notify handler of updated channels
        channelUpdateHandler?(channels)

        return ChannelSyncResult(channelsSynced: syncedCount, errors: errorIndices)
    }

    /// Fetches a single channel from the device.
    /// - Parameter index: The channel index (0-7)
    /// - Returns: Channel info if found, nil if not configured
    public func fetchChannel(index: UInt8) async throws -> ChannelInfo? {
        guard index < ProtocolLimits.maxChannels else {
            throw ChannelServiceError.invalidChannelIndex
        }

        do {
            let meshChannelInfo = try await session.getChannel(index: index)

            // Treat empty channels (cleared slots) as not configured
            if meshChannelInfo.name.isEmpty {
                return nil
            }

            // Convert MeshCore.ChannelInfo to PocketMeshServices.ChannelInfo
            return ChannelInfo(
                index: meshChannelInfo.index,
                name: meshChannelInfo.name,
                secret: meshChannelInfo.secret
            )
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                return nil
            }
            throw ChannelServiceError.sessionError(error)
        }
    }

    /// Sets (creates or updates) a channel on the device.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - index: The channel index (0-7)
    ///   - name: The channel name
    ///   - passphrase: The passphrase to hash into a secret
    public func setChannel(
        deviceID: UUID,
        index: UInt8,
        name: String,
        passphrase: String
    ) async throws {
        guard index < ProtocolLimits.maxChannels else {
            throw ChannelServiceError.invalidChannelIndex
        }

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
    ///   - index: The channel index (0-7)
    ///   - name: The channel name
    ///   - secret: The 16-byte secret (must be exactly 16 bytes)
    public func setChannelWithSecret(
        deviceID: UUID,
        index: UInt8,
        name: String,
        secret: Data
    ) async throws {
        guard index < ProtocolLimits.maxChannels else {
            throw ChannelServiceError.invalidChannelIndex
        }

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
    ///   - index: The channel index (0-7, but 0 is public and shouldn't be cleared)
    public func clearChannel(deviceID: UUID, index: UInt8) async throws {
        guard index < ProtocolLimits.maxChannels else {
            throw ChannelServiceError.invalidChannelIndex
        }

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

    /// Creates or resets the public channel (slot 0).
    /// The public channel has a zero secret and is used for broadcast discovery.
    /// - Parameter deviceID: The device UUID
    public func setupPublicChannel(deviceID: UUID) async throws {
        try await setChannelWithSecret(
            deviceID: deviceID,
            index: 0,
            name: "Public",
            secret: Data(repeating: 0, count: ProtocolLimits.channelSecretSize)
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

    private func fetchChannelDTO(id: UUID) async throws -> ChannelDTO? {
        try await dataStore.fetchChannel(id: id)
    }
}

// MARK: - ChannelServiceProtocol Conformance

extension ChannelService: ChannelServiceProtocol {
    // Already implements syncChannels(deviceID:maxChannels:) -> ChannelSyncResult
}
