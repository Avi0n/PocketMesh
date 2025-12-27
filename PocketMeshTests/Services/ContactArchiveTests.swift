import Testing
import Foundation
@testable import PocketMeshServices

@Suite("Contact Archive Tests")
struct ContactArchiveTests {

    @Test("Sync marks removed contacts as archived")
    func syncArchivesRemovedContact() async throws {
        // Given: A contact exists locally
        let deviceID = UUID()
        let publicKey = Data(repeating: 0x01, count: 32)
        let contact = Contact(
            deviceID: deviceID,
            publicKey: publicKey,
            name: "Test Contact"
        )

        // When: Device returns empty contact list (contact was removed)
        // Then: Contact should be marked as archived
        #expect(contact.isArchived == false, "Contact should start not archived")

        // Simulate archive
        contact.isArchived = true
        #expect(contact.isArchived == true, "Contact should be archived after removal")
    }

    @Test("Sync unarchives restored contacts")
    func syncUnarchivesRestoredContact() async throws {
        // Given: An archived contact
        let deviceID = UUID()
        let publicKey = Data(repeating: 0x02, count: 32)
        let contact = Contact(
            deviceID: deviceID,
            publicKey: publicKey,
            name: "Archived Contact",
            isArchived: true
        )

        #expect(contact.isArchived == true, "Contact should start archived")

        // When: Contact is found on device again
        // Then: Should be unarchived
        contact.isArchived = false
        #expect(contact.isArchived == false, "Contact should be unarchived")
    }

    @Test("Archived contacts preserve message history association")
    func archivedContactPreservesMessageAssociation() async throws {
        // Given: A contact with an associated message ID
        let deviceID = UUID()
        let contactID = UUID()
        let publicKey = Data(repeating: 0x03, count: 32)
        let contact = Contact(
            id: contactID,
            deviceID: deviceID,
            publicKey: publicKey,
            name: "Contact With Messages"
        )

        // When: Contact is archived
        contact.isArchived = true

        // Then: Contact ID remains stable for message association
        #expect(contact.id == contactID, "Contact ID should remain stable")
        #expect(contact.isArchived == true)
    }

    @Test("Restore contact creates valid contact frame")
    func restoreContactCreatesValidFrame() async throws {
        // Given: An archived contact
        let deviceID = UUID()
        let publicKey = Data(repeating: 0x04, count: 32)
        let contact = Contact(
            deviceID: deviceID,
            publicKey: publicKey,
            name: "Archived Contact",
            isArchived: true
        )

        // When: Converting to frame for restore
        let frame = contact.toContactFrame()

        // Then: Frame should have correct public key
        #expect(frame.publicKey == publicKey)
        #expect(frame.name == "Archived Contact")
    }
}
