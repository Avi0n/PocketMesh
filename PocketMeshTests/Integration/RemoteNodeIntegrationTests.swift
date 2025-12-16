import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Remote Node Integration Tests")
struct RemoteNodeIntegrationTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createFullTestStack(
        transport: TestBLETransport,
        dataStore: DataStore
    ) -> (
        RemoteNodeService,
        RoomServerService,
        RepeaterAdminService,
        BinaryProtocolService,
        MockKeychainService
    ) {
        let keychain = MockKeychainService()
        let binaryProtocol = BinaryProtocolService(bleTransport: transport)
        let remoteNodeService = RemoteNodeService(
            bleTransport: transport,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore,
            keychainService: keychain
        )
        let contactService = ContactService(
            bleTransport: transport,
            dataStore: dataStore
        )
        let roomServerService = RoomServerService(
            remoteNodeService: remoteNodeService,
            bleTransport: transport,
            dataStore: dataStore,
            contactService: contactService
        )
        let repeaterAdminService = RepeaterAdminService(
            remoteNodeService: remoteNodeService,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore
        )
        return (remoteNodeService, roomServerService, repeaterAdminService, binaryProtocol, keychain)
    }

    private func createTestContact(
        deviceID: UUID,
        name: String = "TestNode",
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

    // MARK: - Room Discovery → Join → Post → Receive Flow

    @Test("Room flow: create session, post message, receive message")
    func roomFlowCreateSessionPostReceive() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (_, roomService, _, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, name: "Chat Room", type: .room)

        // Save contact to database (simulating discovery)
        try await dataStore.saveContact(roomContact)

        // Set up transport for responses
        await transport.setConnectionState(.ready)
        await transport.queueResponses([
            Data([ResponseCode.sent.rawValue]),  // For login
            Data([ResponseCode.sent.rawValue])   // For message post
        ])

        // Create session
        let session = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: roomContact.publicKey,
            name: roomContact.name,
            role: .roomServer,
            isConnected: true,
            permissionLevel: .readWrite
        )
        try await dataStore.saveRemoteNodeSessionDTO(session)
        try await keychain.storePassword("roompass", forNodeKey: roomContact.publicKey)

        // Set self key prefix
        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        // Post a message
        let postedMessage = try await roomService.postMessage(
            sessionID: session.id,
            text: "Hello from the room!"
        )

        #expect(postedMessage.text == "Hello from the room!")
        #expect(postedMessage.isFromSelf == true)

        // Simulate receiving a message from another user
        let receivedMessages = MutableBox<[RoomMessageDTO]>([])
        await roomService.setRoomMessageHandler { message in
            receivedMessages.value.append(message)
        }

        try await roomService.handleIncomingMessage(
            senderPublicKeyPrefix: session.publicKeyPrefix,
            timestamp: UInt32(Date().timeIntervalSince1970),
            authorPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]),
            text: "Hello from Alice!"
        )

        // Verify received message
        #expect(receivedMessages.value.count == 1)
        #expect(receivedMessages.value.first?.text == "Hello from Alice!")
        #expect(receivedMessages.value.first?.isFromSelf == false)

        // Verify all messages are in database
        let allMessages = try await dataStore.fetchRoomMessages(sessionID: session.id, limit: 10, offset: 0)
        #expect(allMessages.count == 2)
    }

    // MARK: - Repeater Discovery → Connect → Fetch Status Flow

    @Test("Repeater flow: create session, fetch status")
    func repeaterFlowCreateSessionFetchStatus() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (remoteNodeService, _, repeaterService, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let repeaterContact = createTestContact(deviceID: deviceID, name: "Mountain Repeater", type: .repeater)

        // Save contact to database (simulating discovery)
        try await dataStore.saveContact(repeaterContact)

        // Set up transport
        await transport.setConnectionState(.ready)
        await transport.queueResponses([
            Data([ResponseCode.sent.rawValue]),  // For status request
        ])

        // Create session using remoteNodeService
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "adminpass",
            rememberPassword: true
        )

        // Mark as connected with admin permissions
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .admin
        )

        // Request status
        _ = try await repeaterService.requestStatus(sessionID: session.id)

        // Verify status request was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendBinaryRequest.rawValue)

        // Request neighbors
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))
        _ = try await repeaterService.requestNeighbors(sessionID: session.id)

        let sentDataAfterNeighbors = await transport.getSentData()
        #expect(sentDataAfterNeighbors.count >= 2)
    }

    // MARK: - Message Deduplication Tests

    @Test("Message deduplication prevents duplicate saves")
    func messageDeduplicationPreventsDuplicates() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (_, roomService, _, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, type: .room)
        try await dataStore.saveContact(roomContact)

        let session = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: roomContact.publicKey,
            name: roomContact.name,
            role: .roomServer,
            isConnected: true,
            permissionLevel: .readWrite
        )
        try await dataStore.saveRemoteNodeSessionDTO(session)
        try await keychain.storePassword("pass", forNodeKey: roomContact.publicKey)

        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        let timestamp: UInt32 = 1702500000
        let authorPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let text = "Test message"

        // Handle same message multiple times
        for _ in 1...5 {
            try await roomService.handleIncomingMessage(
                senderPublicKeyPrefix: session.publicKeyPrefix,
                timestamp: timestamp,
                authorPrefix: authorPrefix,
                text: text
            )
        }

        // Verify only one message was saved
        let messages = try await dataStore.fetchRoomMessages(sessionID: session.id, limit: 100, offset: 0)
        #expect(messages.count == 1)
    }

    // MARK: - Cross-Service Tests

    @Test("Session can be fetched by different services")
    func sessionCanBeFetchedByDifferentServices() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (remoteNodeService, roomService, repeaterService, _, _) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()

        // Create room via remoteNodeService
        let roomContact = createTestContact(deviceID: deviceID, name: "Room", type: .room)
        let roomSession = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: roomContact,
            password: "roompass",
            rememberPassword: true
        )
        try await dataStore.updateRemoteNodeSessionConnection(
            id: roomSession.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        // Create repeater via remoteNodeService
        let repeaterContact = createTestContact(deviceID: deviceID, name: "Repeater", type: .repeater)
        let repeaterSession = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "adminpass",
            rememberPassword: true
        )
        try await dataStore.updateRemoteNodeSessionConnection(
            id: repeaterSession.id,
            isConnected: true,
            permissionLevel: .admin
        )

        // Fetch via room service
        let roomSessions = try await roomService.fetchRoomSessions(deviceID: deviceID)
        #expect(roomSessions.count == 1)
        #expect(roomSessions.first?.name == "Room")

        // Fetch via repeater service
        let repeaterSessions = try await repeaterService.fetchRepeaterSessions(deviceID: deviceID)
        #expect(repeaterSessions.count == 1)
        #expect(repeaterSessions.first?.name == "Repeater")
    }

    // MARK: - Logout Cleanup Tests

    @Test("Logout cleans up keep-alive and updates session")
    func logoutCleansUpAndUpdatesSession() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (remoteNodeService, _, _, _, _) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: roomContact,
            password: "pass",
            rememberPassword: true
        )

        // Mark as connected
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Logout
        try await remoteNodeService.logout(sessionID: session.id)

        // Verify session is marked as disconnected
        let updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.isConnected == false)
        #expect(updatedSession?.permissionLevel == .guest)
    }

    // MARK: - Permission Level Tests

    @Test("Permission levels correctly gate functionality")
    func permissionLevelsGateFunctionality() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (_, roomService, _, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, type: .room)
        try await dataStore.saveContact(roomContact)

        // Create guest session
        let guestSession = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: roomContact.publicKey,
            name: roomContact.name,
            role: .roomServer,
            isConnected: true,
            permissionLevel: .guest
        )
        try await dataStore.saveRemoteNodeSessionDTO(guestSession)
        try await keychain.storePassword("pass", forNodeKey: roomContact.publicKey)

        await transport.setConnectionState(.ready)

        // Guest cannot post
        await #expect(throws: RemoteNodeError.self) {
            try await roomService.postMessage(sessionID: guestSession.id, text: "Should fail")
        }
    }

    // MARK: - Error Recovery Tests

    @Test("Service handles transport errors gracefully")
    func serviceHandlesTransportErrors() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (_, roomService, _, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, type: .room)
        try await dataStore.saveContact(roomContact)

        let session = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: roomContact.publicKey,
            name: roomContact.name,
            role: .roomServer,
            isConnected: true,
            permissionLevel: .readWrite
        )
        try await dataStore.saveRemoteNodeSessionDTO(session)
        try await keychain.storePassword("pass", forNodeKey: roomContact.publicKey)

        await transport.setConnectionState(.ready)
        await transport.setNextSendToFail()

        await roomService.setSelfPublicKeyPrefix(Data([0x11, 0x22, 0x33, 0x44]))

        // Should throw but not crash
        await #expect(throws: Error.self) {
            try await roomService.postMessage(sessionID: session.id, text: "Test")
        }
    }
}
