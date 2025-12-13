import Foundation

// MARK: - Contact Service Errors

public enum ContactServiceError: Error, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case syncInterrupted
    case contactNotFound
    case contactTableFull
    case protocolError(ProtocolError)
}

// MARK: - Sync Result

/// Result of a contact sync operation
public struct ContactSyncResult: Sendable {
    public let contactsReceived: Int
    public let lastSyncTimestamp: UInt32
    public let isIncremental: Bool

    public init(contactsReceived: Int, lastSyncTimestamp: UInt32, isIncremental: Bool) {
        self.contactsReceived = contactsReceived
        self.lastSyncTimestamp = lastSyncTimestamp
        self.isIncremental = isIncremental
    }
}

// MARK: - Contact Service

/// Service for managing mesh network contacts.
/// Handles contact discovery, sync, add/update/remove operations.
public actor ContactService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private let dataStore: DataStore

    /// Handler for contact updates (for UI refresh)
    private var contactUpdateHandler: (@Sendable ([ContactDTO]) -> Void)?

    /// Progress handler for sync operations
    private var syncProgressHandler: (@Sendable (Int, Int) -> Void)?

    // MARK: - Initialization

    public init(bleTransport: any BLETransport, dataStore: DataStore) {
        self.bleTransport = bleTransport
        self.dataStore = dataStore
    }

    // MARK: - Event Handlers

    /// Set handler for contact updates
    public func setContactUpdateHandler(_ handler: @escaping @Sendable ([ContactDTO]) -> Void) {
        contactUpdateHandler = handler
    }

    /// Set progress handler for sync operations
    public func setSyncProgressHandler(_ handler: @escaping @Sendable (Int, Int) -> Void) {
        syncProgressHandler = handler
    }

    // MARK: - Contact Sync

    /// Sync all contacts from device
    /// - Parameters:
    ///   - deviceID: The device to sync from
    ///   - since: Optional timestamp for incremental sync (only contacts modified after this time)
    /// - Returns: Sync result with count and timestamp
    public func syncContacts(deviceID: UUID, since: UInt32? = nil) async throws -> ContactSyncResult {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        // Step 1: Request contact list
        let command = FrameCodec.encodeGetContacts(since: since)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        // Check for error response
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1, let error = ProtocolError(rawValue: response[1]) {
                throw ContactServiceError.protocolError(error)
            }
            throw ContactServiceError.invalidResponse
        }

        // Parse contacts start response
        guard response.first == ResponseCode.contactsStart.rawValue,
              response.count >= 5 else {
            throw ContactServiceError.invalidResponse
        }

        let totalContacts = Int(response.subdata(in: 1..<5).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        })

        syncProgressHandler?(0, totalContacts)

        // Step 2: Receive all contacts
        var receivedCount = 0
        var lastTimestamp: UInt32 = 0
        var contacts: [ContactFrame] = []

        while true {
            // Request next contact (empty command, device sends next)
            guard let contactData = try await bleTransport.send(Data()) else {
                throw ContactServiceError.syncInterrupted
            }

            // Check if end of contacts
            if contactData.first == ResponseCode.endOfContacts.rawValue {
                if contactData.count >= 5 {
                    lastTimestamp = contactData.subdata(in: 1..<5).withUnsafeBytes {
                        $0.load(as: UInt32.self).littleEndian
                    }
                }
                break
            }

            // Parse contact
            guard contactData.first == ResponseCode.contact.rawValue else {
                // Unexpected response, continue trying
                continue
            }

            do {
                let contactFrame = try FrameCodec.decodeContact(from: contactData)
                contacts.append(contactFrame)
                _ = try await dataStore.saveContact(deviceID: deviceID, from: contactFrame)
                receivedCount += 1
                syncProgressHandler?(receivedCount, totalContacts)
            } catch {
                // Skip malformed contacts
                continue
            }
        }

        // Notify handler with all contacts
        let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        contactUpdateHandler?(allContacts)

        return ContactSyncResult(
            contactsReceived: receivedCount,
            lastSyncTimestamp: lastTimestamp,
            isIncremental: since != nil
        )
    }

    // MARK: - Get Contact

    /// Get a specific contact by public key
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    /// - Returns: The contact if found
    public func getContact(deviceID: UUID, publicKey: Data) async throws -> ContactDTO? {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeGetContactByKey(publicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        // Check for not found
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 && response[1] == ProtocolError.notFound.rawValue {
                return nil
            }
            if let error = ProtocolError(rawValue: response[1]) {
                throw ContactServiceError.protocolError(error)
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.contact.rawValue else {
            throw ContactServiceError.invalidResponse
        }

        let contactFrame = try FrameCodec.decodeContact(from: response)
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contactFrame)
        return try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey)
    }

    // MARK: - Add/Update Contact

    /// Add or update a contact on the device
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - contact: The contact to add/update
    public func addOrUpdateContact(deviceID: UUID, contact: ContactFrame) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeAddUpdateContact(contact)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 {
                if response[1] == ProtocolError.tableFull.rawValue {
                    throw ContactServiceError.contactTableFull
                }
                if let error = ProtocolError(rawValue: response[1]) {
                    throw ContactServiceError.protocolError(error)
                }
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw ContactServiceError.invalidResponse
        }

        // Save to local database
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        // Notify handler
        let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        contactUpdateHandler?(allContacts)
    }

    // MARK: - Remove Contact

    /// Remove a contact from the device
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    public func removeContact(deviceID: UUID, publicKey: Data) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeRemoveContact(publicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 {
                if response[1] == ProtocolError.notFound.rawValue {
                    throw ContactServiceError.contactNotFound
                }
                if let error = ProtocolError(rawValue: response[1]) {
                    throw ContactServiceError.protocolError(error)
                }
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw ContactServiceError.invalidResponse
        }

        // Remove from local database
        if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) {
            try await dataStore.deleteContact(id: contact.id)
        }

        // Notify handler
        let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        contactUpdateHandler?(allContacts)
    }

    // MARK: - Reset Path

    /// Reset the path for a contact (force rediscovery)
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    public func resetPath(deviceID: UUID, publicKey: Data) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeResetPath(publicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 {
                if response[1] == ProtocolError.notFound.rawValue {
                    throw ContactServiceError.contactNotFound
                }
                if let error = ProtocolError(rawValue: response[1]) {
                    throw ContactServiceError.protocolError(error)
                }
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw ContactServiceError.invalidResponse
        }

        // Update local contact to show flood routing
        if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) {
            let frame = ContactFrame(
                publicKey: contact.publicKey,
                type: contact.type,
                flags: contact.flags,
                outPathLength: -1,  // Flood routing
                outPath: Data(),
                name: contact.name,
                lastAdvertTimestamp: contact.lastAdvertTimestamp,
                latitude: contact.latitude,
                longitude: contact.longitude,
                lastModified: UInt32(Date().timeIntervalSince1970)
            )
            _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)
        }
    }

    // MARK: - Path Discovery

    /// Send a path discovery request to find optimal route to contact
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    public func sendPathDiscovery(deviceID: UUID, publicKey: Data) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodePathDiscovery(recipientPublicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        // Check for error response
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 {
                if response[1] == ProtocolError.notFound.rawValue {
                    throw ContactServiceError.contactNotFound
                }
                if let error = ProtocolError(rawValue: response[1]) {
                    throw ContactServiceError.protocolError(error)
                }
            }
            throw ContactServiceError.invalidResponse
        }

        // Path discovery is async - response comes via PUSH_CODE_PATH_DISCOVERY_RESPONSE
        // Firmware always returns SENT (0x06) with tag and timeout data
        guard response.first == ResponseCode.sent.rawValue else {
            throw ContactServiceError.invalidResponse
        }
    }

    // MARK: - Advert Path Query

    /// Query the radio's cached advertisement path for a contact
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    /// - Returns: The cached path info if available, nil if no cached path
    public func getAdvertPath(deviceID: UUID, publicKey: Data) async throws -> AdvertPathResponse? {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeGetAdvertPath(publicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        // Check for not found (no cached path)
        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 && response[1] == ProtocolError.notFound.rawValue {
                return nil  // No cached path - this is expected
            }
            if response.count > 1, let error = ProtocolError(rawValue: response[1]) {
                throw ContactServiceError.protocolError(error)
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.advertPath.rawValue else {
            throw ContactServiceError.invalidResponse
        }

        return try FrameCodec.decodeAdvertPathResponse(from: response)
    }

    /// Set a specific path for a contact
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    ///   - path: The path data (repeater hashes)
    ///   - pathLength: The path length (-1 for flood, 0 for direct, >0 for routed)
    public func setPath(deviceID: UUID, publicKey: Data, path: Data, pathLength: Int8) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        // Get current contact to preserve other fields
        guard let existingContact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) else {
            throw ContactServiceError.contactNotFound
        }

        // Create updated contact frame with new path
        let updatedFrame = ContactFrame(
            publicKey: existingContact.publicKey,
            type: existingContact.type,
            flags: existingContact.flags,
            outPathLength: pathLength,
            outPath: path,
            name: existingContact.name,
            lastAdvertTimestamp: existingContact.lastAdvertTimestamp,
            latitude: existingContact.latitude,
            longitude: existingContact.longitude,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )

        // Send update to device
        try await addOrUpdateContact(deviceID: deviceID, contact: updatedFrame)
    }

    // MARK: - Share Contact

    /// Share a contact via zero-hop broadcast
    /// - Parameter publicKey: The contact's 32-byte public key to share
    public func shareContact(publicKey: Data) async throws {
        guard await bleTransport.connectionState == .ready else {
            throw ContactServiceError.notConnected
        }

        let command = FrameCodec.encodeShareContact(publicKey: publicKey)
        guard let response = try await bleTransport.send(command) else {
            throw ContactServiceError.sendFailed
        }

        if response.first == ResponseCode.error.rawValue {
            if response.count > 1 {
                if response[1] == ProtocolError.notFound.rawValue {
                    throw ContactServiceError.contactNotFound
                }
                if let error = ProtocolError(rawValue: response[1]) {
                    throw ContactServiceError.protocolError(error)
                }
            }
            throw ContactServiceError.invalidResponse
        }

        guard response.first == ResponseCode.ok.rawValue else {
            throw ContactServiceError.invalidResponse
        }
    }

    // MARK: - Local Database Operations

    /// Get all contacts for a device from local database
    public func getContacts(deviceID: UUID) async throws -> [ContactDTO] {
        try await dataStore.fetchContacts(deviceID: deviceID)
    }

    /// Get conversations (contacts with messages) from local database
    public func getConversations(deviceID: UUID) async throws -> [ContactDTO] {
        try await dataStore.fetchConversations(deviceID: deviceID)
    }

    /// Get a contact by ID from local database
    public func getContactByID(_ id: UUID) async throws -> ContactDTO? {
        try await dataStore.fetchContact(id: id)
    }

    /// Update local contact preferences (nickname, blocked, favorite)
    public func updateContactPreferences(
        contactID: UUID,
        nickname: String? = nil,
        isBlocked: Bool? = nil,
        isFavorite: Bool? = nil
    ) async throws {
        guard let existing = try await dataStore.fetchContact(id: contactID) else {
            throw ContactServiceError.contactNotFound
        }

        // Create updated DTO preserving existing values
        let updated = ContactDTO(
            from: Contact(
                id: existing.id,
                deviceID: existing.deviceID,
                publicKey: existing.publicKey,
                name: existing.name,
                typeRawValue: existing.typeRawValue,
                flags: existing.flags,
                outPathLength: existing.outPathLength,
                outPath: existing.outPath,
                lastAdvertTimestamp: existing.lastAdvertTimestamp,
                latitude: existing.latitude,
                longitude: existing.longitude,
                lastModified: existing.lastModified,
                nickname: nickname ?? existing.nickname,
                isBlocked: isBlocked ?? existing.isBlocked,
                isFavorite: isFavorite ?? existing.isFavorite,
                lastMessageDate: existing.lastMessageDate,
                unreadCount: existing.unreadCount
            )
        )

        try await dataStore.saveContact(updated)
    }

}
