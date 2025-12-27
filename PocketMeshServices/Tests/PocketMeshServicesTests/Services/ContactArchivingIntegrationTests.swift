import Testing
import Foundation
@testable import PocketMeshServices
@testable import MeshCore

@Suite("Contact Archiving Integration Tests")
struct ContactArchivingIntegrationTests {

    /// Test device ID (same as MockDataProvider.simulatorDeviceID)
    private let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - Helper Methods

    private func makeContact(name: String, seed: UInt8, isArchived: Bool = false) -> ContactDTO {
        let publicKey = Data((0..<32).map { UInt8($0) &+ seed })
        return ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: publicKey,
            name: name,
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 1,
            outPath: Data([seed]),
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 0,
            longitude: 0,
            lastModified: UInt32(Date().timeIntervalSince1970),
            nickname: nil,
            isBlocked: false,
            isFavorite: false,
            isDiscovered: false,
            isArchived: isArchived,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }

    private func makeMeshContact(from dto: ContactDTO) -> MeshContact {
        MeshContact(
            id: dto.publicKey.hexString(),
            publicKey: dto.publicKey,
            type: dto.typeRawValue,
            flags: dto.flags,
            outPathLength: dto.outPathLength,
            outPath: dto.outPath,
            advertisedName: dto.name,
            lastAdvertisement: Date(timeIntervalSince1970: TimeInterval(dto.lastAdvertTimestamp)),
            latitude: dto.latitude,
            longitude: dto.longitude,
            lastModified: Date(timeIntervalSince1970: TimeInterval(dto.lastModified))
        )
    }

    // MARK: - Tests

    @Test("Sync archives contacts removed from device")
    func syncArchivesRemovedContacts() async throws {
        // Given: 3 contacts in local store
        let mockSession = MockMeshCoreSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: mockSession, dataStore: store)

        let alice = makeContact(name: "Alice", seed: 1)
        let bob = makeContact(name: "Bob", seed: 2)
        let charlie = makeContact(name: "Charlie", seed: 3)

        try await store.saveContact(alice)
        try await store.saveContact(bob)
        try await store.saveContact(charlie)

        // When: Device only returns Bob and Charlie (Alice removed)
        await mockSession.setStubbedContacts([makeMeshContact(from: bob), makeMeshContact(from: charlie)])
        _ = try await service.syncContacts(deviceID: deviceID)

        // Then: Alice should be archived
        let fetchedAlice = try await store.fetchContact(id: alice.id)
        #expect(fetchedAlice?.isArchived == true, "Alice should be archived")

        let fetchedBob = try await store.fetchContact(id: bob.id)
        #expect(fetchedBob?.isArchived == false, "Bob should not be archived")
    }

    @Test("Sync unarchives restored contacts")
    func syncUnarchivesRestoredContacts() async throws {
        // Given: An archived contact
        let mockSession = MockMeshCoreSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: mockSession, dataStore: store)

        let alice = makeContact(name: "Alice", seed: 1, isArchived: true)
        try await store.saveContact(alice)

        // When: Device returns Alice (she's back)
        await mockSession.setStubbedContacts([makeMeshContact(from: alice)])
        _ = try await service.syncContacts(deviceID: deviceID)

        // Then: Alice should be unarchived
        let fetchedAlice = try await store.fetchContact(id: alice.id)
        #expect(fetchedAlice?.isArchived == false, "Alice should be unarchived")
    }

    // MARK: - SimulatorMeshSession Tests (Xcode only)

    #if targetEnvironment(simulator)
    @Test("SimulatorMeshSession removes oldest contact when at capacity")
    func simulatorSessionRemovesOldestAtCapacity() async throws {
        // Given: A SimulatorMeshSession at capacity
        let session = SimulatorMeshSession()
        await session.setMaxContacts(3)

        let alice = makeContact(name: "Alice", seed: 1)
        let bob = makeContact(name: "Bob", seed: 2)
        let charlie = makeContact(name: "Charlie", seed: 3)

        try await session.addContact(makeMeshContact(from: alice))
        try await session.addContact(makeMeshContact(from: bob))
        try await session.addContact(makeMeshContact(from: charlie))

        // When: Adding a fourth contact
        let dave = makeContact(name: "Dave", seed: 4)
        try await session.addContact(makeMeshContact(from: dave))

        // Then: Alice (oldest) should be removed, others remain
        let contacts = await session.currentContacts()
        #expect(contacts.count == 3, "Should have 3 contacts")
        let publicKeys = contacts.map { $0.publicKey }
        #expect(!publicKeys.contains(alice.publicKey), "Alice should be removed")
        #expect(publicKeys.contains(bob.publicKey), "Bob should remain")
        #expect(publicKeys.contains(charlie.publicKey), "Charlie should remain")
        #expect(publicKeys.contains(dave.publicKey), "Dave should be added")
    }

    @Test("Full archiving flow with SimulatorMeshSession")
    func fullArchivingFlowWithSimulator() async throws {
        // Given: ContactService with SimulatorMeshSession at capacity
        let session = SimulatorMeshSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: session, dataStore: store)

        await session.setMaxContacts(2)

        // Add 2 contacts to both session and store
        let alice = makeContact(name: "Alice", seed: 1)
        let bob = makeContact(name: "Bob", seed: 2)

        try await session.addContact(makeMeshContact(from: alice))
        try await session.addContact(makeMeshContact(from: bob))
        try await store.saveContact(alice)
        try await store.saveContact(bob)

        // When: Adding a third contact pushes Alice out
        let charlie = makeContact(name: "Charlie", seed: 3)
        try await session.addContact(makeMeshContact(from: charlie))
        try await store.saveContact(charlie)

        // Sync detects Alice is missing
        _ = try await service.syncContacts(deviceID: deviceID)

        // Then: Alice should be archived
        let fetchedAlice = try await store.fetchContact(id: alice.id)
        #expect(fetchedAlice?.isArchived == true, "Alice should be archived after being pushed out")

        // Bob and Charlie should not be archived
        let fetchedBob = try await store.fetchContact(id: bob.id)
        let fetchedCharlie = try await store.fetchContact(id: charlie.id)
        #expect(fetchedBob?.isArchived == false, "Bob should not be archived")
        #expect(fetchedCharlie?.isArchived == false, "Charlie should not be archived")
    }

    @Test("Restore archived contact adds it back to device")
    func restoreArchivedContactWithSimulator() async throws {
        // Given: An archived contact that was pushed out
        let session = SimulatorMeshSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: session, dataStore: store)

        await session.setMaxContacts(2)

        let alice = makeContact(name: "Alice", seed: 1, isArchived: true)
        let bob = makeContact(name: "Bob", seed: 2)
        let charlie = makeContact(name: "Charlie", seed: 3)

        // Only Bob and Charlie are on device, Alice is archived locally
        try await session.addContact(makeMeshContact(from: bob))
        try await session.addContact(makeMeshContact(from: charlie))
        try await store.saveContact(alice)
        try await store.saveContact(bob)
        try await store.saveContact(charlie)

        // When: Restoring Alice
        try await service.restoreContact(contactID: alice.id)

        // Then: Alice should be on device (and Bob pushed out due to capacity)
        let contacts = await session.currentContacts()
        let publicKeys = contacts.map { $0.publicKey }
        #expect(publicKeys.contains(alice.publicKey), "Alice should be on device after restore")

        // And: Alice should be unarchived locally
        let fetchedAlice = try await store.fetchContact(id: alice.id)
        #expect(fetchedAlice?.isArchived == false, "Alice should be unarchived")
    }
    #endif

    @Test("Discovered contacts are not archived when missing from device")
    func discoveredContactsNotArchived() async throws {
        // Given: A discovered contact (from NEW_ADVERT, not yet confirmed on device)
        let mockSession = MockMeshCoreSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: mockSession, dataStore: store)

        let discovered = ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data((0..<32).map { UInt8($0) }),
            name: "Discovered",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: -1,
            outPath: Data(),
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 0,
            longitude: 0,
            lastModified: UInt32(Date().timeIntervalSince1970),
            nickname: nil,
            isBlocked: false,
            isFavorite: false,
            isDiscovered: true,
            isArchived: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        try await store.saveContact(discovered)

        // When: Device returns no contacts
        await mockSession.setStubbedContacts([])
        _ = try await service.syncContacts(deviceID: deviceID)

        // Then: Discovered contact should NOT be archived (it was never on device)
        let fetched = try await store.fetchContact(id: discovered.id)
        #expect(fetched?.isArchived == false, "Discovered contacts should not be archived")
    }

    @Test("Restore contact sends to device and marks unarchived")
    func restoreContactSendsToDevice() async throws {
        // Given: An archived contact
        let mockSession = MockMeshCoreSession()
        let store = MockPersistenceStore()
        let service = ContactService(session: mockSession, dataStore: store)

        let archived = makeContact(name: "Archived", seed: 42, isArchived: true)
        try await store.saveContact(archived)

        // When: Restore is called
        try await service.restoreContact(contactID: archived.id)

        // Then: Contact should be sent to device
        let addInvocations = await mockSession.addContactInvocations
        #expect(addInvocations.count == 1, "Should have called addContact once")
        #expect(addInvocations.first?.contact.publicKey == archived.publicKey, "Should send correct contact")

        // And: Contact should be marked unarchived locally
        let fetched = try await store.fetchContact(id: archived.id)
        #expect(fetched?.isArchived == false, "Contact should be unarchived after restore")
    }
}
