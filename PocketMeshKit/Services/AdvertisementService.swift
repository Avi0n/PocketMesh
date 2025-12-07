import Foundation

// MARK: - Advertisement Errors

public enum AdvertisementError: Error, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case protocolError(ProtocolError)
}

// MARK: - Advertisement Service

/// Service for managing device advertisements and discovery.
/// Handles sending self-advertisements and processing incoming adverts.
public actor AdvertisementService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private let dataStore: DataStore

    /// Handler for new advertisement events (for UI updates)
    private var advertHandler: (@Sendable (ContactFrame) -> Void)?

    /// Handler for path update events
    private var pathUpdateHandler: (@Sendable (Data, Int8) -> Void)?

    // MARK: - Initialization

    public init(bleTransport: any BLETransport, dataStore: DataStore) {
        self.bleTransport = bleTransport
        self.dataStore = dataStore
    }

    // MARK: - Event Handlers

    /// Set handler for new advertisement events
    public func setAdvertHandler(_ handler: @escaping @Sendable (ContactFrame) -> Void) {
        advertHandler = handler
    }

    /// Set handler for path update events
    public func setPathUpdateHandler(_ handler: @escaping @Sendable (Data, Int8) -> Void) {
        pathUpdateHandler = handler
    }

    // MARK: - Send Advertisement

    /// Send self advertisement to the mesh network
    /// - Parameter flood: If true, sends flood advertisement (reaches all nodes).
    ///                   If false, sends zero-hop advertisement (direct only).
    /// - Returns: True if advertisement was sent successfully
    public func sendSelfAdvertisement(flood: Bool) async throws -> Bool {
        guard await bleTransport.connectionState == .ready else {
            throw AdvertisementError.notConnected
        }

        let command = FrameCodec.encodeSendSelfAdvert(flood: flood)
        guard let response = try await bleTransport.send(command) else {
            throw AdvertisementError.sendFailed
        }

        guard response.first == ResponseCode.ok.rawValue else {
            if response.first == ResponseCode.error.rawValue,
               response.count > 1,
               let error = ProtocolError(rawValue: response[1]) {
                throw AdvertisementError.protocolError(error)
            }
            throw AdvertisementError.invalidResponse
        }

        return true
    }

    // MARK: - Update Node Name

    /// Set the node's advertised name
    /// - Parameter name: The name to advertise (max 31 characters)
    public func setAdvertName(_ name: String) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw AdvertisementError.notConnected
        }

        let command = FrameCodec.encodeSetAdvertName(name)
        guard let response = try await bleTransport.send(command) else {
            throw AdvertisementError.sendFailed
        }

        guard response.first == ResponseCode.ok.rawValue else {
            if response.first == ResponseCode.error.rawValue,
               response.count > 1,
               let error = ProtocolError(rawValue: response[1]) {
                throw AdvertisementError.protocolError(error)
            }
            throw AdvertisementError.invalidResponse
        }
    }

    // MARK: - Update Location

    /// Set the node's advertised GPS coordinates
    /// - Parameters:
    ///   - latitude: Latitude in degrees (-90 to 90)
    ///   - longitude: Longitude in degrees (-180 to 180)
    public func setAdvertLocation(latitude: Double, longitude: Double) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw AdvertisementError.notConnected
        }

        // Convert to fixed-point (scaled by 1e6)
        let latInt = Int32(latitude * 1_000_000)
        let lonInt = Int32(longitude * 1_000_000)

        let command = FrameCodec.encodeSetAdvertLatLon(latitude: latInt, longitude: lonInt)
        guard let response = try await bleTransport.send(command) else {
            throw AdvertisementError.sendFailed
        }

        guard response.first == ResponseCode.ok.rawValue else {
            if response.first == ResponseCode.error.rawValue,
               response.count > 1,
               let error = ProtocolError(rawValue: response[1]) {
                throw AdvertisementError.protocolError(error)
            }
            throw AdvertisementError.invalidResponse
        }
    }

    // MARK: - Push Notification Handling

    /// Process incoming push notification from device
    /// - Parameter data: Raw push data from BLE
    /// - Returns: True if the push was handled
    public func handlePush(_ data: Data, deviceID: UUID) async -> Bool {
        guard !data.isEmpty else { return false }

        guard let pushCode = PushCode(rawValue: data[0]) else {
            return false
        }

        switch pushCode {
        case .advert:
            return await handleAdvertPush(data, deviceID: deviceID)
        case .newAdvert:
            return await handleNewAdvertPush(data, deviceID: deviceID)
        case .pathUpdated:
            return await handlePathUpdatedPush(data, deviceID: deviceID)
        default:
            return false
        }
    }

    // MARK: - Private Push Handlers

    /// Handle PUSH_CODE_ADVERT (0x80) - Existing contact updated
    private func handleAdvertPush(_ data: Data, deviceID: UUID) async -> Bool {
        // PUSH_CODE_ADVERT contains just the public key prefix and updated timestamp
        // Format: [0x80][pub_key_prefix:6][timestamp:4]
        guard data.count >= 11 else { return false }

        let publicKeyPrefix = data.subdata(in: 1..<7)
        let timestamp = data.subdata(in: 7..<11).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }

        // Update the contact's last advert timestamp in the database
        do {
            if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKeyPrefix: publicKeyPrefix) {
                // Create a modified version with updated timestamp
                let frame = ContactFrame(
                    publicKey: contact.publicKey,
                    type: contact.type,
                    flags: contact.flags,
                    outPathLength: contact.outPathLength,
                    outPath: contact.outPath,
                    name: contact.name,
                    lastAdvertTimestamp: timestamp,
                    latitude: contact.latitude,
                    longitude: contact.longitude,
                    lastModified: UInt32(Date().timeIntervalSince1970)
                )
                _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)
                advertHandler?(frame)
            }
            return true
        } catch {
            return false
        }
    }

    /// Handle PUSH_CODE_NEW_ADVERT (0x8A) - New contact discovered (manual add mode)
    private func handleNewAdvertPush(_ data: Data, deviceID: UUID) async -> Bool {
        // PUSH_CODE_NEW_ADVERT contains full contact frame
        guard data.count >= 147 else { return false }

        do {
            let contactFrame = try FrameCodec.decodeContact(from: data)
            _ = try await dataStore.saveContact(deviceID: deviceID, from: contactFrame)
            advertHandler?(contactFrame)
            return true
        } catch {
            return false
        }
    }

    /// Handle PUSH_CODE_PATH_UPDATED (0x81) - Contact path changed
    private func handlePathUpdatedPush(_ data: Data, deviceID: UUID) async -> Bool {
        // Format: [0x81][pub_key_prefix:6][new_path_len:1]
        guard data.count >= 8 else { return false }

        let publicKeyPrefix = data.subdata(in: 1..<7)
        let newPathLength = Int8(bitPattern: data[7])

        do {
            if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKeyPrefix: publicKeyPrefix) {
                // Update the contact's path length
                let frame = ContactFrame(
                    publicKey: contact.publicKey,
                    type: contact.type,
                    flags: contact.flags,
                    outPathLength: newPathLength,
                    outPath: contact.outPath,
                    name: contact.name,
                    lastAdvertTimestamp: contact.lastAdvertTimestamp,
                    latitude: contact.latitude,
                    longitude: contact.longitude,
                    lastModified: UInt32(Date().timeIntervalSince1970)
                )
                _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)
                pathUpdateHandler?(publicKeyPrefix, newPathLength)
            }
            return true
        } catch {
            return false
        }
    }
}
