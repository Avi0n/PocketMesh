import Testing
import Foundation
@testable import PocketMeshKit

@Suite("AdvertisementService Tests")
struct AdvertisementServiceTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createTestContact(deviceID: UUID, name: String = "TestContact") -> ContactFrame {
        ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
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

    // MARK: - Send Self Advertisement Tests

    @Test("Send self advertisement with zero-hop succeeds")
    func sendSelfAdvertZeroHopSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendSelfAdvertisement(flood: false)
        #expect(result == true)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.sendSelfAdvert.rawValue)
        #expect(sentData[0][1] == 0)  // zero-hop (not flood)
    }

    @Test("Send self advertisement with flood succeeds")
    func sendSelfAdvertFloodSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendSelfAdvertisement(flood: true)
        #expect(result == true)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.sendSelfAdvert.rawValue)
        #expect(sentData[0][1] == 1)  // flood
    }

    @Test("Send advertisement fails when not connected")
    func sendAdvertFailsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        // Transport not connected (default state)
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: AdvertisementError.self) {
            try await service.sendSelfAdvertisement(flood: false)
        }
    }

    @Test("Send advertisement fails when send fails")
    func sendAdvertFailsWhenSendFails() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(nil)  // No response

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: AdvertisementError.self) {
            try await service.sendSelfAdvertisement(flood: false)
        }
    }

    // MARK: - Set Advert Name Tests

    @Test("Set advert name succeeds")
    func setAdvertNameSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        try await service.setAdvertName("MyNode")

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.setAdvertName.rawValue)

        let nameData = sentData[0].suffix(from: 1)
        let name = String(data: nameData, encoding: .utf8)
        #expect(name == "MyNode")
    }

    @Test("Set advert name truncates long names")
    func setAdvertNameTruncatesLongNames() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)
        let longName = String(repeating: "A", count: 50)

        try await service.setAdvertName(longName)

        // Verify name was truncated (max 31 chars)
        let sentData = await transport.getSentData()
        let nameData = sentData[0].suffix(from: 1)
        #expect(nameData.count <= 31)
    }

    // MARK: - Set Advert Location Tests

    @Test("Set advert location succeeds")
    func setAdvertLocationSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        try await service.setAdvertLocation(latitude: 37.7749, longitude: -122.4194)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.setAdvertLatLon.rawValue)
        #expect(sentData[0].count == 9)  // command + 4 bytes lat + 4 bytes lon
    }

    @Test("Set advert location with edge coordinates")
    func setAdvertLocationWithEdgeCoordinates() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        // Test max values
        try await service.setAdvertLocation(latitude: 90.0, longitude: 180.0)

        await transport.clearSentData()
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        // Test min values
        try await service.setAdvertLocation(latitude: -90.0, longitude: -180.0)
    }

    // MARK: - Push Handling Tests

    @Test("Handle advert push updates contact timestamp")
    func handleAdvertPushUpdatesContactTimestamp() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        _ = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        // Create advert push data: [0x80][pub_key_prefix:6][timestamp:4]
        let newTimestamp: UInt32 = UInt32(Date().timeIntervalSince1970) + 100
        var pushData = Data([PushCode.advert.rawValue])
        pushData.append(contact.publicKey.prefix(6))
        pushData.append(contentsOf: withUnsafeBytes(of: newTimestamp.littleEndian) { Array($0) })

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == true)
    }

    @Test("Handle new advert push saves contact")
    func handleNewAdvertPushSavesContact() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let advertHandlerCalled = MutableBox(false)
        await service.setAdvertHandler { _ in
            advertHandlerCalled.value = true
        }

        // Create full contact frame with PUSH_CODE_NEW_ADVERT prefix
        let contact = createTestContact(deviceID: deviceID, name: "NewContact")
        var pushData = Data([PushCode.newAdvert.rawValue])
        pushData.append(contact.publicKey)
        pushData.append(contact.type.rawValue)
        pushData.append(contact.flags)
        pushData.append(UInt8(bitPattern: Int8(contact.outPathLength)))

        var pathData = contact.outPath.prefix(64)
        pathData.append(Data(repeating: 0, count: max(0, 64 - pathData.count)))
        pushData.append(pathData)

        var nameData = (contact.name.data(using: .utf8) ?? Data()).prefix(32)
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        pushData.append(nameData)

        pushData.append(contentsOf: withUnsafeBytes(of: contact.lastAdvertTimestamp.littleEndian) { Array($0) })
        let latInt = Int32(contact.latitude * 1_000_000)
        let lonInt = Int32(contact.longitude * 1_000_000)
        pushData.append(contentsOf: withUnsafeBytes(of: latInt.littleEndian) { Array($0) })
        pushData.append(contentsOf: withUnsafeBytes(of: lonInt.littleEndian) { Array($0) })
        pushData.append(contentsOf: withUnsafeBytes(of: contact.lastModified.littleEndian) { Array($0) })

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == true)

        // Verify contact was saved
        let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        #expect(contacts.count == 1)
        #expect(contacts.first?.name == "NewContact")
    }

    @Test("Handle path updated push updates path length")
    func handlePathUpdatedPushCallsRefreshHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        let savedID = try await dataStore.saveContact(deviceID: deviceID, from: contact)

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let pathRefreshCalled = MutableBox(false)
        let receivedDeviceID = MutableBox<UUID?>(nil)
        let receivedPublicKey = MutableBox<Data?>(nil)
        let receivedContactID = MutableBox<UUID?>(nil)
        let receivedWasFlood = MutableBox<Bool?>(nil)
        await service.setPathRefreshHandler { deviceID, publicKey, contactID, wasFlood in
            pathRefreshCalled.value = true
            receivedDeviceID.value = deviceID
            receivedPublicKey.value = publicKey
            receivedContactID.value = contactID
            receivedWasFlood.value = wasFlood
        }

        // Create path updated push: [0x81][publicKey:32] = 33 bytes (per meshcore_py reference)
        var pushData = Data([PushCode.pathUpdated.rawValue])
        pushData.append(contact.publicKey)  // Full 32-byte public key

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == true)
        #expect(pathRefreshCalled.value == true)
        #expect(receivedDeviceID.value == deviceID)
        #expect(receivedPublicKey.value == contact.publicKey)
        #expect(receivedContactID.value == savedID)
        #expect(receivedWasFlood.value == false)  // Contact has outPathLength=2, not flood
    }

    @Test("Handle path updated push with flood contact passes wasFlood=true")
    func handlePathUpdatedPushFloodContactPassesWasFloodTrue() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        // Create flood-routed contact (outPathLength = -1)
        let floodContact = ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: -1,  // Flood routed
            outPath: Data(),
            name: "FloodContact",
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
        let savedID = try await dataStore.saveContact(deviceID: deviceID, from: floodContact)

        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let pathRefreshCalled = MutableBox(false)
        let receivedWasFlood = MutableBox<Bool?>(nil)
        let receivedContactID = MutableBox<UUID?>(nil)
        await service.setPathRefreshHandler { _, _, contactID, wasFlood in
            pathRefreshCalled.value = true
            receivedContactID.value = contactID
            receivedWasFlood.value = wasFlood
        }

        // Create path updated push: [0x81][publicKey:32]
        var pushData = Data([PushCode.pathUpdated.rawValue])
        pushData.append(floodContact.publicKey)

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == true)
        #expect(pathRefreshCalled.value == true)
        #expect(receivedContactID.value == savedID)
        #expect(receivedWasFlood.value == true)  // Was flood routed
    }

    @Test("Handle path updated push with unknown contact does not call refresh handler")
    func handlePathUpdatedPushUnknownContactNoRefresh() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let pathRefreshCalled = MutableBox(false)
        await service.setPathRefreshHandler { _, _, _, _ in
            pathRefreshCalled.value = true
        }

        // Create path updated push with unknown public key
        var pushData = Data([PushCode.pathUpdated.rawValue])
        pushData.append(Data(repeating: 0xAB, count: 32))  // Unknown key

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == true)  // Push was handled (just no contact found)
        #expect(pathRefreshCalled.value == false)  // No refresh for unknown contact
    }

    @Test("Handle path updated push with short data returns false")
    func handlePathUpdatedPushShortDataReturnsFalse() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        // Create too-short path updated push (needs 33 bytes, only give 10)
        var pushData = Data([PushCode.pathUpdated.rawValue])
        pushData.append(Data(repeating: 0x42, count: 9))  // Only 10 bytes total

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == false)  // Too short
    }

    @Test("Handle unhandled push code returns false")
    func handleUnhandledPushCodeReturnsFalse() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        // Use a push code that AdvertisementService doesn't handle
        let pushData = Data([PushCode.messageWaiting.rawValue])

        let handled = await service.handlePush(pushData, deviceID: deviceID)
        #expect(handled == false)
    }

    @Test("Handle empty push data returns false")
    func handleEmptyPushDataReturnsFalse() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = AdvertisementService(bleTransport: transport, dataStore: dataStore)

        let handled = await service.handlePush(Data(), deviceID: deviceID)
        #expect(handled == false)
    }
}
