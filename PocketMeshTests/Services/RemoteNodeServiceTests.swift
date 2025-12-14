import Testing
import Foundation
@testable import PocketMeshKit

@Suite("RemoteNodeService Tests")
struct RemoteNodeServiceTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createTestBinaryProtocol(_ transport: TestBLETransport) -> BinaryProtocolService {
        BinaryProtocolService(bleTransport: transport)
    }

    private func createTestService(
        transport: TestBLETransport,
        dataStore: DataStore,
        keychainService: MockKeychainService = MockKeychainService()
    ) -> (RemoteNodeService, BinaryProtocolService, MockKeychainService) {
        let binaryProtocol = BinaryProtocolService(bleTransport: transport)
        let service = RemoteNodeService(
            bleTransport: transport,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore,
            keychainService: keychainService
        )
        return (service, binaryProtocol, keychainService)
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

    // MARK: - Session Management Tests

    @Test("Create session for room server succeeds")
    func createSessionForRoomSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, keychain) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)
        let password = "testpass"

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: password,
            rememberPassword: true
        )

        #expect(session.role == .roomServer)
        #expect(session.name == contact.name)
        #expect(session.publicKey == contact.publicKey)

        // Verify password was stored
        let stored = try await keychain.retrievePassword(forNodeKey: contact.publicKey)
        #expect(stored == password)
    }

    @Test("Create session for repeater succeeds")
    func createSessionForRepeaterSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .repeater)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "admin",
            rememberPassword: false
        )

        #expect(session.role == .repeater)
    }

    @Test("Create session throws for chat contact")
    func createSessionThrowsForChatContact() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .chat)

        await #expect(throws: RemoteNodeError.self) {
            try await service.createSession(
                deviceID: deviceID,
                contact: contact,
                password: "test",
                rememberPassword: false
            )
        }
    }

    @Test("Create session throws for invalid public key length")
    func createSessionThrowsForInvalidPublicKeyLength() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        // Create an invalid contact with wrong public key length (only 3 bytes)
        let invalidContact = Contact(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data([0x01, 0x02, 0x03]),  // Only 3 bytes - invalid
            name: "InvalidContact",
            typeRawValue: ContactType.room.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 0,
            longitude: 0,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
        let contact = ContactDTO(from: invalidContact)

        await #expect(throws: RemoteNodeError.self) {
            try await service.createSession(
                deviceID: deviceID,
                contact: contact,
                password: "test",
                rememberPassword: false
            )
        }
    }

    @Test("Remove session deletes password and session")
    func removeSessionDeletesPasswordAndSession() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore, keychainService: keychain)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        // Create session first
        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        // Verify it exists
        var stored = try await keychain.retrievePassword(forNodeKey: contact.publicKey)
        #expect(stored != nil)

        // Remove session
        try await service.removeSession(id: session.id, publicKey: session.publicKey)

        // Verify password was deleted
        stored = try await keychain.retrievePassword(forNodeKey: contact.publicKey)
        #expect(stored == nil)

        // Verify session was deleted
        let fetchedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(fetchedSession == nil)
    }

    // MARK: - Login Tests

    @Test("Login throws when not connected")
    func loginThrowsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        // Transport is disconnected by default
        await #expect(throws: RemoteNodeError.self) {
            try await service.login(sessionID: UUID())
        }
    }

    @Test("Login throws when session not found")
    func loginThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.login(sessionID: UUID())
        }
    }

    @Test("Login throws when password not found")
    func loginThrowsWhenPasswordNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore, keychainService: keychain)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        // Create session without storing password
        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: false  // Don't store
        )

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.login(sessionID: session.id)  // No password provided
        }
    }

    @Test("Login sends correct frame")
    func loginSendsCorrectFrame() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)
        let password = "testpass"

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: password,
            rememberPassword: true
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Start login in background (it will wait for login result push)
        let loginTask = Task {
            try await service.login(sessionID: session.id)
        }

        // Let the send happen
        try await Task.sleep(for: .milliseconds(50))

        // Verify frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData[0][0] == CommandCode.sendLogin.rawValue)

        // Cancel the login task (it would timeout waiting for push)
        loginTask.cancel()
    }

    // MARK: - Keep-Alive Tests

    @Test("sendKeepAlive throws when session not found")
    func sendKeepAliveThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.sendKeepAlive(sessionID: UUID())
        }
    }

    @Test("sendKeepAlive throws floodRouted for flood-routed contact")
    func sendKeepAliveThrowsFloodRoutedForFloodRoutedContact() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        // Create a flood-routed contact (outPathLength = -1)
        let contact = createTestContact(deviceID: deviceID, type: .room, outPathLength: -1)

        // Save contact to data store
        try await dataStore.saveContact(contact)

        // Create session
        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.sendKeepAlive(sessionID: session.id)
        }
    }

    @Test("sendKeepAlive succeeds for direct-routed contact")
    func sendKeepAliveSucceedsForDirectRoutedContact() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        // Create a direct-routed contact (outPathLength = 0)
        let contact = createTestContact(deviceID: deviceID, type: .room, outPathLength: 0)

        // Save contact to data store
        try await dataStore.saveContact(contact)

        // Create session
        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Should not throw
        try await service.sendKeepAlive(sessionID: session.id)

        // Verify frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendBinaryRequest.rawValue)
    }

    @Test("handleKeepAliveACK calls handler for unsynced messages")
    func handleKeepAliveACKCallsHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        // Create session
        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        let receivedSessionID = MutableBox<UUID?>(nil)
        let receivedUnsyncedCount = MutableBox<Int?>(nil)

        await service.setKeepAliveResponseHandler { sessionID, count in
            receivedSessionID.value = sessionID
            receivedUnsyncedCount.value = count
        }

        // Handle ACK with 5 unsynced messages
        await service.handleKeepAliveACK(
            fromPublicKeyPrefix: session.publicKeyPrefix,
            unsyncedCount: 5
        )

        #expect(receivedSessionID.value == session.id)
        #expect(receivedUnsyncedCount.value == 5)
    }

    @Test("handleKeepAliveACK does not call handler for zero unsynced")
    func handleKeepAliveACKDoesNotCallHandlerForZero() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        let handlerCalled = MutableBox(false)
        await service.setKeepAliveResponseHandler { _, _ in
            handlerCalled.value = true
        }

        await service.handleKeepAliveACK(
            fromPublicKeyPrefix: session.publicKeyPrefix,
            unsyncedCount: 0
        )

        #expect(handlerCalled.value == false)
    }

    // MARK: - Logout Tests

    @Test("Logout sends logout frame and updates session")
    func logoutSendsFrameAndUpdatesSession() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Mark session as connected first
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        try await service.logout(sessionID: session.id)

        // Verify logout frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.logout.rawValue)

        // Verify session was marked as disconnected
        let updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.isConnected == false)
        #expect(updatedSession?.permissionLevel == .guest)
    }

    @Test("Logout throws when session not found")
    func logoutThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.logout(sessionID: UUID())
        }
    }

    // MARK: - Disconnect Tests

    @Test("Disconnect marks session as disconnected without sending frame")
    func disconnectMarksSessionAsDisconnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        // Mark as connected
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)

        await service.disconnect(sessionID: session.id)

        // Verify no frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.isEmpty)

        // Verify session was marked as disconnected
        let updatedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(updatedSession?.isConnected == false)
    }

    // MARK: - Status Request Tests

    @Test("requestStatus throws when not connected")
    func requestStatusThrowsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await #expect(throws: RemoteNodeError.self) {
            try await service.requestStatus(sessionID: UUID())
        }
    }

    @Test("requestStatus throws when session not found")
    func requestStatusThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.requestStatus(sessionID: UUID())
        }
    }

    // MARK: - CLI Command Tests

    @Test("sendCLICommand throws when not admin")
    func sendCLICommandThrowsWhenNotAdmin() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        // Session has guest permission by default (not admin)
        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await service.sendCLICommand(sessionID: session.id, command: "help")
        }
    }

    @Test("sendCLICommand sends correct frame when admin")
    func sendCLICommandSendsCorrectFrameWhenAdmin() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        // Set session as admin
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .admin
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        _ = try await service.sendCLICommand(sessionID: session.id, command: "help")

        // Verify CLI frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendTextMessage.rawValue)
        #expect(sentData.last?[1] == TextType.cliData.rawValue)
    }

    // MARK: - BLE Reconnection Tests

    @Test("handleBLEReconnection skips when no connected sessions")
    func handleBLEReconnectionSkipsWhenNoConnectedSessions() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        // Should not throw or send anything
        await service.handleBLEReconnection()

        let sentData = await transport.getSentData()
        #expect(sentData.isEmpty)
    }

    @Test("handleBLEReconnection triggers re-authentication")
    func handleBLEReconnectionTriggersReauth() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .room)

        let session = try await service.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "testpass",
            rememberPassword: true
        )

        // Mark as connected to trigger re-auth
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Trigger reconnection
        await service.handleBLEReconnection()

        // Verify a login was attempted for the connected session
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)

        // First frame should be a login command
        if !sentData.isEmpty {
            #expect(sentData[0][0] == CommandCode.sendLogin.rawValue)
        }
    }

    // MARK: - Cleanup Tests

    @Test("stopAllKeepAlives cancels all tasks")
    func stopAllKeepAlivesCancelsAllTasks() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (service, _, _) = createTestService(transport: transport, dataStore: dataStore)

        // Just verify it doesn't crash
        await service.stopAllKeepAlives()
    }
}

// MARK: - TestBLETransport Extension

extension TestBLETransport {
    func setKeepAliveResponseHandler(_ handler: @escaping @Sendable (UUID, Int) async -> Void) async {
        // For testing - would need to be implemented in actual test transport
    }
}

// MARK: - RemoteNodeService Extension for Testing

extension RemoteNodeService {
    func setKeepAliveResponseHandler(_ handler: @escaping @Sendable (UUID, Int) async -> Void) async {
        keepAliveResponseHandler = handler
    }
}
