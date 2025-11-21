import Foundation
import SwiftData

@MainActor
public final class ContactRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func getContact(byPublicKey publicKey: Data) async throws -> Contact? {
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.publicKey == publicKey },
        )
        let contacts = try modelContext.fetch(descriptor)
        return contacts.first
    }

    public func getAllContacts() async throws -> [Contact] {
        let descriptor = FetchDescriptor<Contact>(sortBy: [SortDescriptor(\Contact.name)])
        return try modelContext.fetch(descriptor)
    }

    /// Get all pending contacts awaiting approval
    public func getPendingContacts() async throws -> [Contact] {
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { contact in
                contact.isPending == true
            },
            sortBy: [SortDescriptor(\.lastAdvertisement, order: .reverse)],
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get all approved contacts (non-pending)
    public func getApprovedContacts() async throws -> [Contact] {
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { contact in
                contact.isPending == false
            },
            sortBy: [SortDescriptor(\.name)],
        )
        return try modelContext.fetch(descriptor)
    }

    /// Approve a pending contact
    public func approveContact(_ contact: Contact) async throws {
        contact.isPending = false
        contact.lastModified = Date()
        try modelContext.save()
    }

    /// Reject and delete a pending contact
    public func rejectContact(_ contact: Contact) async throws {
        modelContext.delete(contact)
        try modelContext.save()
    }

    public func getContactsWithLocation() async throws -> [Contact] {
        var descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { contact in
                contact.latitude != nil && contact.longitude != nil
            },
            sortBy: [SortDescriptor(\Contact.name)],
        )
        descriptor.fetchLimit = 1000 // Prevent excessive memory usage
        return try modelContext.fetch(descriptor)
    }

    public func createContact(
        publicKey: Data,
        name: String,
        type: ContactType,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isManuallyAdded: Bool = false,
    ) async throws -> Contact {
        // Check if contact already exists
        if let existing = try await getContact(byPublicKey: publicKey) {
            // Update existing contact
            existing.name = name
            existing.type = type
            existing.latitude = latitude
            existing.longitude = longitude
            existing.lastModified = Date()
            return existing
        } else {
            // Create new contact
            let contact = Contact(
                publicKey: publicKey,
                name: name,
                type: type,
            )
            contact.latitude = latitude
            contact.longitude = longitude
            contact.isManuallyAdded = isManuallyAdded
            contact.lastAdvertisement = Date()
            modelContext.insert(contact)
            return contact
        }
    }

    public func save() async throws {
        try modelContext.save()
    }

    public func deleteContact(_ contact: Contact) async throws {
        modelContext.delete(contact)
        try modelContext.save()
    }
}
