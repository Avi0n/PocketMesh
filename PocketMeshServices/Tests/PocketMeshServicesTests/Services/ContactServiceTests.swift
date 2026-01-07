import Testing
import Foundation
@testable import PocketMeshServices
@testable import MeshCore

@Suite("ContactService Tests")
struct ContactServiceTests {

    // MARK: - Test Constants

    // Sync result test values
    private let testContactsReceived = 5
    private let testSyncTimestamp: UInt32 = 1234567890
    private let maxContactsReceived = Int.max
    private let maxSyncTimestamp = UInt32.max

    // Contact test values
    private let testPublicKey = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                                       0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                                       0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
                                       0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
    private let testTimestamp: UInt32 = 1700000000
    private let testModifiedTimestamp: UInt32 = 1700000100
    private let testFlags: UInt8 = 0x01
    private let invalidContactType: UInt8 = 0xFF
    private let testOutPath = Data([0xAA, 0xBB, 0xCC, 0xDD])
    private let floodRoutingPath = Data(repeating: 0xFF, count: 3)

    // MARK: - ContactSyncResult Tests

    @Test("ContactSyncResult initializes correctly")
    func contactSyncResultInitializes() {
        let result = ContactSyncResult(
            contactsReceived: testContactsReceived,
            lastSyncTimestamp: testSyncTimestamp,
            isIncremental: true
        )
        #expect(result.contactsReceived == testContactsReceived)
        #expect(result.lastSyncTimestamp == testSyncTimestamp)
        #expect(result.isIncremental == true)
    }

    @Test("ContactSyncResult handles zero contacts")
    func contactSyncResultHandlesZero() {
        let result = ContactSyncResult(
            contactsReceived: 0,
            lastSyncTimestamp: 0,
            isIncremental: false
        )
        #expect(result.contactsReceived == 0)
        #expect(result.lastSyncTimestamp == 0)
        #expect(result.isIncremental == false)
    }

    @Test("ContactSyncResult handles maximum values")
    func contactSyncResultHandlesMaxValues() {
        let result = ContactSyncResult(
            contactsReceived: maxContactsReceived,
            lastSyncTimestamp: maxSyncTimestamp,
            isIncremental: true
        )
        #expect(result.contactsReceived == maxContactsReceived)
        #expect(result.lastSyncTimestamp == maxSyncTimestamp)
        #expect(result.isIncremental == true)
    }

    // MARK: - ContactServiceError Tests

    @Test("ContactServiceError cases are distinct")
    func contactServiceErrorCasesDistinct() {
        // Verify basic error cases
        let basicErrors: [ContactServiceError] = [
            .notConnected,
            .sendFailed,
            .invalidResponse,
            .syncInterrupted,
            .contactNotFound,
            .contactTableFull
        ]

        // Verify all basic cases are distinct (no duplicates)
        let errorDescriptions = basicErrors.map { String(describing: $0) }
        let uniqueDescriptions = Set(errorDescriptions)
        #expect(errorDescriptions.count == uniqueDescriptions.count)
    }

    @Test("ContactServiceError sessionError carries MeshCoreError")
    func contactServiceErrorSessionError() {
        let meshError = MeshCoreError.notConnected
        let error = ContactServiceError.sessionError(meshError)

        // Verify the associated value is accessible
        if case .sessionError(let innerError) = error {
            // Just verify we can access the inner error
            if case .notConnected = innerError {
                // Success
            } else {
                Issue.record("Expected .notConnected case")
            }
        } else {
            Issue.record("Expected sessionError case")
        }
    }

    // MARK: - MeshContact.toContactFrame() Tests

    @Test("MeshContact converts to ContactFrame correctly")
    func meshContactToContactFrame() {
        // Create a test MeshContact with all fields populated
        let publicKey = testPublicKey
        let outPath = testOutPath
        let advertisedName = "TestNode"
        let lastAdvertDate = Date(timeIntervalSince1970: TimeInterval(testTimestamp))
        let lastModifiedDate = Date(timeIntervalSince1970: TimeInterval(testModifiedTimestamp))
        let latitude = 37.7749
        let longitude = -122.4194

        let meshContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.chat.rawValue,
            flags: testFlags,
            outPathLength: 2,
            outPath: outPath,
            advertisedName: advertisedName,
            lastAdvertisement: lastAdvertDate,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModifiedDate
        )

        // Convert to ContactFrame
        let contactFrame = meshContact.toContactFrame()

        // Verify all fields are correctly mapped
        #expect(contactFrame.publicKey == publicKey)
        #expect(contactFrame.type == .chat)
        #expect(contactFrame.flags == testFlags)
        #expect(contactFrame.outPathLength == 2)
        #expect(contactFrame.outPath == outPath)
        #expect(contactFrame.name == advertisedName)
        #expect(contactFrame.lastAdvertTimestamp == UInt32(lastAdvertDate.timeIntervalSince1970))
        #expect(contactFrame.latitude == latitude)
        #expect(contactFrame.longitude == longitude)
        #expect(contactFrame.lastModified == UInt32(lastModifiedDate.timeIntervalSince1970))
    }

    @Test("MeshContact handles all ContactType conversions")
    func meshContactContactTypeConversions() {
        let publicKey = Data(repeating: 0x00, count: ProtocolLimits.publicKeySize)

        // Test chat type
        let chatContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Chat",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        #expect(chatContact.toContactFrame().type == .chat)

        // Test repeater type
        let repeaterContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Repeater",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        #expect(repeaterContact.toContactFrame().type == .repeater)

        // Test room type
        let roomContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.room.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Room",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        #expect(roomContact.toContactFrame().type == .room)
    }

    @Test("MeshContact handles invalid ContactType gracefully")
    func meshContactInvalidContactType() {
        let publicKey = Data(repeating: 0x00, count: ProtocolLimits.publicKeySize)

        // Create MeshContact with invalid type
        let invalidContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: invalidContactType,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Invalid",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )

        // Should default to .chat per ContactService implementation
        #expect(invalidContact.toContactFrame().type == .chat)
    }

    @Test("MeshContact handles flood routing path")
    func meshContactFloodRouting() {
        let publicKey = Data(repeating: 0x00, count: ProtocolLimits.publicKeySize)

        let floodContact = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: -1,  // Flood routing
            outPath: Data(),
            advertisedName: "Flood",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )

        let frame = floodContact.toContactFrame()
        #expect(frame.outPathLength == -1)
        #expect(frame.outPath.isEmpty)
    }

    // MARK: - ContactFrame.toMeshContact() Tests

    @Test("ContactFrame converts to MeshContact correctly")
    func contactFrameToMeshContact() {
        // Create a test ContactFrame with all fields populated
        let publicKey = testPublicKey
        let outPath = testOutPath
        let name = "TestNode"
        let lastAdvertTimestamp = testTimestamp
        let lastModified = testModifiedTimestamp
        let latitude = 37.7749
        let longitude = -122.4194

        let contactFrame = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: testFlags,
            outPathLength: 2,
            outPath: outPath,
            name: name,
            lastAdvertTimestamp: lastAdvertTimestamp,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified
        )

        // Convert to MeshContact
        let meshContact = contactFrame.toMeshContact()

        // Verify all fields are correctly mapped
        #expect(meshContact.id == publicKey.hexString())
        #expect(meshContact.publicKey == publicKey)
        #expect(meshContact.type == ContactType.chat.rawValue)
        #expect(meshContact.flags == testFlags)
        #expect(meshContact.outPathLength == 2)
        #expect(meshContact.outPath == outPath)
        #expect(meshContact.advertisedName == name)
        #expect(meshContact.lastAdvertisement == Date(timeIntervalSince1970: TimeInterval(lastAdvertTimestamp)))
        #expect(meshContact.latitude == latitude)
        #expect(meshContact.longitude == longitude)
        #expect(meshContact.lastModified == Date(timeIntervalSince1970: TimeInterval(lastModified)))
    }

    @Test("ContactFrame ID generation from public key")
    func contactFrameIDGeneration() {
        let publicKey = Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x90,
                              0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
                              0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00,
                              0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        let contactFrame = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "Test",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )

        let meshContact = contactFrame.toMeshContact()

        // ID should be hex string of public key (uppercase)
        let expectedID = publicKey.hexString()
        #expect(meshContact.id == expectedID)
    }

    @Test("ContactFrame handles all ContactType conversions")
    func contactFrameContactTypeConversions() {
        let publicKey = Data(repeating: 0x00, count: ProtocolLimits.publicKeySize)

        // Test chat type
        let chatFrame = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "Chat",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        #expect(chatFrame.toMeshContact().type == ContactType.chat.rawValue)

        // Test repeater type
        let repeaterFrame = ContactFrame(
            publicKey: publicKey,
            type: .repeater,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "Repeater",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        #expect(repeaterFrame.toMeshContact().type == ContactType.repeater.rawValue)

        // Test room type
        let roomFrame = ContactFrame(
            publicKey: publicKey,
            type: .room,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "Room",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        #expect(roomFrame.toMeshContact().type == ContactType.room.rawValue)
    }

    // MARK: - Round-Trip Conversion Tests

    @Test("Round-trip conversion MeshContact -> ContactFrame -> MeshContact")
    func roundTripMeshContactConversion() {
        let publicKey = testPublicKey

        let original = MeshContact(
            id: publicKey.hexString(),
            publicKey: publicKey,
            type: ContactType.repeater.rawValue,
            flags: 0x05,
            outPathLength: 3,
            outPath: Data([0xAA, 0xBB, 0xCC]),
            advertisedName: "OriginalNode",
            lastAdvertisement: Date(timeIntervalSince1970: TimeInterval(testTimestamp)),
            latitude: 40.7128,
            longitude: -74.0060,
            lastModified: Date(timeIntervalSince1970: 1700000200)
        )

        // Convert to ContactFrame and back
        let frame = original.toContactFrame()
        let roundTripped = frame.toMeshContact()

        // Verify all fields survived the round trip
        #expect(roundTripped.id == original.id)
        #expect(roundTripped.publicKey == original.publicKey)
        #expect(roundTripped.type == original.type)
        #expect(roundTripped.flags == original.flags)
        #expect(roundTripped.outPathLength == original.outPathLength)
        #expect(roundTripped.outPath == original.outPath)
        #expect(roundTripped.advertisedName == original.advertisedName)
        #expect(roundTripped.lastAdvertisement == original.lastAdvertisement)
        #expect(roundTripped.latitude == original.latitude)
        #expect(roundTripped.longitude == original.longitude)
        #expect(roundTripped.lastModified == original.lastModified)
    }

    @Test("Round-trip conversion ContactFrame -> MeshContact -> ContactFrame")
    func roundTripContactFrameConversion() {
        let publicKey = testPublicKey

        let original = ContactFrame(
            publicKey: publicKey,
            type: .room,
            flags: 0x03,
            outPathLength: 1,
            outPath: Data([0xFF]),
            name: "OriginalRoom",
            lastAdvertTimestamp: testTimestamp,
            latitude: 51.5074,
            longitude: -0.1278,
            lastModified: 1700000300
        )

        // Convert to MeshContact and back
        let meshContact = original.toMeshContact()
        let roundTripped = meshContact.toContactFrame()

        // Verify all fields survived the round trip
        #expect(roundTripped == original)
    }

    // MARK: - Cleanup Handler Tests

    /// Actor to track cleanup handler invocations in a thread-safe manner
    private actor CleanupTracker {
        var invocations: [(contactID: UUID, reason: ContactCleanupReason)] = []

        func record(contactID: UUID, reason: ContactCleanupReason) {
            invocations.append((contactID: contactID, reason: reason))
        }
    }

    @Test("removeContact deletes messages and triggers cleanup")
    func removeContactDeletesMessagesAndTriggersCleanup() async throws {
        let mockSession = MockMeshCoreSession()
        let mockStore = MockPersistenceStore()

        let deviceID = UUID()
        let contactID = UUID()

        // Set up contact in the mock store
        let contact = ContactDTO(
            id: contactID,
            deviceID: deviceID,
            publicKey: testPublicKey,
            name: "TestContact",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isFavorite: false,
            isDiscovered: false,
            lastMessageDate: nil,
            unreadCount: 3
        )
        try await mockStore.saveContact(contact)

        // Track cleanup handler invocations
        let tracker = CleanupTracker()

        let service = ContactService(session: mockSession, dataStore: mockStore)
        await service.setCleanupHandler { contactID, reason in
            await tracker.record(contactID: contactID, reason: reason)
        }

        // Remove the contact
        try await service.removeContact(deviceID: deviceID, publicKey: testPublicKey)

        // Verify messages were deleted
        let deletedForContacts = await mockStore.deletedMessagesForContactIDs
        #expect(deletedForContacts == [contactID])

        // Verify cleanup handler was called with reason=.deleted
        let invocations = await tracker.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0].contactID == contactID)
        #expect(invocations[0].reason == .deleted)
    }

    @Test("updateContactPreferences clears unread when blocking")
    func updateContactPreferencesClearsUnreadWhenBlocking() async throws {
        let mockSession = MockMeshCoreSession()
        let mockStore = MockPersistenceStore()

        let deviceID = UUID()
        let contactID = UUID()

        // Set up contact with unread count
        let contact = ContactDTO(
            id: contactID,
            deviceID: deviceID,
            publicKey: testPublicKey,
            name: "TestContact",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isFavorite: false,
            isDiscovered: false,
            lastMessageDate: nil,
            unreadCount: 5
        )
        try await mockStore.saveContact(contact)

        // Track cleanup handler invocations
        let tracker = CleanupTracker()

        let service = ContactService(session: mockSession, dataStore: mockStore)
        await service.setCleanupHandler { contactID, reason in
            await tracker.record(contactID: contactID, reason: reason)
        }

        // Block the contact
        try await service.updateContactPreferences(contactID: contactID, isBlocked: true)

        // Verify unread count was cleared
        let updatedContact = await mockStore.contacts[contactID]
        #expect(updatedContact?.unreadCount == 0)
        #expect(updatedContact?.isBlocked == true)

        // Verify cleanup handler was called with reason=.blocked
        let invocations = await tracker.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0].contactID == contactID)
        #expect(invocations[0].reason == .blocked)
    }

    @Test("updateContactPreferences does not trigger cleanup when not blocking")
    func updateContactPreferencesNoCleanupWhenNotBlocking() async throws {
        let mockSession = MockMeshCoreSession()
        let mockStore = MockPersistenceStore()

        let deviceID = UUID()
        let contactID = UUID()

        // Set up contact
        let contact = ContactDTO(
            id: contactID,
            deviceID: deviceID,
            publicKey: testPublicKey,
            name: "TestContact",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isFavorite: false,
            isDiscovered: false,
            lastMessageDate: nil,
            unreadCount: 5
        )
        try await mockStore.saveContact(contact)

        // Track cleanup handler invocations
        let tracker = CleanupTracker()

        let service = ContactService(session: mockSession, dataStore: mockStore)
        await service.setCleanupHandler { contactID, reason in
            await tracker.record(contactID: contactID, reason: reason)
        }

        // Update nickname (not blocking)
        try await service.updateContactPreferences(contactID: contactID, nickname: "NewNickname")

        // Verify unread count was preserved
        let updatedContact = await mockStore.contacts[contactID]
        #expect(updatedContact?.unreadCount == 5)
        #expect(updatedContact?.nickname == "NewNickname")

        // Verify cleanup handler was NOT called
        let invocations = await tracker.invocations
        #expect(invocations.isEmpty)
    }

    @Test("updateContactPreferences preserves fields when blocking")
    func updateContactPreferencesPreservesFieldsWhenBlocking() async throws {
        let mockSession = MockMeshCoreSession()
        let mockStore = MockPersistenceStore()

        let deviceID = UUID()
        let contactID = UUID()

        // Set up contact with special fields
        let contact = ContactDTO(
            id: contactID,
            deviceID: deviceID,
            publicKey: testPublicKey,
            name: "TestContact",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: "MyNickname",
            isBlocked: false,
            isFavorite: true,
            isDiscovered: true,
            lastMessageDate: Date(),
            unreadCount: 5,
            ocvPreset: "medium",
            customOCVArrayString: "custom"
        )
        try await mockStore.saveContact(contact)

        let service = ContactService(session: mockSession, dataStore: mockStore)

        // Block the contact
        try await service.updateContactPreferences(contactID: contactID, isBlocked: true)

        // Verify all fields are preserved except unreadCount
        let updatedContact = await mockStore.contacts[contactID]
        #expect(updatedContact?.nickname == "MyNickname")
        #expect(updatedContact?.isFavorite == true)
        #expect(updatedContact?.isDiscovered == true)
        #expect(updatedContact?.ocvPreset == "medium")
        #expect(updatedContact?.customOCVArrayString == "custom")
        #expect(updatedContact?.unreadCount == 0)
        #expect(updatedContact?.isBlocked == true)
    }

    @Test("unblocking contact does not trigger cleanup")
    func unblockingContactDoesNotTriggerCleanup() async throws {
        let mockSession = MockMeshCoreSession()
        let mockStore = MockPersistenceStore()

        let deviceID = UUID()
        let contactID = UUID()

        // Set up contact that is already blocked
        let contact = ContactDTO(
            id: contactID,
            deviceID: deviceID,
            publicKey: testPublicKey,
            name: "TestContact",
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: true,
            isFavorite: false,
            isDiscovered: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        try await mockStore.saveContact(contact)

        // Track cleanup handler invocations
        let tracker = CleanupTracker()

        let service = ContactService(session: mockSession, dataStore: mockStore)
        await service.setCleanupHandler { contactID, reason in
            await tracker.record(contactID: contactID, reason: reason)
        }

        // Unblock the contact
        try await service.updateContactPreferences(contactID: contactID, isBlocked: false)

        // Verify contact was unblocked
        let updatedContact = await mockStore.contacts[contactID]
        #expect(updatedContact?.isBlocked == false)

        // Verify cleanup handler was NOT called
        let invocations = await tracker.invocations
        #expect(invocations.isEmpty)
    }

}
