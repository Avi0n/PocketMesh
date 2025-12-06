import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Mock BLE Peripheral Tests")
struct MockBLEPeripheralTests {

    // MARK: - Connection Tests

    @Test("Connect and disconnect cycle")
    func connectDisconnect() async {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        #expect(await mock.connected == false)

        await mock.connect()
        #expect(await mock.connected == true)

        await mock.disconnect()
        #expect(await mock.connected == false)
    }

    @Test("Command fails when disconnected")
    func commandWhenDisconnected() async {
        let mock = MockBLEPeripheral()
        let query = FrameCodec.encodeDeviceQuery(protocolVersion: 8)

        await #expect(throws: ProtocolError.self) {
            _ = try await mock.processCommand(query)
        }
    }

    // MARK: - Device Query Tests

    @Test("Device query returns device info")
    func deviceQuery() async throws {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        await mock.connect()

        let query = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        let response = try await mock.processCommand(query)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.deviceInfo.rawValue)

        let info = try FrameCodec.decodeDeviceInfo(from: response!)
        #expect(info.firmwareVersion == 8)
        #expect(info.maxChannels == 8)
        #expect(info.maxContacts == 50)
    }

    // MARK: - App Start Tests

    @Test("App start returns self info")
    func appStart() async throws {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        await mock.connect()

        // First need device query
        _ = try await mock.processCommand(FrameCodec.encodeDeviceQuery(protocolVersion: 8))

        let appStart = FrameCodec.encodeAppStart(appName: "PocketMesh")
        let response = try await mock.processCommand(appStart)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.selfInfo.rawValue)

        let selfInfo = try FrameCodec.decodeSelfInfo(from: response!)
        #expect(selfInfo.nodeName == "TestNode")
        #expect(selfInfo.publicKey.count == 32)
    }

    // MARK: - Radio Params Tests

    @Test("Set radio params with valid input")
    func setRadioParamsValid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let params = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 10,
            codingRate: 5
        )
        let response = try await mock.processCommand(params)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.ok.rawValue)
        #expect(await mock.currentFrequency == 915000)
    }

    @Test("Set radio params with invalid frequency rejects")
    func setRadioParamsInvalidFrequency() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let params = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 100000, // Too low
            bandwidthKHz: 250000,
            spreadingFactor: 10,
            codingRate: 5
        )
        let response = try await mock.processCommand(params)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.error.rawValue)
        #expect(response![1] == ProtocolError.illegalArgument.rawValue)
    }

    @Test("Set radio params with invalid spreading factor rejects")
    func setRadioParamsInvalidSF() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let params = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 15, // Too high (max 12)
            codingRate: 5
        )
        let response = try await mock.processCommand(params)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.error.rawValue)
    }

    @Test("Set TX power with valid range")
    func setTxPowerValid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetRadioTxPower(15))
        #expect(response![0] == ResponseCode.ok.rawValue)
        #expect(await mock.currentTxPower == 15)
    }

    @Test("Set TX power with invalid range rejects")
    func setTxPowerInvalid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetRadioTxPower(25))
        #expect(response![0] == ResponseCode.error.rawValue)
    }

    // MARK: - Advert Name Tests

    @Test("Set advert name updates node name")
    func setAdvertName() async throws {
        let mock = MockBLEPeripheral(nodeName: "OldName")
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetAdvertName("NewName"))
        #expect(response![0] == ResponseCode.ok.rawValue)
        #expect(await mock.currentNodeName == "NewName")
    }

    // MARK: - Lat/Lon Tests

    @Test("Set advert lat/lon with valid coordinates")
    func setAdvertLatLonValid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(
            FrameCodec.encodeSetAdvertLatLon(latitude: 37_774_900, longitude: -122_419_400)
        )
        #expect(response![0] == ResponseCode.ok.rawValue)
    }

    @Test("Set advert lat/lon with invalid coordinates rejects")
    func setAdvertLatLonInvalid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(
            FrameCodec.encodeSetAdvertLatLon(latitude: 100_000_000, longitude: 0) // Invalid latitude
        )
        #expect(response![0] == ResponseCode.error.rawValue)
    }

    // MARK: - Channel Tests

    @Test("Get channel 0 returns public channel")
    func getPublicChannel() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetChannel(index: 0))
        #expect(response![0] == ResponseCode.channelInfo.rawValue)

        let channel = try FrameCodec.decodeChannelInfo(from: response!)
        #expect(channel.index == 0)
        #expect(channel.name == "Public")
    }

    @Test("Get non-existent channel returns error")
    func getNonExistentChannel() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetChannel(index: 7))
        #expect(response![0] == ResponseCode.error.rawValue)
        #expect(response![1] == ProtocolError.notFound.rawValue)
    }

    @Test("Set channel creates new channel")
    func setChannel() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let secret = Data(repeating: 0xAB, count: 16)
        let response = try await mock.processCommand(
            FrameCodec.encodeSetChannel(index: 1, name: "Private", secret: secret)
        )
        #expect(response![0] == ResponseCode.ok.rawValue)
        #expect(await mock.channelCount == 2) // Public + new channel

        // Verify we can get it back
        let getResponse = try await mock.processCommand(FrameCodec.encodeGetChannel(index: 1))
        let channel = try FrameCodec.decodeChannelInfo(from: getResponse!)
        #expect(channel.name == "Private")
    }

    @Test("Set channel with invalid index rejects")
    func setChannelInvalidIndex() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let secret = Data(repeating: 0xAB, count: 16)
        let response = try await mock.processCommand(
            FrameCodec.encodeSetChannel(index: 10, name: "Bad", secret: secret)
        )
        #expect(response![0] == ResponseCode.error.rawValue)
    }

    // MARK: - Battery and Storage Tests

    @Test("Get battery and storage returns values")
    func getBatteryAndStorage() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetBatteryAndStorage())
        #expect(response![0] == ResponseCode.batteryAndStorage.rawValue)

        let result = try FrameCodec.decodeBatteryAndStorage(from: response!)
        #expect(result.batteryMillivolts == 4200)
        #expect(result.storageTotalKB == 1024)
    }

    // MARK: - Device Time Tests

    @Test("Get device time returns current time")
    func getDeviceTime() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let beforeTime = UInt32(Date().timeIntervalSince1970)
        let response = try await mock.processCommand(FrameCodec.encodeGetDeviceTime())
        let afterTime = UInt32(Date().timeIntervalSince1970)

        let time = try FrameCodec.decodeCurrentTime(from: response!)
        #expect(time >= beforeTime)
        #expect(time <= afterTime + 1)
    }

    @Test("Set device time succeeds")
    func setDeviceTime() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(
            FrameCodec.encodeSetDeviceTime(UInt32(Date().timeIntervalSince1970))
        )
        #expect(response![0] == ResponseCode.ok.rawValue)
    }

    // MARK: - Device PIN Tests

    @Test("Set device PIN with valid PIN")
    func setDevicePinValid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetDevicePin(654321))
        #expect(response![0] == ResponseCode.ok.rawValue)
    }

    @Test("Set device PIN to 0 disables PIN")
    func setDevicePinDisable() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetDevicePin(0))
        #expect(response![0] == ResponseCode.ok.rawValue)
    }

    @Test("Set device PIN with invalid PIN rejects")
    func setDevicePinInvalid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSetDevicePin(12345)) // Too short
        #expect(response![0] == ResponseCode.error.rawValue)
    }

    // MARK: - Reboot Tests

    @Test("Reboot with correct confirmation disconnects")
    func rebootValid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeReboot())
        #expect(response![0] == ResponseCode.ok.rawValue)
        #expect(await mock.connected == false)
    }

    @Test("Reboot with wrong confirmation rejects")
    func rebootInvalid() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        var badCommand = Data([CommandCode.reboot.rawValue])
        badCommand.append("wrong!".data(using: .utf8)!)

        let response = try await mock.processCommand(badCommand)
        #expect(response![0] == ResponseCode.error.rawValue)
        #expect(await mock.connected == true)
    }

    // MARK: - Stats Tests

    @Test("Get core stats returns values")
    func getCoreStats() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetStats(type: .core))
        let stats = try FrameCodec.decodeCoreStats(from: response!)
        #expect(stats.batteryMillivolts == 4200)
        #expect(stats.uptimeSeconds == 3600)
    }

    @Test("Get radio stats returns values")
    func getRadioStats() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetStats(type: .radio))
        let stats = try FrameCodec.decodeRadioStats(from: response!)
        #expect(stats.noiseFloor == -120)
        #expect(stats.lastRSSI == -60)
    }

    @Test("Get packet stats returns values")
    func getPacketStats() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetStats(type: .packets))
        let stats = try FrameCodec.decodePacketStats(from: response!)
        #expect(stats.packetsReceived == 50)
        #expect(stats.packetsSent == 30)
    }

    // MARK: - Tuning Params Tests

    @Test("Get tuning params returns values")
    func getTuningParams() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeGetTuningParams())
        let params = try FrameCodec.decodeTuningParams(from: response!)
        #expect(params.rxDelayBase == 0.0)
        #expect(params.airtimeFactor == 1.0)
    }

    @Test("Set tuning params updates values")
    func setTuningParams() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let setResponse = try await mock.processCommand(
            FrameCodec.encodeSetTuningParams(rxDelayBase: 0.5, airtimeFactor: 1.5)
        )
        #expect(setResponse![0] == ResponseCode.ok.rawValue)

        let getResponse = try await mock.processCommand(FrameCodec.encodeGetTuningParams())
        let params = try FrameCodec.decodeTuningParams(from: getResponse!)
        #expect(params.rxDelayBase == 0.5)
        #expect(params.airtimeFactor == 1.5)
    }

    // MARK: - Contact Tests

    @Test("Add contact and retrieve by key")
    func addAndGetContact() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: 0,
            outPathLength: -1,
            outPath: Data(repeating: 0, count: 64),
            name: "TestContact",
            lastAdvertTimestamp: 12345,
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )

        await mock.addContact(contact)
        #expect(await mock.contactCount == 1)

        let getResponse = try await mock.processCommand(FrameCodec.encodeGetContactByKey(publicKey: publicKey))
        #expect(getResponse![0] == ResponseCode.contact.rawValue)

        let retrieved = try FrameCodec.decodeContact(from: getResponse!)
        #expect(retrieved.name == "TestContact")
        #expect(retrieved.publicKey == publicKey)
    }

    @Test("Get non-existent contact returns error")
    func getNonExistentContact() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let publicKey = Data(repeating: 0xAB, count: 32)
        let response = try await mock.processCommand(FrameCodec.encodeGetContactByKey(publicKey: publicKey))
        #expect(response![0] == ResponseCode.error.rawValue)
        #expect(response![1] == ProtocolError.notFound.rawValue)
    }

    @Test("Remove contact deletes it")
    func removeContact() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let publicKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = ContactFrame(
            publicKey: publicKey,
            type: .chat,
            flags: 0,
            outPathLength: -1,
            outPath: Data(repeating: 0, count: 64),
            name: "ToDelete",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )

        await mock.addContact(contact)
        #expect(await mock.contactCount == 1)

        let removeResponse = try await mock.processCommand(FrameCodec.encodeRemoveContact(publicKey: publicKey))
        #expect(removeResponse![0] == ResponseCode.ok.rawValue)
        #expect(await mock.contactCount == 0)
    }

    // MARK: - Message Queue Tests

    @Test("Sync next message returns queued message")
    func syncNextMessage() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        // Add a contact first
        let senderKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = ContactFrame(
            publicKey: senderKey,
            type: .chat,
            flags: 0,
            outPathLength: -1,
            outPath: Data(repeating: 0, count: 64),
            name: "Sender",
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        await mock.addContact(contact)

        // Simulate incoming message
        await mock.simulateMessageReceived(from: senderKey.prefix(6), text: "Hello!")

        // Sync message
        let response = try await mock.processCommand(FrameCodec.encodeSyncNextMessage())
        #expect(response![0] == ResponseCode.contactMessageReceivedV3.rawValue)

        let message = try FrameCodec.decodeMessageV3(from: response!)
        #expect(message.text == "Hello!")
    }

    @Test("Sync next message when empty returns no more messages")
    func syncNextMessageEmpty() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSyncNextMessage())
        #expect(response![0] == ResponseCode.noMoreMessages.rawValue)
    }

    // MARK: - Send Self Advert Tests

    @Test("Send self advert succeeds")
    func sendSelfAdvert() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(FrameCodec.encodeSendSelfAdvert(flood: true))
        #expect(response![0] == ResponseCode.ok.rawValue)
    }

    // MARK: - Unknown Command Tests

    @Test("Unknown command returns unsupported error")
    func unknownCommand() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        let response = try await mock.processCommand(Data([0xFF])) // Invalid command
        #expect(response![0] == ResponseCode.error.rawValue)
        #expect(response![1] == ProtocolError.unsupportedCommand.rawValue)
    }
}
