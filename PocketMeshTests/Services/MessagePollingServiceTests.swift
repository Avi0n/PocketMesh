import Testing
import Foundation
@testable import PocketMeshKit

// MARK: - Test Delegate

/// A test delegate for tracking message polling events
actor TestMessagePollingDelegate: MessagePollingDelegate {
    private var _directMessages: [(MessageDTO, ContactDTO)] = []
    private var _channelMessages: [(MessageDTO, UInt8)] = []
    private var _unknownSenders: [Data] = []
    private var _errors: [MessagePollingError] = []
    private var _sendConfirmations: [SendConfirmation] = []
    private var _statusResponses: [RemoteNodeStatus] = []
    private var _loginResults: [(LoginResult, Data)] = []

    var directMessages: [(MessageDTO, ContactDTO)] {
        _directMessages
    }

    var channelMessages: [(MessageDTO, UInt8)] {
        _channelMessages
    }

    var unknownSenders: [Data] {
        _unknownSenders
    }

    var errors: [MessagePollingError] {
        _errors
    }

    var sendConfirmations: [SendConfirmation] {
        _sendConfirmations
    }

    var statusResponses: [RemoteNodeStatus] {
        _statusResponses
    }

    var loginResults: [(LoginResult, Data)] {
        _loginResults
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveDirectMessage message: MessageDTO, from contact: ContactDTO) async {
        await appendDirectMessage(message, contact)
    }

    private func appendDirectMessage(_ message: MessageDTO, _ contact: ContactDTO) {
        _directMessages.append((message, contact))
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveChannelMessage message: MessageDTO, channelIndex: UInt8) async {
        await appendChannelMessage(message, channelIndex)
    }

    private func appendChannelMessage(_ message: MessageDTO, _ channelIndex: UInt8) {
        _channelMessages.append((message, channelIndex))
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveUnknownSender keyPrefix: Data) async {
        await appendUnknownSender(keyPrefix)
    }

    private func appendUnknownSender(_ keyPrefix: Data) {
        _unknownSenders.append(keyPrefix)
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didEncounterError error: MessagePollingError) async {
        await appendError(error)
    }

    private func appendError(_ error: MessagePollingError) {
        _errors.append(error)
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveSendConfirmation confirmation: SendConfirmation) async {
        await appendSendConfirmation(confirmation)
    }

    private func appendSendConfirmation(_ confirmation: SendConfirmation) {
        _sendConfirmations.append(confirmation)
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveStatusResponse status: RemoteNodeStatus) async {
        await appendStatusResponse(status)
    }

    private func appendStatusResponse(_ status: RemoteNodeStatus) {
        _statusResponses.append(status)
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveLoginResult result: LoginResult, fromPublicKeyPrefix: Data) async {
        await appendLoginResult(result, fromPublicKeyPrefix)
    }

    private func appendLoginResult(_ result: LoginResult, _ keyPrefix: Data) {
        _loginResults.append((result, keyPrefix))
    }

    nonisolated func messagePollingService(_ service: MessagePollingService, didReceiveRoomMessage frame: MessageFrame, fromRoom contact: ContactDTO) async {
        // Room messages are handled by RoomServerService, not tracked here
    }

    func reset() {
        _directMessages.removeAll()
        _channelMessages.removeAll()
        _unknownSenders.removeAll()
        _errors.removeAll()
        _sendConfirmations.removeAll()
        _statusResponses.removeAll()
        _loginResults.removeAll()
    }
}

// MARK: - Test Helpers

private func createDirectMessageV3Frame(
    senderPrefix: Data,
    text: String,
    timestamp: UInt32 = 0,
    snr: Int8 = 40,
    pathLength: UInt8 = 2
) -> Data {
    let ts = timestamp > 0 ? timestamp : UInt32(Date().timeIntervalSince1970)

    var frame = Data([ResponseCode.contactMessageReceivedV3.rawValue])
    frame.append(UInt8(bitPattern: snr))
    frame.append(0)  // reserved
    frame.append(0)  // reserved
    frame.append(senderPrefix.prefix(6))
    frame.append(pathLength)
    frame.append(TextType.plain.rawValue)
    frame.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
    frame.append(text.data(using: .utf8) ?? Data())

    return frame
}

private func createChannelMessageV3Frame(
    channelIndex: UInt8,
    text: String,
    timestamp: UInt32 = 0,
    snr: Int8 = 40,
    pathLength: UInt8 = 2
) -> Data {
    let ts = timestamp > 0 ? timestamp : UInt32(Date().timeIntervalSince1970)

    var frame = Data([ResponseCode.channelMessageReceivedV3.rawValue])
    frame.append(UInt8(bitPattern: snr))
    frame.append(0)  // reserved
    frame.append(0)  // reserved
    frame.append(channelIndex)
    frame.append(pathLength)
    frame.append(TextType.plain.rawValue)
    frame.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
    frame.append(text.data(using: .utf8) ?? Data())

    return frame
}

private func createNoMoreMessagesFrame() -> Data {
    Data([ResponseCode.noMoreMessages.rawValue])
}

private func createTestContact(deviceID: UUID, publicKey: Data, name: String = "TestContact") -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: deviceID,
        publicKey: publicKey,
        name: name,
        typeRawValue: ContactType.chat.rawValue,
        flags: 0,
        outPathLength: 2,
        outPath: Data([0x01, 0x02]),
        lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
        latitude: 0,
        longitude: 0,
        lastModified: UInt32(Date().timeIntervalSince1970)
    )
    return ContactDTO(from: contact)
}

// MARK: - Message Polling Service Tests

@Suite("MessagePollingService Tests")
struct MessagePollingServiceTests {

    @Test("Parse direct message frame")
    func parseDirectMessageFrame() throws {
        let senderPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let frame = createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Hello world!")

        let message = try MessagePollingService.parseDirectMessage(from: frame)

        #expect(message.senderKeyPrefix == senderPrefix)
        #expect(message.text == "Hello world!")
        #expect(message.pathLength == 2)
        #expect(message.snr == 40)
        #expect(!message.isChannelMessage)
        #expect(message.channelIndex == nil)
    }

    @Test("Parse channel message frame")
    func parseChannelMessageFrame() throws {
        let frame = createChannelMessageV3Frame(channelIndex: 1, text: "Channel broadcast!")

        let message = try MessagePollingService.parseChannelMessage(from: frame)

        #expect(message.text == "Channel broadcast!")
        #expect(message.pathLength == 2)
        #expect(message.snr == 40)
        #expect(message.isChannelMessage)
        #expect(message.channelIndex == 1)
    }

    @Test("Sync message queue receives direct message")
    func syncMessageQueueReceivesDirectMessage() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        // Queue: message, then no more
        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Hello from mesh!"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        #expect(await delegate.directMessages.count == 1)
        #expect(await delegate.directMessages.first?.0.text == "Hello from mesh!")
        #expect(await delegate.directMessages.first?.1.id == contact.id)

        // Verify message was saved
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Hello from mesh!")
        #expect(messages.first?.direction == .incoming)
    }

    @Test("Sync message queue receives channel message")
    func syncMessageQueueReceivesChannelMessage() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Queue: channel message, then no more
        await transport.queueResponses([
            createChannelMessageV3Frame(channelIndex: 0, text: "Channel message!"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        #expect(await delegate.channelMessages.count == 1)
        #expect(await delegate.channelMessages.first?.0.text == "Channel message!")
        #expect(await delegate.channelMessages.first?.1 == 0)

        // Verify message was saved
        let messages = try await dataStore.fetchMessages(deviceID: deviceID, channelIndex: 0)
        #expect(messages.count == 1)
    }

    @Test("Unknown sender notifies delegate")
    func unknownSenderNotifiesDelegate() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Queue: message from unknown sender, then no more
        let unknownPrefix = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: unknownPrefix, text: "Hello?"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        #expect(await delegate.unknownSenders.count == 1)
        #expect(await delegate.unknownSenders.first == unknownPrefix)
        #expect(await delegate.directMessages.isEmpty)
    }

    @Test("Multiple messages synced in sequence")
    func multipleMessagesSyncedInSequence() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Message 1"),
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Message 2"),
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Message 3"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        #expect(await delegate.directMessages.count == 3)

        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 3)
    }

    @Test("Message waiting triggers sync")
    func messageWaitingTriggersSync() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "New message!"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        // Trigger message waiting
        await service.handleMessageWaiting()

        // Wait for sync to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(await delegate.directMessages.count == 1)
    }

    @Test("Sync fails when not connected")
    func syncFailsWhenNotConnected() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        // Transport is disconnected
        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(UUID())

        await service.syncMessageQueue()

        #expect(await delegate.errors.count == 1)
    }

    @Test("Sync fails without active device")
    func syncFailsWithoutActiveDevice() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        await transport.setConnectionState(.ready)

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        // Note: no active device set

        await service.syncMessageQueue()

        #expect(await delegate.errors.count == 1)
    }

    @Test("Contact unread count incremented on message")
    func contactUnreadCountIncrementedOnMessage() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Message 1"),
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Message 2"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        await service.setDelegate(TestMessagePollingDelegate())
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        // Verify unread count was incremented
        let updatedContact = try await dataStore.fetchContact(id: contact.id)
        #expect(updatedContact?.unreadCount == 2)
    }

    @Test("Syncing status is tracked")
    func syncingStatusIsTracked() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(createNoMoreMessagesFrame())

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        await service.setActiveDevice(deviceID)

        // Before sync
        var isSyncing = await service.isCurrentlySyncing
        #expect(!isSyncing)

        await service.syncMessageQueue()

        // After sync
        isSyncing = await service.isCurrentlySyncing
        #expect(!isSyncing)
    }

    @Test("Process push data for message waiting")
    func processPushDataForMessageWaiting() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Push message!"),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        // Simulate push data
        let pushData = Data([PushCode.messageWaiting.rawValue])
        try await service.processPushData(pushData)

        // Wait for sync to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(await delegate.directMessages.count == 1)
        #expect(await delegate.directMessages.first?.0.text == "Push message!")
    }

    @Test("Message SNR is correctly parsed")
    func messageSnrIsCorrectlyParsed() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contactKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let contact = createTestContact(deviceID: deviceID, publicKey: contactKey)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        // SNR of 40 = 10.0 dB (scaled by 4)
        let senderPrefix = contactKey.prefix(6)
        await transport.queueResponses([
            createDirectMessageV3Frame(senderPrefix: senderPrefix, text: "Test", snr: 40),
            createNoMoreMessagesFrame()
        ])

        let service = MessagePollingService(bleTransport: transport, dataStore: dataStore)
        let delegate = TestMessagePollingDelegate()
        await service.setDelegate(delegate)
        await service.setActiveDevice(deviceID)

        await service.syncMessageQueue()

        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.snr == 40)
        #expect(messages.first?.snrValue == 10.0)
    }
}
