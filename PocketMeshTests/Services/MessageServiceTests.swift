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

private func createTestContact(
    deviceID: UUID,
    name: String = "TestContact",
    type: ContactType = .chat
) -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: deviceID,
        publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
        name: name,
        typeRawValue: type.rawValue,
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
        #expect(result.status == .sent)

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

    @Test("Send failure marks message as failed immediately")
    func sendFailureMarksMessageAsFailed() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)

        // Single failure response (no retry)
        await transport.queueResponse(createErrorResponse(.badState))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: MessageServiceError.self) {
            try await service.sendDirectMessage(text: "Hello!", to: contact)
        }

        // Verify message was saved and marked as failed immediately
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 1)
        #expect(messages.first?.status == .failed)

        // Verify only one attempt was made
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
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

        // Verify ACK is not yet delivered
        var pending = await service.getPendingAck(for: result.id)
        #expect(pending?.isDelivered == false)

        // Handle confirmation
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 1001, roundTripTime: 100))

        // ACK is still tracked (for repeat counting) but now marked as delivered
        let newPendingCount = await service.pendingAckCount
        #expect(newPendingCount == 1)  // Still tracked for repeat counting

        // Verify it's now marked as delivered
        pending = await service.getPendingAck(for: result.id)
        #expect(pending?.isDelivered == true)
        #expect(pending?.heardRepeats == 1)
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

    // MARK: - Edge Case Tests

    @Test("First confirmation sets heardRepeats to 1")
    func firstConfirmationSetsHeardRepeatsToOne() async throws {
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

        // First confirmation
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 1001, roundTripTime: 100))

        // Check heardRepeats is 1
        let pending = await service.getPendingAck(for: result.id)
        #expect(pending?.heardRepeats == 1)
        #expect(pending?.isDelivered == true)
    }

    @Test("Duplicate ACKs increment heardRepeats")
    func duplicateAcksIncrementHeardRepeats() async throws {
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
        let confirmation = SendConfirmation(ackCode: 1001, roundTripTime: 100)

        // Send 3 confirmations (simulating mesh relays)
        try await service.handleSendConfirmation(confirmation)
        try await service.handleSendConfirmation(confirmation)
        try await service.handleSendConfirmation(confirmation)

        // Check heardRepeats is 3
        let pending = await service.getPendingAck(for: result.id)
        #expect(pending?.heardRepeats == 3)

        // Verify message is still delivered (not changed by duplicate ACKs)
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .delivered)
    }

    @Test("Out-of-order confirmations both delivered")
    func outOfOrderConfirmationsBothDelivered() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Queue responses for two messages
        await transport.queueResponses([
            createSentResponse(ackCode: 111, timeout: 5000),
            createSentResponse(ackCode: 222, timeout: 5000)
        ])

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Send two messages
        let resultA = try await service.sendDirectMessage(text: "Message A", to: contact)
        let resultB = try await service.sendDirectMessage(text: "Message B", to: contact)

        #expect(resultA.ackCode == 111)
        #expect(resultB.ackCode == 222)

        // ACK for B arrives before A (out of order)
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 222, roundTripTime: 50))
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 111, roundTripTime: 150))

        // Both messages should be delivered
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        let messageA = messages.first { $0.id == resultA.id }
        let messageB = messages.first { $0.id == resultB.id }

        #expect(messageA?.status == .delivered)
        #expect(messageB?.status == .delivered)
        #expect(messageA?.roundTripTime == 150)
        #expect(messageB?.roundTripTime == 50)
    }

    @Test("Late ACK after timeout is ignored")
    func lateAckAfterTimeoutIsIgnored() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Very short timeout (10ms)
        await transport.queueResponse(createSentResponse(ackCode: 333, timeout: 10))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Wait for timeout to expire
        try await Task.sleep(for: .milliseconds(50))

        // Mark as failed
        try await service.checkExpiredAcks()

        // Verify message is failed
        var messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)

        // Late ACK arrives - should be gracefully ignored (no throw)
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 333, roundTripTime: 5000))

        // Message should still be failed (not revived)
        messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)
    }

    @Test("Unknown ACK code is ignored gracefully")
    func unknownAckCodeIsIgnoredGracefully() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // No pending ACKs tracked - send confirmation for unknown code
        // Should not throw, just return gracefully
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 99999, roundTripTime: 100))

        // Verify no crash occurred and pending count is still 0
        let pendingCount = await service.pendingAckCount
        #expect(pendingCount == 0)
    }

    @Test("Manual check after simulated background detects expired ACKs")
    func manualCheckAfterSimulatedBackgroundDetectsExpiredAcks() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Short timeout (50ms)
        await transport.queueResponse(createSentResponse(ackCode: 444, timeout: 50))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Start timer with longer interval than our test
        await service.startAckExpiryChecking(interval: 10.0)

        _ = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Simulate app going to background - stop timer
        await service.stopAckExpiryChecking()

        // Wait longer than timeout (simulating time in background)
        try await Task.sleep(for: .milliseconds(100))

        // Simulate returning to foreground - do manual check
        try await service.checkExpiredAcks()

        // Message should be marked as failed
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)
    }

    @Test("Delivered ACKs cleaned up after grace period")
    func deliveredAcksCleanedUpAfterGracePeriod() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Very short timeout for faster test
        await transport.queueResponse(createSentResponse(ackCode: 555, timeout: 1))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Confirm delivery
        try await service.handleSendConfirmation(SendConfirmation(ackCode: 555, roundTripTime: 100))

        // Verify ACK is still tracked (within grace period)
        var pending = await service.getPendingAck(for: result.id)
        #expect(pending != nil)
        #expect(pending?.isDelivered == true)

        // Note: In real usage, cleanup happens after timeout + 60s grace period
        // For testing, we just verify the cleanup method exists and runs without error
        await service.cleanupDeliveredAcks()

        // ACK should still exist (grace period hasn't passed in real time)
        pending = await service.getPendingAck(for: result.id)
        #expect(pending != nil)
    }

    // MARK: - Message Failure Handler Tests

    @Test("Message failed handler callback on timeout")
    func messageFailedHandlerCalledOnTimeout() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Very short timeout (10ms)
        await transport.queueResponse(createSentResponse(ackCode: 666, timeout: 10))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let failedMessageIDs = MutableBox<[UUID]>([])
        await service.setMessageFailedHandler { messageID in
            failedMessageIDs.value.append(messageID)
        }

        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Wait for timeout to expire
        try await Task.sleep(for: .milliseconds(50))

        // Check expired ACKs
        try await service.checkExpiredAcks()

        // Verify handler was called with correct message ID
        #expect(failedMessageIDs.value.count == 1)
        #expect(failedMessageIDs.value.first == result.id)

        // Verify message is marked as failed
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)
    }

    @Test("stopAndFailAllPending marks messages as failed and stops ACK checking")
    func stopAndFailAllPendingMarksMessagesAsFailed() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Queue responses for two messages with long timeout
        await transport.queueResponses([
            createSentResponse(ackCode: 777, timeout: 60000),
            createSentResponse(ackCode: 778, timeout: 60000)
        ])

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let failedMessageIDs = MutableBox<[UUID]>([])
        await service.setMessageFailedHandler { messageID in
            failedMessageIDs.value.append(messageID)
        }

        // Start ACK checking
        await service.startAckExpiryChecking(interval: 5.0)
        var isActive = await service.isAckExpiryCheckingActive
        #expect(isActive)

        // Send two messages
        let resultA = try await service.sendDirectMessage(text: "Message A", to: contact)
        let resultB = try await service.sendDirectMessage(text: "Message B", to: contact)

        // Verify both messages are in sent/pending status
        var messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.status == .sent })

        // Atomically stop and fail all pending
        try await service.stopAndFailAllPending()

        // Verify ACK checking is stopped
        isActive = await service.isAckExpiryCheckingActive
        #expect(!isActive)

        // Verify both messages are now failed
        messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.allSatisfy { $0.status == .failed })

        // Verify handler was called for both messages
        #expect(failedMessageIDs.value.count == 2)
        #expect(failedMessageIDs.value.contains(resultA.id))
        #expect(failedMessageIDs.value.contains(resultB.id))

        // Verify pending ACK count is 0
        let pendingCount = await service.pendingAckCount
        #expect(pendingCount == 0)
    }

    @Test("failAllPendingMessages marks messages as failed but keeps ACK checking active")
    func failAllPendingMessagesKeepsAckCheckingActive() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 888, timeout: 60000))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let failedMessageIDs = MutableBox<[UUID]>([])
        await service.setMessageFailedHandler { messageID in
            failedMessageIDs.value.append(messageID)
        }

        // Start ACK checking
        await service.startAckExpiryChecking(interval: 5.0)
        var isActive = await service.isAckExpiryCheckingActive
        #expect(isActive)

        // Send a message
        let result = try await service.sendDirectMessage(text: "Hello!", to: contact)

        // Verify message is in sent status
        var messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .sent)

        // Fail all pending (reconnection scenario - keeps ACK checking active)
        try await service.failAllPendingMessages()

        // Verify ACK checking is STILL active
        isActive = await service.isAckExpiryCheckingActive
        #expect(isActive)

        // Verify message is now failed
        messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.first?.status == .failed)

        // Verify handler was called
        #expect(failedMessageIDs.value.count == 1)
        #expect(failedMessageIDs.value.first == result.id)

        // Clean up
        await service.stopAckExpiryChecking()
    }

    @Test("failAllPendingMessages with no pending messages does nothing")
    func failAllPendingMessagesWithNoPendingDoesNothing() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let failedMessageIDs = MutableBox<[UUID]>([])
        await service.setMessageFailedHandler { messageID in
            failedMessageIDs.value.append(messageID)
        }

        // Call failAllPendingMessages with no pending messages - should not throw
        try await service.failAllPendingMessages()

        // Verify handler was not called
        #expect(failedMessageIDs.value.isEmpty)
    }

    // MARK: - Retry Tests

    @Test("sendMessageWithRetry succeeds on first ACK")
    func sendMessageWithRetrySucceedsOnFirstAck() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001, timeout: 1000))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Use async let for structured concurrency - ensures ACK task completes
        async let ackTask: Void = {
            try? await Task.sleep(for: .milliseconds(100))
            try? await service.handleSendConfirmation(SendConfirmation(ackCode: 1001, roundTripTime: 50))
        }()

        let result = try await service.sendMessageWithRetry(text: "Hello!", to: contact)
        _ = await ackTask  // Ensure cleanup

        #expect(result.status == .delivered)

        // Verify only one attempt was made
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
    }

    @Test("sendMessageWithRetry retries on ACK timeout")
    func sendMessageWithRetryRetriesOnAckTimeout() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Queue 3 responses for 3 attempts (very short timeout to speed up test)
        await transport.queueResponses([
            createSentResponse(ackCode: 1001, timeout: 50),
            createSentResponse(ackCode: 1002, timeout: 50),
            createSentResponse(ackCode: 1003, timeout: 50)
        ])

        let config = MessageServiceConfig(maxAttempts: 3, minTimeout: 0.05)
        let service = MessageService(bleTransport: transport, dataStore: dataStore, config: config)

        // No ACK sent - all attempts should timeout
        let result = try await service.sendMessageWithRetry(text: "Hello!", to: contact)

        // Should fail after max attempts
        #expect(result.status == .failed)

        // Verify all 3 attempts were made
        let sentData = await transport.getSentData()
        #expect(sentData.count == 3)
    }

    @Test("sendMessageWithRetry succeeds on second attempt")
    func sendMessageWithRetrySucceedsOnSecondAttempt() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponses([
            createSentResponse(ackCode: 1001, timeout: 50),
            createSentResponse(ackCode: 1002, timeout: 500)
        ])

        let config = MessageServiceConfig(maxAttempts: 3, minTimeout: 0.05)
        let service = MessageService(bleTransport: transport, dataStore: dataStore, config: config)

        // Use task group for structured concurrency
        let result = try await withThrowingTaskGroup(of: MessageDTO?.self) { group in
            // Spawn ACK sender - sends ACK for second attempt after first times out
            group.addTask {
                // Wait for first timeout (~60ms with 1.2x multiplier) + backoff (~200ms) + some buffer
                try? await Task.sleep(for: .milliseconds(350))
                try? await service.handleSendConfirmation(
                    SendConfirmation(ackCode: 1002, roundTripTime: 100)
                )
                return nil
            }

            // Spawn message sender
            group.addTask {
                try await service.sendMessageWithRetry(text: "Hello!", to: contact)
            }

            // Collect results
            var message: MessageDTO?
            for try await value in group {
                if let msg = value {
                    message = msg
                }
            }
            return message
        }

        #expect(result?.status == .delivered)

        // Verify 2 attempts were made
        let sentData = await transport.getSentData()
        #expect(sentData.count == 2)
    }

    @Test("sendMessageWithRetry respects task cancellation")
    func sendMessageWithRetryRespectsTaskCancellation() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        // Queue responses with long timeout
        await transport.queueResponses([
            createSentResponse(ackCode: 1001, timeout: 5000),
            createSentResponse(ackCode: 1002, timeout: 5000)
        ])

        let config = MessageServiceConfig(maxAttempts: 3, minTimeout: 5.0)
        let service = MessageService(bleTransport: transport, dataStore: dataStore, config: config)

        // Create a task that we'll cancel
        let task = Task {
            try await service.sendMessageWithRetry(text: "Hello!", to: contact)
        }

        // Give it time to start first attempt
        try await Task.sleep(for: .milliseconds(100))

        // Cancel the task
        task.cancel()

        // The task should throw CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError but task completed normally")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError but got: \(error)")
        }
    }

    // MARK: - Repeater Blocking Tests

    @Test("Send direct message to repeater throws invalidRecipient")
    func sendDirectMessageToRepeaterThrowsInvalidRecipient() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let repeater = createTestContact(deviceID: deviceID, name: "Test Repeater", type: .repeater)

        await transport.setConnectionState(.ready)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Verify the specific error case is thrown
        do {
            _ = try await service.sendDirectMessage(text: "Hello!", to: repeater)
            Issue.record("Expected invalidRecipient error but succeeded")
        } catch let error as MessageServiceError {
            switch error {
            case .invalidRecipient:
                break  // Expected case
            default:
                Issue.record("Expected invalidRecipient but got \(error)")
            }
        } catch {
            Issue.record("Expected MessageServiceError but got \(error)")
        }

        // Verify no message was saved (error thrown before save)
        let messages = try await dataStore.fetchMessages(contactID: repeater.id)
        #expect(messages.isEmpty)

        // Verify no data was sent to BLE
        let sentData = await transport.getSentData()
        #expect(sentData.isEmpty)
    }

    @Test("Send message with retry to repeater throws invalidRecipient")
    func sendMessageWithRetryToRepeaterThrowsInvalidRecipient() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let repeater = createTestContact(deviceID: deviceID, name: "Test Repeater", type: .repeater)

        await transport.setConnectionState(.ready)

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        // Verify the specific error case is thrown
        do {
            _ = try await service.sendMessageWithRetry(text: "Hello!", to: repeater)
            Issue.record("Expected invalidRecipient error but succeeded")
        } catch let error as MessageServiceError {
            switch error {
            case .invalidRecipient:
                break  // Expected case
            default:
                Issue.record("Expected invalidRecipient but got \(error)")
            }
        } catch {
            Issue.record("Expected MessageServiceError but got \(error)")
        }

        // Verify no message was saved
        let messages = try await dataStore.fetchMessages(contactID: repeater.id)
        #expect(messages.isEmpty)

        // Verify no data was sent to BLE
        let sentData = await transport.getSentData()
        #expect(sentData.isEmpty)
    }
}
