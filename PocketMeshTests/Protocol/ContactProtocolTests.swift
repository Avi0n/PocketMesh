import XCTest
@testable import PocketMesh
@testable import PocketMeshKit

@MainActor
final class ContactProtocolTests: BaseTestCase {
    func testGetContactsCommand() async throws {
        // Test CMD_GET_CONTACTS (4) multi-frame protocol

        // Should return empty array initially (no contacts on mock)
        let contacts = try await meshProtocol.getContacts(since: nil)
        XCTAssertTrue(contacts.isEmpty, "Expected no contacts on fresh mock")

        // TODO: Configure mock to return test contacts
        // Would require MockBLERadio to support contact list simulation
    }

    func testGetContactsWithTimestamp() async throws {
        // Test incremental sync with timestamp watermark
        let timestamp = Date().addingTimeInterval(-3600) // 1 hour ago

        let contacts = try await meshProtocol.getContacts(since: timestamp)
        XCTAssertTrue(contacts.isEmpty, "Expected no contacts modified in last hour")
    }

    func testAddUpdateContactCommand() async throws {
        // Test CMD_ADD_UPDATE_CONTACT (9) → RESP_CODE_OK (0)

        let contactData = TestDataFactory.contactData(
            publicKey: TestDataFactory.alicePublicKey,
            name: "Alice"
        )

        try await meshProtocol.addOrUpdateContact(contactData)

        // Verify no error thrown - success indicated by not throwing
    }

    func testAddMultipleContacts() async throws {
        // Test adding multiple contacts sequentially
        let contacts = [
            TestDataFactory.contactData(
                publicKey: TestDataFactory.alicePublicKey,
                name: "Alice"
            ),
            TestDataFactory.contactData(
                publicKey: TestDataFactory.bobPublicKey,
                name: "Bob"
            ),
            TestDataFactory.contactData(
                publicKey: TestDataFactory.charliePublicKey,
                name: "Charlie"
            )
        ]

        for contact in contacts {
            try await meshProtocol.addOrUpdateContact(contact)
        }

        // All contacts should be added successfully
    }

    func testRemoveContactCommand() async throws {
        // Test CMD_REMOVE_CONTACT (15) → RESP_CODE_OK (0)

        let publicKey = TestDataFactory.bobPublicKey
        try await meshProtocol.removeContact(publicKey: publicKey)

        // Verify no error thrown
    }

    func testRemoveNonexistentContact() async throws {
        // Test removing contact that doesn't exist
        let randomKey = TestDataFactory.randomPublicKey()

        // Should not error even if contact doesn't exist
        try await meshProtocol.removeContact(publicKey: randomKey)
    }

    // MARK: - Advertisement Commands

    func testSendSelfAdvertisement() async throws {
        // Test CMD_SEND_SELF_ADVERT (7)
        try await meshProtocol.sendSelfAdvertisement(floodMode: false)

        // Should complete without error
    }

    func testSendSelfAdvertisementWithFlood() async throws {
        // Test flood advertisement
        try await meshProtocol.sendSelfAdvertisement(floodMode: true)

        // Should complete without error
    }

    func testSetAdvertisementName() async throws {
        // Test CMD_SET_ADVERT_NAME (8)
        try await meshProtocol.setAdvertisementName("TestDevice")

        // Should complete without error
    }

    func testSetAdvertisementNameWithLongName() async throws {
        // Test with maximum length name (32 characters)
        let longName = String(repeating: "A", count: 32)
        try await meshProtocol.setAdvertisementName(longName)

        // Should complete without error
    }

    func testSetAdvertisementLocation() async throws {
        // Test CMD_SET_ADVERT_LATLON (14)
        try await meshProtocol.setAdvertisementLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 0
        )

        // Should complete without error
    }

    func testSetAdvertisementLocationWithAltitude() async throws {
        // Test with altitude included
        try await meshProtocol.setAdvertisementLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 100
        )

        // Should complete without error
    }

    // MARK: - Contact Data Validation

    func testAddContactWithDifferentTypes() async throws {
        // Test different contact types per specification
        // Note: Spec defines CHAT (1), ROOM (3), REPEATER types

        let chatContact = TestDataFactory.contactData(
            publicKey: TestDataFactory.alicePublicKey,
            name: "Chat Contact",
            type: .chat
        )
        try await meshProtocol.addOrUpdateContact(chatContact)

        let roomContact = TestDataFactory.contactData(
            publicKey: TestDataFactory.bobPublicKey,
            name: "Room Contact",
            type: .room
        )
        try await meshProtocol.addOrUpdateContact(roomContact)

        // Both contact types should be accepted
    }

    func testAddContactWithPath() async throws {
        // Test contact with routing path data
        var contactData = TestDataFactory.contactData(
            publicKey: TestDataFactory.charliePublicKey,
            name: "Remote Contact"
        )

        // Add path data (e.g., 2-hop path through intermediate nodes)
        let pathData = Data([0x01, 0x02]) // Example path
        contactData = ContactData(
            publicKey: contactData.publicKey,
            name: contactData.name,
            type: contactData.type,
            flags: contactData.flags,
            outPathLength: UInt8(pathData.count),
            outPath: pathData,
            lastAdvertisement: contactData.lastAdvertisement,
            latitude: contactData.latitude,
            longitude: contactData.longitude,
            lastModified: contactData.lastModified
        )

        try await meshProtocol.addOrUpdateContact(contactData)

        // Contact with path should be accepted
    }

    // MARK: - Error Handling

    func testAddContactWithInvalidPublicKey() async throws {
        // Test with invalid (too short) public key
        var invalidContact = TestDataFactory.contactData(name: "Invalid")
        // Create contact with wrong key length (should be 32 bytes)
        invalidContact = ContactData(
            publicKey: Data(repeating: 0x01, count: 16), // Wrong length
            name: invalidContact.name,
            type: invalidContact.type,
            flags: invalidContact.flags,
            outPathLength: invalidContact.outPathLength,
            outPath: invalidContact.outPath,
            lastAdvertisement: invalidContact.lastAdvertisement,
            latitude: invalidContact.latitude,
            longitude: invalidContact.longitude,
            lastModified: invalidContact.lastModified
        )

        do {
            try await meshProtocol.addOrUpdateContact(invalidContact)
            XCTFail("Expected error for invalid public key length")
        } catch {
            // Expected - invalid public key should cause error
        }
    }

    func testRemoveContactWithInvalidKey() async throws {
        // Test removing contact with invalid key
        let invalidKey = Data() // Empty key

        do {
            try await meshProtocol.removeContact(publicKey: invalidKey)
            XCTFail("Expected error for invalid public key")
        } catch {
            // Expected - invalid key should cause error
        }
    }
}
