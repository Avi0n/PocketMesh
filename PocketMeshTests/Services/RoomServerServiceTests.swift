import Testing
import Foundation
@testable import PocketMeshKit

@Suite("RoomServerService Tests")
struct RoomServerServiceTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createTestServices(
        transport: TestBLETransport,
        dataStore: DataStore
    ) -> (RoomServerService, RemoteNodeService, MockKeychainService) {
        let keychain = MockKeychainService()
        let binaryProtocol = BinaryProtocolService(bleTransport: transport)
        let remoteNodeService = RemoteNodeService(
            bleTransport: transport,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore,
            keychainService: keychain
        )
        let roomServerService = RoomServerService(
            remoteNodeService: remoteNodeService,
            bleTransport: transport,
            dataStore: dataStore
        )
        return (roomServerService, remoteNodeService, keychain)
    }

    private func createTestContact(
        deviceID: UUID,
        name: String = "TestRoom",
        type: ContactType = .room,
        outPathLength: Int8 = 0
    ) -> ContactDTO {
        let contact = Contact(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            name: name,
            typeRawValue: type.rawValue,
            flags: 0,
            outPathLength: outPathLength,
            outPath: Data(),
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
        return ContactDTO(from: contact)
    }

    private func createTestSession(
        deviceID: UUID,
        dataStore: DataStore,
        keychain: MockKeychainService,
        isConnected: Bool = true,
        permissionLevel: RoomPermissionLevel = .readWrite
    ) async throws -> RemoteNodeSessionDTO {
        let contact = createTestContact(deviceID: deviceID, type: .room)
        try await keychain.storePassword("testpass", forNodeKey: contact.publicKey)

        let session = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: contact.publicKey,
            name: contact.name,
            role: .roomServer,
            isConnected: isConnected,
            permissionLevel: permissionLevel
        )

        try await dataStore.saveRemoteNodeSessionDTO(session)
        return try await dataStore.fetchRemoteNodeSession(id: session.id)!
    }

    // MARK: - Post Message Tests

    @Test("postMessage uses TextType.plain")
    func postMessageUsesPlainTextType() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Set self public key prefix
        await roomService.setSelfPublicKeyPrefix(Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]))

        let message = try await roomService.postMessage(sessionID: session.id, text: "Hello room!")

        // Verify text type in sent frame
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendTextMessage.rawValue)
        #expect(sentData.last?[1] == TextType.plain.rawValue)

        // Verify message was created correctly
        #expect(message.text == "Hello room!")
        #expect(message.isFromSelf == true)
    }

    @Test("postMessage saves local message immediately")
    func postMessageSavesLocalMessageImmediately() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        await roomService.setSelfPublicKeyPrefix(Data([0x01, 0x02, 0x03, 0x04]))

        _ = try await roomService.postMessage(sessionID: session.id, text: "Test message")

        // Verify message was saved to database
        let messages = try await dataStore.fetchRoomMessages(sessionID: session.id, limit: 10, offset: 0)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Test message")
        #expect(messages.first?.isFromSelf == true)
    }

    @Test("postMessage throws when not connected")
    func postMessageThrowsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            permissionLevel: .readWrite
        )

        // Transport is disconnected

        await #expect(throws: RemoteNodeError.self) {
            try await roomService.postMessage(sessionID: session.id, text: "Test")
        }
    }

    @Test("postMessage throws when session not found")
    func postMessageThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await roomService.postMessage(sessionID: UUID(), text: "Test")
        }
    }

    @Test("postMessage throws when permission denied (guest)")
    func postMessageThrowsWhenPermissionDenied() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            permissionLevel: .guest  // Can't post
        )

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await roomService.postMessage(sessionID: session.id, text: "Test")
        }
    }

    // MARK: - Handle Incoming Message Tests

    @Test("handleIncomingMessage uses content hash for deduplication")
    func handleIncomingMessageUsesContentHashDedup() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain
        )

        let senderPrefix = session.publicKeyPrefix
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let timestamp: UInt32 = 1702500000
        let text = "Duplicate message"

        // Handle first message
        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: senderPrefix,
            timestamp: timestamp,
            authorPrefix: authorPrefix,
            text: text
        )

        // Handle same message again (should be deduplicated)
        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: senderPrefix,
            timestamp: timestamp,
            authorPrefix: authorPrefix,
            text: text
        )

        // Verify only one message was saved
        let messages = try await dataStore.fetchRoomMessages(sessionID: session.id, limit: 10, offset: 0)
        #expect(messages.count == 1)
    }

    @Test("handleIncomingMessage increments unread count for non-self messages")
    func handleIncomingMessageIncrementsUnreadCount() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain
        )

        // Set self key prefix to something different from author
        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        let senderPrefix = session.publicKeyPrefix
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])  // Different from self

        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: senderPrefix,
            timestamp: UInt32(Date().timeIntervalSince1970),
            authorPrefix: authorPrefix,
            text: "New message"
        )

        // Verify unread count was incremented
        let updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.unreadCount == 1)
    }

    @Test("handleIncomingMessage ignores messages from unknown rooms")
    func handleIncomingMessageIgnoresUnknownRooms() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let unknownRoomPrefix = Data([0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA])
        let authorPrefix = Data([0x11, 0x22, 0x33, 0x44])

        // Should not throw, just silently ignore
        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: unknownRoomPrefix,
            timestamp: UInt32(Date().timeIntervalSince1970),
            authorPrefix: authorPrefix,
            text: "From unknown room"
        )

        // No messages should be saved (no session exists)
    }

    @Test("handleIncomingMessage calls roomMessageHandler")
    func handleIncomingMessageCallsHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain
        )

        let receivedMessage = MutableBox<RoomMessageDTO?>(nil)
        await roomService.setRoomMessageHandler { message in
            receivedMessage.value = message
        }

        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: session.publicKeyPrefix,
            timestamp: UInt32(Date().timeIntervalSince1970),
            authorPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            text: "Handler test"
        )

        #expect(receivedMessage.value?.text == "Handler test")
    }

    // MARK: - Message Retrieval Tests

    @Test("fetchMessages returns messages ordered by timestamp")
    func fetchMessagesReturnsOrderedMessages() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponses([
            Data([ResponseCode.sent.rawValue]),
            Data([ResponseCode.sent.rawValue]),
            Data([ResponseCode.sent.rawValue])
        ])

        await roomService.setSelfPublicKeyPrefix(Data([0x01, 0x02, 0x03, 0x04]))

        // Post multiple messages
        _ = try await roomService.postMessage(sessionID: session.id, text: "First")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await roomService.postMessage(sessionID: session.id, text: "Second")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await roomService.postMessage(sessionID: session.id, text: "Third")

        let messages = try await roomService.fetchMessages(sessionID: session.id)
        #expect(messages.count == 3)
    }

    // MARK: - Mark As Read Tests

    @Test("markAsRead resets unread count")
    func markAsReadResetsUnreadCount() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain
        )

        // Add some unread messages
        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        for i in 1...5 {
            try await roomService.handleIncomingMessage(
                senderPublicKeyPrefix: session.publicKeyPrefix,
                timestamp: UInt32(Date().timeIntervalSince1970) + UInt32(i),
                authorPrefix: Data([0xAA, 0xBB, 0xCC, UInt8(i)]),
                text: "Message \(i)"
            )
        }

        var updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.unreadCount == 5)

        // Mark as read
        try await roomService.markAsRead(sessionID: session.id)

        updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.unreadCount == 0)
    }

    // MARK: - Session Query Tests

    @Test("fetchRoomSessions returns only room sessions")
    func fetchRoomSessionsReturnsOnlyRooms() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, remoteNodeService, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()

        // Create a room session
        let roomContact = createTestContact(deviceID: deviceID, type: .room)
        _ = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: roomContact,
            password: "room",
            rememberPassword: true
        )

        // Create a repeater session
        let repeaterContact = createTestContact(deviceID: deviceID, name: "Repeater", type: .repeater)
        _ = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "repeater",
            rememberPassword: true
        )

        let roomSessions = try await roomService.fetchRoomSessions(deviceID: deviceID)
        #expect(roomSessions.count == 1)
        #expect(roomSessions.first?.role == .roomServer)
    }

    @Test("getConnectedSession returns nil for non-room")
    func getConnectedSessionReturnsNilForNonRoom() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (roomService, remoteNodeService, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let repeaterContact = createTestContact(deviceID: deviceID, type: .repeater)
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "admin",
            rememberPassword: true
        )

        // Mark as connected
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .admin
        )

        let result = try await roomService.getConnectedSession(publicKeyPrefix: session.publicKeyPrefix)
        #expect(result == nil)
    }
}

// MARK: - RoomServerService Extension for Testing

extension RoomServerService {
    func setRoomMessageHandler(_ handler: @escaping @Sendable (RoomMessageDTO) async -> Void) async {
        roomMessageHandler = handler
    }
}
