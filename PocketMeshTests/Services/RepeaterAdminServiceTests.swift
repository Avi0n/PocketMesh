import Testing
import Foundation
@testable import PocketMeshKit

@Suite("RepeaterAdminService Tests")
struct RepeaterAdminServiceTests {

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
    ) -> (RepeaterAdminService, RemoteNodeService, BinaryProtocolService, MockKeychainService) {
        let keychain = MockKeychainService()
        let binaryProtocol = BinaryProtocolService(bleTransport: transport)
        let remoteNodeService = RemoteNodeService(
            bleTransport: transport,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore,
            keychainService: keychain
        )
        let repeaterAdminService = RepeaterAdminService(
            remoteNodeService: remoteNodeService,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore
        )
        return (repeaterAdminService, remoteNodeService, binaryProtocol, keychain)
    }

    private func createTestContact(
        deviceID: UUID,
        name: String = "TestRepeater",
        type: ContactType = .repeater,
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
        role: RemoteNodeRole = .repeater,
        isConnected: Bool = true,
        permissionLevel: RoomPermissionLevel = .admin
    ) async throws -> RemoteNodeSessionDTO {
        let contact = createTestContact(deviceID: deviceID, type: role == .repeater ? .repeater : .room)
        try await keychain.storePassword("adminpass", forNodeKey: contact.publicKey)

        let session = RemoteNodeSessionDTO(
            deviceID: deviceID,
            publicKey: contact.publicKey,
            name: contact.name,
            role: role,
            isConnected: isConnected,
            permissionLevel: permissionLevel
        )

        try await dataStore.saveRemoteNodeSessionDTO(session)
        return try await dataStore.fetchRemoteNodeSession(id: session.id)!
    }

    // MARK: - Connect As Admin Tests

    @Test("connectAsAdmin creates session and logs in")
    func connectAsAdminCreatesSessionAndLogsIn() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, _, _, keychain) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .repeater)
        let password = "adminpass"

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        // Start connect in background (it will wait for login result push)
        let connectTask = Task {
            try await repeaterService.connectAsAdmin(
                deviceID: deviceID,
                contact: contact,
                password: password,
                rememberPassword: true
            )
        }

        // Let the send happen
        try await Task.sleep(for: .milliseconds(50))

        // Verify login frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData[0][0] == CommandCode.sendLogin.rawValue)

        // Verify password was stored
        let stored = try await keychain.retrievePassword(forNodeKey: contact.publicKey)
        #expect(stored == password)

        // Cancel the connect task (it would timeout waiting for push)
        connectTask.cancel()
    }

    // MARK: - Disconnect Tests

    @Test("disconnect sends logout and removes session")
    func disconnectSendsLogoutAndRemovesSession() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, remoteNodeService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID, type: .repeater)

        // Create session manually
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: contact,
            password: "adminpass",
            rememberPassword: true
        )

        // Mark as connected
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .admin
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        try await repeaterService.disconnect(sessionID: session.id, publicKey: session.publicKey)

        // Verify logout frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.logout.rawValue)

        // Verify session was deleted
        let fetchedSession = try await dataStore.fetchRemoteNodeSession(id: session.id)
        #expect(fetchedSession == nil)
    }

    // MARK: - Request Neighbors Tests

    @Test("requestNeighbors throws when session not found")
    func requestNeighborsThrowsWhenSessionNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await repeaterService.requestNeighbors(sessionID: UUID())
        }
    }

    @Test("requestNeighbors throws for room session")
    func requestNeighborsThrowsForRoomSession() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .roomServer  // Not a repeater
        )

        await transport.setConnectionState(.ready)

        await #expect(throws: RemoteNodeError.self) {
            try await repeaterService.requestNeighbors(sessionID: session.id)
        }
    }

    @Test("requestNeighbors sends correct frame for repeater session")
    func requestNeighborsSendsCorrectFrame() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .repeater
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        _ = try await repeaterService.requestNeighbors(sessionID: session.id)

        // Verify neighbors request frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendBinaryRequest.rawValue)
    }

    @Test("requestNeighbors uses default pubkey prefix length")
    func requestNeighborsUsesDefaultPrefixLength() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .repeater
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        _ = try await repeaterService.requestNeighbors(
            sessionID: session.id,
            count: 20,
            offset: 0,
            orderBy: .newestFirst
            // Uses default pubkeyPrefixLength
        )

        // Default prefix length should be 6
        #expect(RepeaterAdminService.defaultPubkeyPrefixLength == 6)
    }

    // MARK: - Request Status Tests

    @Test("requestStatus delegates to RemoteNodeService")
    func requestStatusDelegatesToRemoteNodeService() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .repeater
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        _ = try await repeaterService.requestStatus(sessionID: session.id)

        // Verify status request frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendBinaryRequest.rawValue)
    }

    // MARK: - Request Telemetry Tests

    @Test("requestTelemetry sends correct frame")
    func requestTelemetrySendsCorrectFrame() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .repeater
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        try await repeaterService.requestTelemetry(sessionID: session.id)

        // Verify telemetry request frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendTelemetryRequest.rawValue)
    }

    // MARK: - Send Command Tests

    @Test("sendCommand sends CLI command")
    func sendCommandSendsCLICommand() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let keychain = MockKeychainService()
        let (repeaterService, _, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let session = try await createTestSession(
            deviceID: deviceID,
            dataStore: dataStore,
            keychain: keychain,
            role: .repeater,
            permissionLevel: .admin
        )

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.sent.rawValue]))

        _ = try await repeaterService.sendCommand(sessionID: session.id, command: "help")

        // Verify CLI command frame was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count >= 1)
        #expect(sentData.last?[0] == CommandCode.sendTextMessage.rawValue)
        #expect(sentData.last?[1] == TextType.cliData.rawValue)
    }

    // MARK: - Session Query Tests

    @Test("fetchRepeaterSessions returns only repeater sessions")
    func fetchRepeaterSessionsReturnsOnlyRepeaters() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, remoteNodeService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()

        // Create a repeater session
        let repeaterContact = createTestContact(deviceID: deviceID, type: .repeater)
        _ = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "admin",
            rememberPassword: true
        )

        // Create a room session
        let roomContact = createTestContact(deviceID: deviceID, name: "Room", type: .room)
        _ = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: roomContact,
            password: "room",
            rememberPassword: true
        )

        let repeaterSessions = try await repeaterService.fetchRepeaterSessions(deviceID: deviceID)
        #expect(repeaterSessions.count == 1)
        #expect(repeaterSessions.first?.role == .repeater)
    }

    @Test("getConnectedSession returns nil for non-repeater")
    func getConnectedSessionReturnsNilForNonRepeater() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, remoteNodeService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, name: "Room", type: .room)
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: roomContact,
            password: "room",
            rememberPassword: true
        )

        // Mark as connected
        try await dataStore.updateRemoteNodeSessionConnection(
            id: session.id,
            isConnected: true,
            permissionLevel: .readWrite
        )

        let result = try await repeaterService.getConnectedSession(publicKeyPrefix: session.publicKeyPrefix)
        #expect(result == nil)
    }

    @Test("getConnectedSession returns session for connected repeater")
    func getConnectedSessionReturnsConnectedRepeater() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, remoteNodeService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

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

        let result = try await repeaterService.getConnectedSession(publicKeyPrefix: session.publicKeyPrefix)
        #expect(result != nil)
        #expect(result?.id == session.id)
    }

    @Test("getConnectedSession returns nil for disconnected repeater")
    func getConnectedSessionReturnsNilForDisconnectedRepeater() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (repeaterService, remoteNodeService, _, _) = createTestServices(transport: transport, dataStore: dataStore)

        let deviceID = UUID()
        let repeaterContact = createTestContact(deviceID: deviceID, type: .repeater)
        let session = try await remoteNodeService.createSession(
            deviceID: deviceID,
            contact: repeaterContact,
            password: "admin",
            rememberPassword: true
        )

        // Session is not connected by default

        let result = try await repeaterService.getConnectedSession(publicKeyPrefix: session.publicKeyPrefix)
        #expect(result == nil)
    }
}
