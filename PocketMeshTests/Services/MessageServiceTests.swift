import Testing
import Foundation
@testable import PocketMeshKit

/// A test BLE transport that allows full control over responses
public actor TestBLETransport: BLETransport {
    private var _connectionState: BLEConnectionState = .disconnected
    private var _connectedDeviceID: UUID?
    private var responseHandler: (@Sendable (Data) -> Void)?

    /// Responses to return for send calls (FIFO queue)
    private var queuedResponses: [Data?] = []

    /// Whether to fail the next send
    private var shouldFailNextSend = false
    private var failError: Error = BLEError.writeError("Test failure")

    /// Track all sent data for verification
    private var sentData: [Data] = []

    public var connectionState: BLEConnectionState {
        _connectionState
    }

    public var connectedDeviceID: UUID? {
        _connectedDeviceID
    }

    public init() {}

    public func startScanning() async throws {
        _connectionState = .scanning
    }

    public func stopScanning() async {
        if _connectionState == .scanning {
            _connectionState = .disconnected
        }
    }

    public func connect(to deviceID: UUID) async throws {
        _connectedDeviceID = deviceID
        _connectionState = .connected
    }

    public func disconnect() async {
        _connectedDeviceID = nil
        _connectionState = .disconnected
    }

    public func send(_ data: Data) async throws -> Data? {
        sentData.append(data)

        if shouldFailNextSend {
            shouldFailNextSend = false
            throw failError
        }

        if !queuedResponses.isEmpty {
            return queuedResponses.removeFirst()
        }

        return nil
    }

    public func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) async {
        responseHandler = handler
    }

    // MARK: - Test Helpers

    public func setConnectionState(_ state: BLEConnectionState) {
        _connectionState = state
    }

    public func queueResponse(_ response: Data?) {
        queuedResponses.append(response)
    }

    public func queueResponses(_ responses: [Data?]) {
        queuedResponses.append(contentsOf: responses)
    }

    public func setNextSendToFail(with error: Error = BLEError.writeError("Test failure")) {
        shouldFailNextSend = true
        failError = error
    }

    public func getSentData() -> [Data] {
        sentData
    }

    public func clearSentData() {
        sentData.removeAll()
    }

    public func simulatePush(_ data: Data) {
        responseHandler?(data)
    }
}

// MARK: - Test Helpers

private func createTestContact(deviceID: UUID, name: String = "TestContact") -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: deviceID,
        publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
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

private func createSentResponse(ackCode: UInt32, isFlood: Bool = false, timeout: UInt32 = 5000) -> Data {
    var data = Data([ResponseCode.sent.rawValue])
    data.append(isFlood ? 1 : 0)
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })
    return data
}

private func createErrorResponse(_ error: ProtocolError) -> Data {
    Data([ResponseCode.error.rawValue, error.rawValue])
}

private func createSendConfirmation(ackCode: UInt32, roundTrip: UInt32 = 500) -> Data {
    var data = Data([PushCode.sendConfirmed.rawValue])
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: roundTrip.littleEndian) { Array($0) })
    return data
}

// MARK: - Message Service Tests

@Suite("MessageService Tests")
struct MessageServiceTests {

    @Test("Send direct message successfully")
    func sendDirectMessageSuccessfully() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(
            text: "Hello!",
            to: contact
        )

        #expect(result.ackCode == 1001)
        #expect(result.attemptCount == 1)
        #expect(!result.isFlood)

        // Verify message was saved
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Hello!")
        #expect(messages.first?.status == .sent)
    }

    @Test("Send message fails when not connected")
    func sendMessageFailsWhenNotConnected() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)

        // Transport is disconnected by default
        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: MessageServiceError.self) {
            try await service.sendDirectMessage(text: "Hello!", to: contact)
        }
    }

    @Test("Message too long is rejected")
    func messageTooLongIsRejected() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        await transport.setConnectionState(.ready)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Create a message longer than 160 chars
        let longMessage = String(repeating: "A", count: 200)

        await #expect(throws: MessageServiceError.self) {
            try await service.sendDirectMessage(text: longMessage, to: contact)
        }
    }

    @Test("Retry logic with exponential backoff")
    func retryLogicWithExponentialBackoff() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        // Queue: fail, fail, succeed
        await transport.queueResponses([
            createErrorResponse(.badState),
            createErrorResponse(.badState),
            createSentResponse(ackCode: 1001)
        ])

        let config = MessageServiceConfig(
            maxRetries: 3,
            initialRetryDelay: 0.01,
            maxRetryDelay: 0.1,
            retryBackoffMultiplier: 2.0
        )
        let service = MessageService(bleTransport: transport, dataStore: dataStore, config: config)

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        #expect(result.attemptCount == 3)
        #expect(result.ackCode == 1001)

        // Verify 3 attempts were made
        let sentData = await transport.getSentData()
        #expect(sentData.count == 3)
    }

    @Test("Max retries exceeded marks message as failed")
    func maxRetriesExceededMarksMessageAsFailed() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        // All attempts fail
        await transport.queueResponses([
            createErrorResponse(.badState),
            createErrorResponse(.badState),
            createErrorResponse(.badState)
        ])

        let config = MessageServiceConfig(maxRetries: 3, initialRetryDelay: 0.01)
        let service = MessageService(bleTransport: transport, dataStore: dataStore, config: config)

        await #expect(throws: MessageServiceError.self) {
            try await service.sendDirectMessage(text: "Hello!", to: contact)
        }

        // Verify message was saved and marked as failed
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 1)
        #expect(messages.first?.status == .failed)
    }

    @Test("ACK confirmation updates message to delivered")
    func ackConfirmationUpdatesMessageToDelivered() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001, timeout: 5000))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)
        #expect(result.ackCode == 1001)

        // Verify message is in 'sent' status
        var messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .sent)

        // Simulate ACK confirmation
        let confirmation = SendConfirmation(ackCode: 1001, roundTripTime: 250)
        try await service.handleSendConfirmation(confirmation)

        // Verify message is now delivered
        messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .delivered)
        #expect(messages.first?.roundTripTime == 250)
    }

    @Test("Pending ACK tracking")
    func pendingAckTracking() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001, timeout: 5000))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Check pending ACK count
        let pendingCount = await service.pendingAckCount
        #expect(pendingCount == 1)

        // Handle confirmation
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 1001, roundTripTime: 100))

        // Check pending ACK count is now 0
        let newPendingCount = await service.pendingAckCount
        #expect(newPendingCount == 0)
    }

    @Test("Send channel message successfully")
    func sendChannelMessageSuccessfully() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let messageID = try await service.sendChannelMessage(
            text: "Hello channel!",
            channelIndex: 0,
            deviceID: deviceID
        )

        // Verify message was saved
        let messages = try await dataStore.fetchMessages(deviceID: deviceID, channelIndex: 0)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Hello channel!")
        #expect(messages.first?.status == .sent)
        #expect(messages.first?.id == messageID)
    }

    @Test("Invalid channel index rejected")
    func invalidChannelIndexRejected() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: MessageServiceError.self) {
            try await service.sendChannelMessage(
                text: "Hello!",
                channelIndex: 10,  // Invalid - max is 7
                deviceID: deviceID
            )
        }
    }

    @Test("ACK confirmation handler callback")
    func ackConfirmationHandlerCallback() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let callbackReceived = MutableBox(false)
        let receivedAckCode = MutableBox<UInt32>(0)
        let receivedRtt = MutableBox<UInt32>(0)

        await service.setAckConfirmationHandler { ackCode, rtt in
            callbackReceived.value = true
            receivedAckCode.value = ackCode
            receivedRtt.value = rtt
        }

        _ = try await service.sendDirectMessage(text: "Hello!", to: contact)
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 1001, roundTripTime: 333))

        #expect(callbackReceived.value)
        #expect(receivedAckCode.value == 1001)
        #expect(receivedRtt.value == 333)
    }

    @Test("Expired ACKs are cleaned up")
    func expiredAcksAreCleanedUp() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Return a very short timeout (10ms)
        await transport.queueResponse(createSentResponse(ackCode: 1001, timeout: 10))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        _ = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Wait for timeout to expire
        try await Task.sleep(for: .milliseconds(50))

        // Check expired ACKs
        try await service.checkExpiredAcks()

        // Message should be marked as failed
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)

        // Pending ACK should be removed
        let pendingCount = await service.pendingAckCount
        #expect(pendingCount == 0)
    }
}
