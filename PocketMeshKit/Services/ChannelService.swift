import Foundation
import CryptoKit

// MARK: - Channel Service Errors

public enum ChannelServiceError: Error, Sendable {
    case notConnected
    case channelNotFound
    case invalidChannelIndex
    case secretHashingFailed
    case saveFailed(String)
    case sendFailed(String)
    case protocolError(ProtocolError)
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

    private let bleTransport: any BLETransport
    private let dataStore: DataStore

    /// Callback for channel updates
    private var channelUpdateHandler: (@Sendable ([ChannelDTO]) -> Void)?

    // MARK: - Initialization

    public init(
        bleTransport: any BLETransport,
        dataStore: DataStore
    ) {
        self.bleTransport = bleTransport
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
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw ChannelServiceError.notConnected
        }

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
                }
            } catch ChannelServiceError.channelNotFound {
                // Channel not configured on device, skip
                continue
            } catch {
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

        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw ChannelServiceError.notConnected
        }

        let frameData = FrameCodec.encodeGetChannel(index: index)

        guard let response = try await bleTransport.send(frameData),
              !response.isEmpty else {
            throw ChannelServiceError.sendFailed("No response received")
        }

        // Check for not found (channel not configured)
        if response[0] == ResponseCode.error.rawValue {
            if response.count >= 2, response[1] == ProtocolError.notFound.rawValue {
                return nil
            }
            if let error = ProtocolError(rawValue: response[1]) {
                throw ChannelServiceError.protocolError(error)
            }
            throw ChannelServiceError.sendFailed("Unknown protocol error")
        }

        return try FrameCodec.decodeChannelInfo(from: response)
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

        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw ChannelServiceError.notConnected
        }

        let secret = Self.hashSecret(passphrase)

        let frameData = FrameCodec.encodeSetChannel(index: index, name: name, secret: secret)

        guard let response = try await bleTransport.send(frameData),
              !response.isEmpty else {
            throw ChannelServiceError.sendFailed("No response received")
        }

        // Check for error
        if response[0] == ResponseCode.error.rawValue {
            if response.count >= 2, let error = ProtocolError(rawValue: response[1]) {
                throw ChannelServiceError.protocolError(error)
            }
            throw ChannelServiceError.sendFailed("Unknown protocol error")
        }

        guard response[0] == ResponseCode.ok.rawValue else {
            throw ChannelServiceError.sendFailed("Unexpected response code")
        }

        // Save to local database
        let channelInfo = ChannelInfo(index: index, name: name, secret: secret)
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        // Notify handler of update
        let channels = try await dataStore.fetchChannels(deviceID: deviceID)
        channelUpdateHandler?(channels)
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

        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw ChannelServiceError.notConnected
        }

        let frameData = FrameCodec.encodeSetChannel(index: index, name: name, secret: secret)

        guard let response = try await bleTransport.send(frameData),
              !response.isEmpty else {
            throw ChannelServiceError.sendFailed("No response received")
        }

        if response[0] == ResponseCode.error.rawValue {
            if response.count >= 2, let error = ProtocolError(rawValue: response[1]) {
                throw ChannelServiceError.protocolError(error)
            }
            throw ChannelServiceError.sendFailed("Unknown protocol error")
        }

        guard response[0] == ResponseCode.ok.rawValue else {
            throw ChannelServiceError.sendFailed("Unexpected response code")
        }

        // Save to local database
        let channelInfo = ChannelInfo(index: index, name: name, secret: secret)
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        // Notify handler of update
        let channels = try await dataStore.fetchChannels(deviceID: deviceID)
        channelUpdateHandler?(channels)
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
