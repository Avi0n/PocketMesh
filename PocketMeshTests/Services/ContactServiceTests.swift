import Testing
import Foundation
@testable import PocketMeshKit

@Suite("ContactService Tests")
struct ContactServiceTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createTestContact(name: String = "TestContact", publicKey: Data? = nil) -> ContactFrame {
        ContactFrame(
            publicKey: publicKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: 2,
            outPath: Data([0x01, 0x02]),
            name: name,
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
    }

    private func encodeContactFrame(_ contact: ContactFrame) -> Data {
        var response = Data([ResponseCode.contact.rawValue])
        response.append(contact.publicKey)
        response.append(contact.type.rawValue)
        response.append(contact.flags)
        response.append(UInt8(bitPattern: Int8(contact.outPathLength)))

        var pathData = contact.outPath
        if pathData.count < 64 {
            pathData.append(Data(repeating: 0, count: 64 - pathData.count))
        }
        response.append(pathData.prefix(64))

        var nameData = contact.name.data(using: .utf8) ?? Data()
        if nameData.count < 32 {
            nameData.append(Data(repeating: 0, count: 32 - nameData.count))
        }
        response.append(nameData.prefix(32))

        response.append(contentsOf: withUnsafeBytes(of: contact.lastAdvertTimestamp.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.latitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.longitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.lastModified.littleEndian) { Array($0) })

        return response
    }

    private func createContactsStartResponse(count: UInt32) -> Data {
        var response = Data([ResponseCode.contactsStart.rawValue])
        response.append(contentsOf: withUnsafeBytes(of: count.littleEndian) { Array($0) })
        return response
    }

    private func createEndOfContactsResponse(lastTimestamp: UInt32 = 0) -> Data {
        var response = Data([ResponseCode.endOfContacts.rawValue])
        response.append(contentsOf: withUnsafeBytes(of: lastTimestamp.littleEndian) { Array($0) })
        return response
    }

    private func createErrorResponse(_ error: ProtocolError) -> Data {
        Data([ResponseCode.error.rawValue, error.rawValue])
    }

    // MARK: - Sync Contacts Tests

    @Test("Sync contacts with empty list succeeds")
    func syncContactsEmptyListSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Queue responses: contacts start (0 contacts), end of contacts
        await transport.queueResponses([
            createContactsStartResponse(count: 0),
            createEndOfContactsResponse(lastTimestamp: 1000)
        ])

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.syncContacts(deviceID: deviceID)

        #expect(result.contactsReceived == 0)
        #expect(result.lastSyncTimestamp == 1000)
        #expect(result.isIncremental == false)
    }

    @Test("Sync contacts with multiple contacts succeeds")
    func syncContactsMultipleContactsSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let contact1 = createTestContact(name: "Alice")
        let contact2 = createTestContact(name: "Bob")

        // Queue responses
        await transport.queueResponses([
            createContactsStartResponse(count: 2),
            encodeContactFrame(contact1),
            encodeContactFrame(contact2),
            createEndOfContactsResponse(lastTimestamp: 2000)
        ])

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let progressUpdates = MutableBox<[(Int, Int)]>([])
        await service.setSyncProgressHandler { current, total in
            progressUpdates.value.append((current, total))
        }

        let result = try await service.syncContacts(deviceID: deviceID)

        #expect(result.contactsReceived == 2)
        #expect(result.lastSyncTimestamp == 2000)

        // Verify contacts were saved
        let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        #expect(contacts.count == 2)

        // Verify progress was reported
        #expect(progressUpdates.value.count >= 2)
    }

    @Test("Incremental sync uses since parameter")
    func incrementalSyncUsesSinceParameter() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponses([
            createContactsStartResponse(count: 0),
            createEndOfContactsResponse(lastTimestamp: 3000)
        ])

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.syncContacts(deviceID: deviceID, since: 1500)

        #expect(result.isIncremental == true)

        // Verify the command included the since timestamp
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData[0].count == 5)  // command + 4 bytes timestamp
    }

    @Test("Sync contacts fails when not connected")
    func syncContactsFailsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ContactServiceError.self) {
            try await service.syncContacts(deviceID: deviceID)
        }
    }

    @Test("Sync contacts handles contact update handler")
    func syncContactsHandlesContactUpdateHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let contact = createTestContact(name: "TestUser")

        await transport.queueResponses([
            createContactsStartResponse(count: 1),
            encodeContactFrame(contact),
            createEndOfContactsResponse()
        ])

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let receivedContacts = MutableBox<[ContactDTO]>([])
        await service.setContactUpdateHandler { contacts in
            receivedContacts.value = contacts
        }

        _ = try await service.syncContacts(deviceID: deviceID)

        #expect(receivedContacts.value.count == 1)
        #expect(receivedContacts.value.first?.name == "TestUser")
    }

    // MARK: - Get Contact Tests

    @Test("Get contact by public key succeeds")
    func getContactByPublicKeySucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let contact = createTestContact(name: "FoundContact")
        await transport.queueResponse(encodeContactFrame(contact))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.getContact(deviceID: deviceID, publicKey: contact.publicKey)

        #expect(result != nil)
        #expect(result?.name == "FoundContact")

        // Verify command was sent correctly
        let sentData = await transport.getSentData()
        #expect(sentData[0][0] == CommandCode.getContactByKey.rawValue)
    }

    @Test("Get contact returns nil when not found")
    func getContactReturnsNilWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponse(createErrorResponse(.notFound))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.getContact(deviceID: deviceID, publicKey: Data(repeating: 0xAB, count: 32))

        #expect(result == nil)
    }

    // MARK: - Add/Update Contact Tests

    @Test("Add contact succeeds")
    func addContactSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let contact = createTestContact(name: "NewContact")

        try await service.addOrUpdateContact(deviceID: deviceID, contact: contact)

        // Verify contact was saved locally
        let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        #expect(contacts.count == 1)
        #expect(contacts.first?.name == "NewContact")

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData[0][0] == CommandCode.addUpdateContact.rawValue)
    }

    @Test("Add contact fails when table full")
    func addContactFailsWhenTableFull() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponse(createErrorResponse(.tableFull))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let contact = createTestContact()

        await #expect(throws: ContactServiceError.self) {
            try await service.addOrUpdateContact(deviceID: deviceID, contact: contact)
        }
    }

    @Test("Update existing contact succeeds")
    func updateExistingContactSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // First add a contact
        let originalContact = createTestContact(name: "Original", publicKey: publicKey)
        _ = try await dataStore.saveContact(deviceID: deviceID, from: originalContact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        // Update the contact
        let updatedContact = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: 0,
            outPathLength: 3,
            outPath: Data([0x01, 0x02, 0x03]),
            name: "Updated",
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 40.0,
            longitude: -74.0,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )

        try await service.addOrUpdateContact(deviceID: deviceID, contact: updatedContact)

        // Verify contact was updated
        let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        #expect(contacts.count == 1)
        #expect(contacts.first?.name == "Updated")
    }

    // MARK: - Remove Contact Tests

    @Test("Remove contact succeeds")
    func removeContactSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let contact = createTestContact(name: "ToBeRemoved")
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        try await service.removeContact(deviceID: deviceID, publicKey: contact.publicKey)

        // Verify contact was removed locally
        let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        #expect(contacts.isEmpty)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData[0][0] == CommandCode.removeContact.rawValue)
    }

    @Test("Remove contact fails when not found")
    func removeContactFailsWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponse(createErrorResponse(.notFound))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ContactServiceError.self) {
            try await service.removeContact(deviceID: deviceID, publicKey: Data(repeating: 0xAB, count: 32))
        }
    }

    // MARK: - Reset Path Tests

    @Test("Reset path succeeds")
    func resetPathSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let contact = createTestContact(name: "PathReset")
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        try await service.resetPath(deviceID: deviceID, publicKey: contact.publicKey)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData[0][0] == CommandCode.resetPath.rawValue)

        // Verify contact path was updated to flood
        let updatedContact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: contact.publicKey)
        #expect(updatedContact?.outPathLength == -1)
    }

    @Test("Reset path fails when contact not found")
    func resetPathFailsWhenContactNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        await transport.queueResponse(createErrorResponse(.notFound))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ContactServiceError.self) {
            try await service.resetPath(deviceID: deviceID, publicKey: Data(repeating: 0xAB, count: 32))
        }
    }

    // MARK: - Share Contact Tests

    @Test("Share contact succeeds")
    func shareContactSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        try await service.shareContact(publicKey: publicKey)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData[0][0] == CommandCode.shareContact.rawValue)
    }

    @Test("Share contact fails when not found")
    func shareContactFailsWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createErrorResponse(.notFound))

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ContactServiceError.self) {
            try await service.shareContact(publicKey: Data(repeating: 0xAB, count: 32))
        }
    }

    // MARK: - Local Database Operations Tests

    @Test("Get contacts from local database")
    func getContactsFromLocalDatabase() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Add contacts directly to database
        let contact1 = createTestContact(name: "LocalAlice")
        let contact2 = createTestContact(name: "LocalBob")
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact1)
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact2)

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let contacts = try await service.getContacts(deviceID: deviceID)

        #expect(contacts.count == 2)
    }

    @Test("Get conversations from local database")
    func getConversationsFromLocalDatabase() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Add contacts - one with messages, one without
        let contact1 = createTestContact(name: "WithMessages")
        let contact2 = createTestContact(name: "WithoutMessages")
        let id1 = try await dataStore.saveContact(deviceID: deviceID, from: contact1)
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact2)

        // Update contact1 to have a lastMessageDate
        try await dataStore.updateContactLastMessage(contactID: id1, date: Date())

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        let conversations = try await service.getConversations(deviceID: deviceID)

        #expect(conversations.count == 1)
        #expect(conversations.first?.name == "WithMessages")
    }

    @Test("Update contact preferences")
    func updateContactPreferences() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let contact = createTestContact(name: "Preferences")
        let contactID = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        try await service.updateContactPreferences(
            contactID: contactID,
            nickname: "NickName",
            isBlocked: true,
            isFavorite: true
        )

        let updated = try await service.getContactByID(contactID)

        #expect(updated?.nickname == "NickName")
        #expect(updated?.isBlocked == true)
        #expect(updated?.isFavorite == true)
    }

    @Test("Update contact preferences fails when not found")
    func updateContactPreferencesFailsWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let service = ContactService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ContactServiceError.self) {
            try await service.updateContactPreferences(
                contactID: UUID(),
                nickname: "Test"
            )
        }
    }
}
