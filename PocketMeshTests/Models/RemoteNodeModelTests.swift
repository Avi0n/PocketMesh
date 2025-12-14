import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Remote Node Model Tests")
struct RemoteNodeModelTests {

    // MARK: - RemoteNodeSession Tests

    @Test("RemoteNodeSession correctly stores role")
    func remoteNodeSessionStoresRole() async throws {
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Create room session
        let roomSession = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: publicKey,
            name: "TestRoom",
            role: .roomServer
        )

        try await dataStore.saveRemoteNodeSessionDTO(roomSession)
        let fetched = try await dataStore.fetchRemoteNodeSession(id: roomSession.id)

        #expect(fetched?.role == .roomServer)
        #expect(fetched?.isRoom == true)
        #expect(fetched?.isRepeater == false)
    }

    @Test("RemoteNodeSession correctly stores repeater role")
    func remoteNodeSessionStoresRepeaterRole() async throws {
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        let repeaterSession = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: publicKey,
            name: "TestRepeater",
            role: .repeater
        )

        try await dataStore.saveRemoteNodeSessionDTO(repeaterSession)
        let fetched = try await dataStore.fetchRemoteNodeSession(id: repeaterSession.id)

        #expect(fetched?.role == .repeater)
        #expect(fetched?.isRoom == false)
        #expect(fetched?.isRepeater == true)
    }

    // MARK: - RemoteNodeSessionDTO Tests

    @Test("RemoteNodeSessionDTO computed properties work")
    func remoteNodeSessionDTOComputedProperties() {
        let publicKey = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF] + Array(repeating: UInt8(0), count: 26))

        let session = RemoteNodeSessionDTO(
            deviceID: UUID(),
            publicKey: publicKey,
            name: "Test",
            role: .roomServer,
            isConnected: true,
            permissionLevel: .readWrite
        )

        // Test public key prefix
        #expect(session.publicKeyPrefix.count == 6)
        #expect(session.publicKeyPrefix == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))

        // Test hex string
        #expect(session.publicKeyHex.hasPrefix("AABBCCDDEEFF"))

        // Test role helpers
        #expect(session.isRoom == true)
        #expect(session.isRepeater == false)

        // Test permission helpers
        #expect(session.canPost == true)  // Room + readWrite
        #expect(session.isAdmin == false)
    }

    @Test("RemoteNodeSessionDTO canPost requires room and readWrite")
    func remoteNodeSessionDTOCanPostRequirements() {
        // Room + guest = can't post
        let guestRoom = RemoteNodeSessionDTO(
            deviceID: UUID(),
            publicKey: Data(repeating: 0, count: 32),
            name: "Test",
            role: .roomServer,
            permissionLevel: .guest
        )
        #expect(guestRoom.canPost == false)

        // Repeater + admin = can't post (not a room)
        let adminRepeater = RemoteNodeSessionDTO(
            deviceID: UUID(),
            publicKey: Data(repeating: 0, count: 32),
            name: "Test",
            role: .repeater,
            permissionLevel: .admin
        )
        #expect(adminRepeater.canPost == false)

        // Room + admin = can post
        let adminRoom = RemoteNodeSessionDTO(
            deviceID: UUID(),
            publicKey: Data(repeating: 0, count: 32),
            name: "Test",
            role: .roomServer,
            permissionLevel: .admin
        )
        #expect(adminRoom.canPost == true)
    }

    // MARK: - RoomMessage Tests

    @Test("RoomMessage.generateDeduplicationKey produces consistent keys")
    func roomMessageGenerateDeduplicationKeyConsistent() {
        let timestamp: UInt32 = 1702500000
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let text = "Hello world"

        let key1 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        let key2 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        #expect(key1 == key2)
    }

    @Test("RoomMessage.generateDeduplicationKey differs for different content")
    func roomMessageGenerateDeduplicationKeyDiffers() {
        let timestamp: UInt32 = 1702500000
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])

        let key1 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: "Hello"
        )

        let key2 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorPrefix,
            text: "World"
        )

        #expect(key1 != key2)
    }

    @Test("RoomMessage.generateDeduplicationKey differs for different timestamps")
    func roomMessageGenerateDeduplicationKeyDiffersByTimestamp() {
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let text = "Same text"

        let key1 = RoomMessage.generateDeduplicationKey(
            timestamp: 1702500000,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        let key2 = RoomMessage.generateDeduplicationKey(
            timestamp: 1702500001,
            authorKeyPrefix: authorPrefix,
            text: text
        )

        #expect(key1 != key2)
    }

    @Test("RoomMessage.generateDeduplicationKey differs for different authors")
    func roomMessageGenerateDeduplicationKeyDiffersByAuthor() {
        let timestamp: UInt32 = 1702500000
        let text = "Same text"

        let key1 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            text: text
        )

        let key2 = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: Data([0x11, 0x22, 0x33, 0x44]),
            text: text
        )

        #expect(key1 != key2)
    }

    @Test("RoomMessage author display name fallback works")
    func roomMessageAuthorDisplayNameFallback() {
        // With author name
        let messageWithName = RoomMessageDTO(
            sessionID: UUID(),
            authorKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            authorName: "Alice",
            text: "Hello",
            timestamp: 1702500000
        )
        #expect(messageWithName.authorDisplayName == "Alice")

        // Without author name (should use hex)
        let messageWithoutName = RoomMessageDTO(
            sessionID: UUID(),
            authorKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            authorName: nil,
            text: "Hello",
            timestamp: 1702500000
        )
        #expect(messageWithoutName.authorDisplayName == "AABBCCDD")
    }

    @Test("RoomMessageDTO date conversion works")
    func roomMessageDTODateConversion() {
        let timestamp: UInt32 = 1702500000
        let message = RoomMessageDTO(
            sessionID: UUID(),
            authorKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            authorName: nil,
            text: "Test",
            timestamp: timestamp
        )

        let expectedDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        #expect(message.date == expectedDate)
    }

    // MARK: - KeychainService Tests

    @Test("KeychainService store/retrieve/delete cycle")
    func keychainServiceStoreRetrieveDeleteCycle() async throws {
        let keychain = MockKeychainService()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let password = "testpassword123"

        // Store
        try await keychain.storePassword(password, forNodeKey: publicKey)

        // Retrieve
        let retrieved = try await keychain.retrievePassword(forNodeKey: publicKey)
        #expect(retrieved == password)

        // Has password
        let hasPassword = await keychain.hasPassword(forNodeKey: publicKey)
        #expect(hasPassword == true)

        // Delete
        try await keychain.deletePassword(forNodeKey: publicKey)

        // Verify deleted
        let afterDelete = try await keychain.retrievePassword(forNodeKey: publicKey)
        #expect(afterDelete == nil)

        let hasPasswordAfterDelete = await keychain.hasPassword(forNodeKey: publicKey)
        #expect(hasPasswordAfterDelete == false)
    }

    @Test("KeychainService handles non-existent keys")
    func keychainServiceHandlesNonExistentKeys() async throws {
        let keychain = MockKeychainService()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        let retrieved = try await keychain.retrievePassword(forNodeKey: publicKey)
        #expect(retrieved == nil)

        let hasPassword = await keychain.hasPassword(forNodeKey: publicKey)
        #expect(hasPassword == false)
    }

    @Test("KeychainService replaces existing password")
    func keychainServiceReplacesExistingPassword() async throws {
        let keychain = MockKeychainService()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Store first password
        try await keychain.storePassword("first", forNodeKey: publicKey)
        var retrieved = try await keychain.retrievePassword(forNodeKey: publicKey)
        #expect(retrieved == "first")

        // Store second password (should replace)
        try await keychain.storePassword("second", forNodeKey: publicKey)
        retrieved = try await keychain.retrievePassword(forNodeKey: publicKey)
        #expect(retrieved == "second")
    }

    @Test("KeychainService delete non-existent key does not throw")
    func keychainServiceDeleteNonExistentKeyNoThrow() async throws {
        let keychain = MockKeychainService()
        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Should not throw
        try await keychain.deletePassword(forNodeKey: publicKey)
    }

    @Test("MockKeychainService getAllStoredKeys returns all keys")
    func mockKeychainServiceGetAllStoredKeys() async throws {
        let keychain = MockKeychainService()

        let key1 = Data(repeating: 0x11, count: 32)
        let key2 = Data(repeating: 0x22, count: 32)
        let key3 = Data(repeating: 0x33, count: 32)

        try await keychain.storePassword("pass1", forNodeKey: key1)
        try await keychain.storePassword("pass2", forNodeKey: key2)
        try await keychain.storePassword("pass3", forNodeKey: key3)

        let allKeys = await keychain.getAllStoredKeys()
        #expect(allKeys.count == 3)
        #expect(allKeys.contains(key1))
        #expect(allKeys.contains(key2))
        #expect(allKeys.contains(key3))
    }

    @Test("MockKeychainService clear removes all passwords")
    func mockKeychainServiceClearRemovesAll() async throws {
        let keychain = MockKeychainService()

        try await keychain.storePassword("pass1", forNodeKey: Data(repeating: 0x11, count: 32))
        try await keychain.storePassword("pass2", forNodeKey: Data(repeating: 0x22, count: 32))

        await keychain.clear()

        let allKeys = await keychain.getAllStoredKeys()
        #expect(allKeys.isEmpty)
    }
}
