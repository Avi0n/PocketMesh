import Foundation
import MeshCore
import os

// MARK: - Contact Service Errors

public enum ContactServiceError: Error, Sendable, LocalizedError {
    case notConnected
    case sendFailed
    case invalidResponse
    case syncInterrupted
    case contactNotFound
    case contactTableFull
    case sessionError(MeshCoreError)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to radio"
        case .sendFailed:
            return "Failed to send message"
        case .invalidResponse:
            return "Invalid response from device"
        case .syncInterrupted:
            return "Sync was interrupted"
        case .contactNotFound:
            return "Contact not found on device"
        case .contactTableFull:
            return "Device node list is full"
        case .sessionError(let error):
            return error.localizedDescription
        }
    }
}

/// Reason for contact cleanup (deletion or blocking)
public enum ContactCleanupReason: Sendable {
    case deleted
    case blocked
    case unblocked
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

    private let session: any MeshCoreSessionProtocol
    private let dataStore: any PersistenceStoreProtocol
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "ContactService")

    /// Sync coordinator for UI refresh notifications
    private weak var syncCoordinator: SyncCoordinator?

    /// Progress handler for sync operations
    private var syncProgressHandler: (@Sendable (Int, Int) -> Void)?

    /// Cleanup handler called when a contact is deleted or blocked
    private var cleanupHandler: (@Sendable (UUID, ContactCleanupReason, Data) async -> Void)?

    // MARK: - Initialization

    public init(session: any MeshCoreSessionProtocol, dataStore: any PersistenceStoreProtocol) {
        self.session = session
        self.dataStore = dataStore
    }

    // MARK: - Configuration

    /// Set the sync coordinator for UI refresh notifications
    public func setSyncCoordinator(_ coordinator: SyncCoordinator) {
        self.syncCoordinator = coordinator
    }

    /// Set progress handler for sync operations
    public func setSyncProgressHandler(_ handler: @escaping @Sendable (Int, Int) -> Void) {
        syncProgressHandler = handler
    }

    /// Set handler for contact cleanup operations (deletion/blocking)
    public func setCleanupHandler(_ handler: @escaping @Sendable (UUID, ContactCleanupReason, Data) async -> Void) {
        cleanupHandler = handler
    }

    // MARK: - Contact Sync

    /// Sync all contacts from device
    /// - Parameters:
    ///   - deviceID: The device to sync from
    ///   - since: Optional date for incremental sync (only contacts modified after this time)
    /// - Returns: Sync result with count and timestamp
    public func syncContacts(deviceID: UUID, since: Date? = nil) async throws -> ContactSyncResult {
        do {
            let meshContacts = try await session.getContacts(since: since)

            syncProgressHandler?(0, meshContacts.count)

            var receivedCount = 0
            var lastTimestamp: UInt32 = 0

            // Build set of public keys from device for cleanup
            let devicePublicKeys = Set(meshContacts.map(\.publicKey))

            for meshContact in meshContacts {
                let frame = meshContact.toContactFrame()
                _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)
                receivedCount += 1

                let modifiedTimestamp = UInt32(meshContact.lastModified.timeIntervalSince1970)
                if modifiedTimestamp > lastTimestamp {
                    lastTimestamp = modifiedTimestamp
                }

                syncProgressHandler?(receivedCount, meshContacts.count)
            }

            // On full sync, remove local contacts that no longer exist on device
            if since == nil {
                let localContacts = try await dataStore.fetchContacts(deviceID: deviceID)
                for localContact in localContacts where !devicePublicKeys.contains(localContact.publicKey) {
                    try await dataStore.deleteMessagesForContact(contactID: localContact.id)
                    try await dataStore.deleteContact(id: localContact.id)
                    await cleanupHandler?(localContact.id, .deleted, localContact.publicKey)
                }
            }

            return ContactSyncResult(
                contactsReceived: receivedCount,
                lastSyncTimestamp: lastTimestamp,
                isIncremental: since != nil
            )
        } catch let error as MeshCoreError {
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Get Contact

    /// Get a specific contact by public key from local database
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    /// - Returns: The contact if found
    public func getContact(deviceID: UUID, publicKey: Data) async throws -> ContactDTO? {
        try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey)
    }

    // MARK: - Add/Update Contact

    /// Add or update a contact on the device
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - contact: The contact to add/update
    public func addOrUpdateContact(deviceID: UUID, contact: ContactFrame) async throws {
        do {
            let meshContact = contact.toMeshContact()
            try await session.addContact(meshContact)

            // Save to local database
            _ = try await dataStore.saveContact(deviceID: deviceID, from: contact)

            // Notify UI to refresh contacts list
            await syncCoordinator?.notifyContactsChanged()
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.tableFull.rawValue {
                throw ContactServiceError.contactTableFull
            }
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Remove Contact

    /// Remove a contact from the device
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    public func removeContact(deviceID: UUID, publicKey: Data) async throws {
        do {
            try await session.removeContact(publicKey: publicKey)

            // Remove from local database
            if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) {
                let contactID = contact.id

                // Delete associated messages first
                try await dataStore.deleteMessagesForContact(contactID: contactID)

                // Delete the contact
                try await dataStore.deleteContact(id: contactID)

                // Trigger cleanup (notifications, badge, session)
                await cleanupHandler?(contactID, .deleted, publicKey)
            }

            // Notify UI to refresh contacts list
            await syncCoordinator?.notifyContactsChanged()
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                throw ContactServiceError.contactNotFound
            }
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Reset Path

    /// Reset the path for a contact (force rediscovery)
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    public func resetPath(deviceID: UUID, publicKey: Data) async throws {
        do {
            try await session.resetPath(publicKey: publicKey)

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
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                throw ContactServiceError.contactNotFound
            }
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Path Discovery

    /// Send a path discovery request to find optimal route to contact
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    /// - Returns: MessageSentInfo containing the estimated timeout from firmware
    public func sendPathDiscovery(deviceID: UUID, publicKey: Data) async throws -> MessageSentInfo {
        do {
            return try await session.sendPathDiscovery(to: publicKey)
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                throw ContactServiceError.contactNotFound
            }
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Set Path

    /// Set a specific path for a contact
    /// - Parameters:
    ///   - deviceID: The device ID
    ///   - publicKey: The contact's 32-byte public key
    ///   - path: The path data (repeater hashes)
    ///   - pathLength: The path length (-1 for flood, 0 for direct, >0 for routed)
    public func setPath(deviceID: UUID, publicKey: Data, path: Data, pathLength: Int8) async throws {
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
        do {
            try await session.shareContact(publicKey: publicKey)
        } catch let error as MeshCoreError {
            if case .deviceError(let code) = error, code == ProtocolError.notFound.rawValue {
                throw ContactServiceError.contactNotFound
            }
            throw ContactServiceError.sessionError(error)
        }
    }

    // MARK: - Export/Import Contact

    /// Export a contact to a shareable URI (legacy firmware call)
    /// - Parameter publicKey: The contact's 32-byte public key (nil for self)
    /// - Returns: Contact URI string
    @available(*, deprecated, message: "Use exportContactURI(name:publicKey:type:) instead")
    public func exportContact(publicKey: Data? = nil) async throws -> String {
        do {
            return try await session.exportContact(publicKey: publicKey)
        } catch let error as MeshCoreError {
            throw ContactServiceError.sessionError(error)
        }
    }

    /// Build a shareable contact URI from contact information
    /// - Parameters:
    ///   - name: The contact's advertised name
    ///   - publicKey: The contact's 32-byte public key
    ///   - type: The contact type (chat, repeater, room)
    /// - Returns: Contact URI string in format: meshcore://contact/add?name=...&public_key=...&type=...
    public static func exportContactURI(name: String, publicKey: Data, type: ContactType) -> String {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "meshcore://contact/add?name=\(encodedName)&public_key=\(publicKey.hexString())&type=\(type.rawValue)"
    }

    /// Import a contact from card data
    /// - Parameter cardData: The contact card data
    public func importContact(cardData: Data) async throws {
        do {
            try await session.importContact(cardData: cardData)
        } catch let error as MeshCoreError {
            throw ContactServiceError.sessionError(error)
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

        // Check blocking state transitions
        let isBeingBlocked = isBlocked == true && !existing.isBlocked
        let isBeingUnblocked = isBlocked == false && existing.isBlocked

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
                unreadCount: isBeingBlocked ? 0 : existing.unreadCount,
                isDiscovered: existing.isDiscovered,
                ocvPreset: existing.ocvPreset,
                customOCVArrayString: existing.customOCVArrayString
            )
        )

        try await dataStore.saveContact(updated)

        // Trigger cleanup for blocking state changes
        if isBeingBlocked {
            await cleanupHandler?(contactID, .blocked, existing.publicKey)
        } else if isBeingUnblocked {
            await cleanupHandler?(contactID, .unblocked, existing.publicKey)
        }
    }

    /// Get discovered contacts (from NEW_ADVERT push, not yet added to device)
    public func getDiscoveredContacts(deviceID: UUID) async throws -> [ContactDTO] {
        try await dataStore.fetchDiscoveredContacts(deviceID: deviceID)
    }

    /// Confirm a discovered contact (mark as added to device)
    public func confirmContact(id: UUID) async throws {
        try await dataStore.confirmContact(id: id)
    }

    /// Updates OCV settings for a contact
    /// - Parameters:
    ///   - contactID: The contact's ID
    ///   - preset: The OCV preset name
    ///   - customArray: Custom OCV array string (for custom preset)
    public func updateContactOCVSettings(
        contactID: UUID,
        preset: String,
        customArray: String?
    ) async throws {
        guard let existing = try await dataStore.fetchContact(id: contactID) else {
            throw ContactServiceError.contactNotFound
        }

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
                nickname: existing.nickname,
                isBlocked: existing.isBlocked,
                isFavorite: existing.isFavorite,
                lastMessageDate: existing.lastMessageDate,
                unreadCount: existing.unreadCount,
                isDiscovered: existing.isDiscovered,
                ocvPreset: preset,
                customOCVArrayString: customArray
            )
        )

        try await dataStore.saveContact(updated)
    }
}

// MARK: - ContactServiceProtocol Conformance

extension ContactService: ContactServiceProtocol {
    // Already implements syncContacts(deviceID:since:) -> ContactSyncResult
}

// MARK: - MeshContact Extensions

extension MeshContact {
    /// Converts a MeshContact to a ContactFrame for persistence
    func toContactFrame() -> ContactFrame {
        ContactFrame(
            publicKey: publicKey,
            type: ContactType(rawValue: type) ?? .chat,
            flags: flags,
            outPathLength: outPathLength,
            outPath: outPath,
            name: advertisedName,
            lastAdvertTimestamp: UInt32(lastAdvertisement.timeIntervalSince1970),
            latitude: latitude,
            longitude: longitude,
            lastModified: UInt32(lastModified.timeIntervalSince1970)
        )
    }
}

// MARK: - ContactFrame Extensions

extension ContactFrame {
    /// Converts a ContactFrame to a MeshContact for session operations
    func toMeshContact() -> MeshContact {
        MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: type.rawValue,
            flags: flags,
            outPathLength: outPathLength,
            outPath: outPath,
            advertisedName: name,
            lastAdvertisement: Date(timeIntervalSince1970: TimeInterval(lastAdvertTimestamp)),
            latitude: latitude,
            longitude: longitude,
            lastModified: Date(timeIntervalSince1970: TimeInterval(lastModified))
        )
    }
}
