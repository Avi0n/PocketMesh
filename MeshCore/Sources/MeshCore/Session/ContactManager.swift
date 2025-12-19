import Foundation
import os

/// Manages contact storage, caching, and lifecycle.
///
/// This is a non-Sendable struct designed to be owned by `MeshCoreSession`.
/// All access is synchronous within the session's actor isolation domain.
struct ContactManager {
    private let logger = Logger(subsystem: "MeshCore", category: "ContactManager")

    // MARK: - State

    private var contacts: [String: MeshContact] = [:]
    private var pendingContacts: [String: MeshContact] = [:]
    private var lastModified: Date?
    private var isDirty = true
    private var autoUpdate = false

    // MARK: - Public Properties

    /// All cached contacts
    var cachedContacts: [MeshContact] {
        Array(contacts.values)
    }

    /// Pending contacts awaiting confirmation
    var cachedPendingContacts: [MeshContact] {
        Array(pendingContacts.values)
    }

    /// Whether contacts need refresh
    var needsRefresh: Bool {
        isDirty
    }

    /// Last modified date from device
    var contactsLastModified: Date? {
        lastModified
    }

    /// Whether there are any contacts in cache
    var isEmpty: Bool {
        contacts.isEmpty
    }

    // MARK: - Lookup Methods

    /// Find contact by advertised name
    /// - Parameters:
    ///   - name: Name to search for
    ///   - exactMatch: If true, requires exact case-insensitive match; otherwise uses localizedStandardContains
    func getByName(_ name: String, exactMatch: Bool = false) -> MeshContact? {
        if exactMatch {
            return contacts.values.first { $0.advertisedName.lowercased() == name.lowercased() }
        }
        return contacts.values.first { $0.advertisedName.localizedStandardContains(name) }
    }

    /// Find contact by public key prefix (hex string)
    func getByKeyPrefix(_ prefix: String) -> MeshContact? {
        let normalizedPrefix = prefix.lowercased()
        return contacts.values.first { $0.publicKey.hexString.lowercased().hasPrefix(normalizedPrefix) }
    }

    /// Find contact by public key prefix (Data)
    func getByKeyPrefix(_ prefix: Data) -> MeshContact? {
        contacts.values.first { $0.publicKey.prefix(prefix.count) == prefix }
    }

    /// Find contact by full public key
    func getByPublicKey(_ key: Data) -> MeshContact? {
        contacts[key.hexString]
    }

    // MARK: - Cache Management

    /// Store a single contact in cache
    mutating func store(_ contact: MeshContact) {
        contacts[contact.id] = contact
    }

    /// Update cache with new contacts from device
    mutating func updateCache(_ newContacts: [MeshContact], lastModified: Date) {
        for contact in newContacts {
            contacts[contact.id] = contact
        }
        self.lastModified = lastModified
        isDirty = false
        logger.debug("Updated cache with \(newContacts.count) contacts")
    }

    /// Mark cache as not dirty
    mutating func markClean(lastModified: Date) {
        self.lastModified = lastModified
        isDirty = false
    }

    /// Mark cache as needing refresh
    mutating func markDirty() {
        isDirty = true
    }

    /// Add a pending contact
    mutating func addPending(_ contact: MeshContact) {
        pendingContacts[contact.id] = contact
    }

    /// Pop a pending contact by public key
    mutating func popPending(publicKey: String) -> MeshContact? {
        pendingContacts.removeValue(forKey: publicKey)
    }

    /// Flush all pending contacts
    mutating func flushPending() {
        pendingContacts.removeAll()
    }

    /// Remove a contact from cache
    mutating func remove(_ contactId: String) {
        contacts.removeValue(forKey: contactId)
        pendingContacts.removeValue(forKey: contactId)
        isDirty = true
    }

    /// Clear all cached data
    mutating func clear() {
        contacts.removeAll()
        pendingContacts.removeAll()
        lastModified = nil
        isDirty = true
    }

    // MARK: - Auto-Update

    var isAutoUpdateEnabled: Bool {
        autoUpdate
    }

    mutating func setAutoUpdate(_ enabled: Bool) {
        autoUpdate = enabled
    }

    /// Track changes from device event stream
    mutating func trackChanges(from event: MeshEvent) {
        switch event {
        case .contact(let contact):
            contacts[contact.id] = contact
        case .newContact(let contact):
            addPending(contact)
            isDirty = true
        case .contactsEnd(let modifiedDate):
            lastModified = modifiedDate
            isDirty = false
        case .advertisement, .pathUpdate:
            isDirty = true
        default:
            break
        }
    }
}
