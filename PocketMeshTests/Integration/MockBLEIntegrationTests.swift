import Testing
import Foundation
@testable import PocketMeshKit

/// A mock BLE transport that uses MockBLEPeripheral for testing
public actor MockBLETransport: BLETransport {
    private let mockPeripheral: MockBLEPeripheral
    private var _connectionState: BLEConnectionState = .disconnected
    private var _connectedDeviceID: UUID?
    private var responseHandler: (@Sendable (Data) -> Void)?

    public var connectionState: BLEConnectionState {
        _connectionState
    }

    public var connectedDeviceID: UUID? {
        _connectedDeviceID
    }

    public init(peripheral: MockBLEPeripheral) {
        self.mockPeripheral = peripheral
    }

    public func startScanning() async throws {
        _connectionState = .scanning
    }

    public func stopScanning() async {
        if _connectionState == .scanning {
            _connectionState = .disconnected
        }
    }

    public func connect(to deviceID: UUID) async throws {
        _connectionState = .connecting
        await mockPeripheral.connect()
        _connectedDeviceID = deviceID
        _connectionState = .connected
    }

    public func disconnect() async {
        await mockPeripheral.disconnect()
        _connectedDeviceID = nil
        _connectionState = .disconnected
    }

    public func send(_ data: Data) async throws -> Data? {
        guard await mockPeripheral.connected else {
            throw BLEError.notConnected
        }
        return try await mockPeripheral.processCommand(data)
    }

    public func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) async {
        responseHandler = handler
        await mockPeripheral.setResponseHandler(handler)
    }

    /// Get the underlying mock peripheral for test configuration
    public var peripheral: MockBLEPeripheral {
        mockPeripheral
    }
}

@Suite("Mock BLE Integration Tests")
struct MockBLEIntegrationTests {

    // MARK: - Connection Tests

    @Test("Connect and query device info")
    func connectAndQueryDeviceInfo() async throws {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let state = await transport.connectionState
        #expect(state == .connected)

        // Query device info
        let query = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        let response = try await transport.send(query)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.deviceInfo.rawValue)

        let deviceInfo = try FrameCodec.decodeDeviceInfo(from: response!)
        #expect(deviceInfo.firmwareVersion == 8)
        #expect(deviceInfo.maxChannels == 8)
    }

    @Test("App start returns self info")
    func appStartReturnsSelfInfo() async throws {
        let mock = MockBLEPeripheral(nodeName: "MyNode")
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Device query first
        _ = try await transport.send(FrameCodec.encodeDeviceQuery(protocolVersion: 8))

        // App start
        let appStart = FrameCodec.encodeAppStart(appName: "PocketMesh")
        let response = try await transport.send(appStart)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.selfInfo.rawValue)

        let selfInfo = try FrameCodec.decodeSelfInfo(from: response!)
        #expect(selfInfo.nodeName == "MyNode")
        #expect(selfInfo.publicKey.count == 32)
    }

    // MARK: - Contact Sync Tests

    @Test("Get contacts returns contact list")
    func getContactsReturnsContactList() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Add some contacts to mock
        let contact1 = ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: 2,
            outPath: Data([0x01, 0x02]),
            name: "Alice",
            lastAdvertTimestamp: 1000,
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: 1000
        )
        let contact2 = ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .repeater,
            flags: 0,
            outPathLength: -1,
            outPath: Data(),
            name: "RepeaterNode",
            lastAdvertTimestamp: 2000,
            latitude: 0,
            longitude: 0,
            lastModified: 2000
        )

        await mock.addContact(contact1)
        await mock.addContact(contact2)

        // Get contacts
        let getContacts = FrameCodec.encodeGetContacts()
        let startResponse = try await transport.send(getContacts)

        #expect(startResponse != nil)
        #expect(startResponse?[0] == ResponseCode.contactsStart.rawValue)

        // Iterate through contacts
        var contacts: [ContactFrame] = []
        while true {
            let nextContact = await mock.getNextContact()
            guard let data = nextContact else { break }

            if data[0] == ResponseCode.endOfContacts.rawValue {
                break
            }

            let frame = try FrameCodec.decodeContact(from: data)
            contacts.append(frame)
        }

        #expect(contacts.count == 2)
        #expect(contacts.contains { $0.name == "Alice" })
        #expect(contacts.contains { $0.name == "RepeaterNode" })
    }

    @Test("Incremental contact sync with since filter")
    func incrementalContactSyncWithSinceFilter() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Add contacts with different timestamps
        let oldContact = ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "OldContact",
            lastAdvertTimestamp: 1000,
            latitude: 0,
            longitude: 0,
            lastModified: 1000
        )
        let newContact = ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            name: "NewContact",
            lastAdvertTimestamp: 3000,
            latitude: 0,
            longitude: 0,
            lastModified: 3000
        )

        await mock.addContact(oldContact)
        await mock.addContact(newContact)

        // Get contacts since timestamp 2000
        let getContacts = FrameCodec.encodeGetContacts(since: 2000)
        _ = try await transport.send(getContacts)

        // Collect contacts
        var contacts: [ContactFrame] = []
        while true {
            let nextContact = await mock.getNextContact()
            guard let data = nextContact else { break }

            if data[0] == ResponseCode.endOfContacts.rawValue {
                break
            }

            let frame = try FrameCodec.decodeContact(from: data)
            contacts.append(frame)
        }

        // Should only get the new contact
        #expect(contacts.count == 1)
        #expect(contacts.first?.name == "NewContact")
    }

    // MARK: - Message Tests

    @Test("Send text message to contact")
    func sendTextMessageToContact() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Add a contact
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = ContactFrame(
            publicKey: contactKey,
            type: .chat,
            flags: 0,
            outPathLength: 2,
            outPath: Data([0x01, 0x02]),
            name: "Bob",
            lastAdvertTimestamp: 1000,
            latitude: 0,
            longitude: 0,
            lastModified: 1000
        )
        await mock.addContact(contact)

        // Send message
        let sendMessage = FrameCodec.encodeSendTextMessage(
            textType: .plain,
            attempt: 1,
            timestamp: UInt32(Date().timeIntervalSince1970),
            recipientKeyPrefix: contactKey.prefix(6),
            text: "Hello Bob!"
        )
        let response = try await transport.send(sendMessage)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.sent.rawValue)

        let sentResponse = try FrameCodec.decodeSentResponse(from: response!)
        #expect(sentResponse.ackCode >= 1000)
        #expect(sentResponse.estimatedTimeout > 0)
    }

    @Test("Send message to unknown contact returns error")
    func sendMessageToUnknownContactReturnsError() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Try to send to non-existent contact
        let unknownKey = Data(repeating: 0xFF, count: 6)
        let sendMessage = FrameCodec.encodeSendTextMessage(
            textType: .plain,
            attempt: 1,
            timestamp: UInt32(Date().timeIntervalSince1970),
            recipientKeyPrefix: unknownKey,
            text: "Hello?"
        )
        let response = try await transport.send(sendMessage)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.error.rawValue)
        #expect(response?[1] == ProtocolError.notFound.rawValue)
    }

    @Test("Receive message via sync")
    func receiveMessageViaSync() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Simulate incoming message
        let senderPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        await mock.simulateMessageReceived(from: senderPrefix, text: "Hello from mesh!")

        // Sync message
        let sync = FrameCodec.encodeSyncNextMessage()
        let response = try await transport.send(sync)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.contactMessageReceivedV3.rawValue)

        let message = try FrameCodec.decodeMessageV3(from: response!)
        #expect(message.text == "Hello from mesh!")
        #expect(message.senderPublicKeyPrefix == senderPrefix)
    }

    @Test("No more messages when queue empty")
    func noMoreMessagesWhenQueueEmpty() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let sync = FrameCodec.encodeSyncNextMessage()
        let response = try await transport.send(sync)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.noMoreMessages.rawValue)
    }

    // MARK: - Channel Tests

    @Test("Get and set channel")
    func getAndSetChannel() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Get public channel (slot 0)
        let getChannel = FrameCodec.encodeGetChannel(index: 0)
        let getResponse = try await transport.send(getChannel)

        #expect(getResponse != nil)
        #expect(getResponse?[0] == ResponseCode.channelInfo.rawValue)

        let channelInfo = try FrameCodec.decodeChannelInfo(from: getResponse!)
        #expect(channelInfo.index == 0)
        #expect(channelInfo.name == "Public")

        // Set a new channel
        let newSecret = Data(repeating: 0xAB, count: 16)
        let setChannel = FrameCodec.encodeSetChannel(index: 1, name: "Private", secret: newSecret)
        let setResponse = try await transport.send(setChannel)

        #expect(setResponse != nil)
        #expect(setResponse?[0] == ResponseCode.ok.rawValue)

        // Verify channel was set
        let verifyGet = FrameCodec.encodeGetChannel(index: 1)
        let verifyResponse = try await transport.send(verifyGet)

        let verifyInfo = try FrameCodec.decodeChannelInfo(from: verifyResponse!)
        #expect(verifyInfo.name == "Private")
        #expect(verifyInfo.secret == newSecret)
    }

    // MARK: - Radio Configuration Tests

    @Test("Set radio parameters")
    func setRadioParameters() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let setParams = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 868_000,
            bandwidthKHz: 125_000,
            spreadingFactor: 12,
            codingRate: 8
        )
        let response = try await transport.send(setParams)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.ok.rawValue)

        // Verify via mock
        let currentFreq = await mock.currentFrequency
        #expect(currentFreq == 868_000)
    }

    @Test("Set TX power")
    func setTxPower() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let setTx = FrameCodec.encodeSetRadioTxPower(15)
        let response = try await transport.send(setTx)

        #expect(response != nil)
        #expect(response?[0] == ResponseCode.ok.rawValue)

        let currentTx = await mock.currentTxPower
        #expect(currentTx == 15)
    }

    @Test("Invalid radio params rejected")
    func invalidRadioParamsRejected() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Invalid spreading factor (13)
        let invalidSF = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915_000,
            bandwidthKHz: 250_000,
            spreadingFactor: 13,
            codingRate: 5
        )
        let response = try await transport.send(invalidSF)

        #expect(response?[0] == ResponseCode.error.rawValue)
        #expect(response?[1] == ProtocolError.illegalArgument.rawValue)
    }

    // MARK: - Device Status Tests

    @Test("Get battery and storage")
    func getBatteryAndStorage() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let getBattery = FrameCodec.encodeGetBatteryAndStorage()
        let response = try await transport.send(getBattery)

        #expect(response != nil)
        let batteryInfo = try FrameCodec.decodeBatteryAndStorage(from: response!)
        #expect(batteryInfo.batteryMillivolts == 4200)
        #expect(batteryInfo.storageTotalKB == 1024)
    }

    @Test("Set device name")
    func setDeviceName() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        let setName = FrameCodec.encodeSetAdvertName("NewNodeName")
        let response = try await transport.send(setName)

        #expect(response?[0] == ResponseCode.ok.rawValue)

        let nodeName = await mock.currentNodeName
        #expect(nodeName == "NewNodeName")
    }

    // MARK: - Push Notification Tests

    @Test("Receive push notification for message waiting")
    func receivePushNotificationForMessageWaiting() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Use continuation for safe concurrency
        let receivedPush = await withCheckedContinuation { continuation in
            Task {
                await transport.setResponseHandler { data in
                    continuation.resume(returning: data)
                }

                // Simulate message received (which triggers a push)
                let senderPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
                await mock.simulateMessageReceived(from: senderPrefix, text: "New message!")
            }
        }

        #expect(receivedPush[0] == PushCode.messageWaiting.rawValue)
    }

    @Test("Receive send confirmed push")
    func receiveSendConfirmedPush() async throws {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(peripheral: mock)

        try await transport.connect(to: UUID())

        // Use continuation for safe concurrency
        let receivedPush = await withCheckedContinuation { continuation in
            Task {
                await transport.setResponseHandler { data in
                    continuation.resume(returning: data)
                }

                await mock.simulateSendConfirmed(ackCode: 12345, roundTrip: 250)
            }
        }

        #expect(receivedPush[0] == PushCode.sendConfirmed.rawValue)

        let confirmation = try FrameCodec.decodeSendConfirmation(from: receivedPush)
        #expect(confirmation.ackCode == 12345)
        #expect(confirmation.roundTripTime == 250)
    }
}
