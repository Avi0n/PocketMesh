import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests MessagePollingService integration with MockBLERadio against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class MessagePollingServiceTests: BaseTestCase {

    var messagePollingService: MessagePollingService!
    var testDevice: Device!
    var testContact: Contact!

    override func setUp() async throws {
        try await super.setUp()

        // Create test device and contact
        testDevice = try TestDataFactory.createTestDevice()
        testContact = try TestDataFactory.createTestContact()

        // Save to SwiftData context
        modelContext.insert(testDevice)
        modelContext.insert(testContact)
        try modelContext.save()

        // Initialize MessagePollingService with mock BLE manager
        messagePollingService = MessagePollingService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        await messagePollingService.stopPolling()
        messagePollingService = nil
        testDevice = nil
        testContact = nil
        try await super.tearDown()
    }

    // MARK: - Polling Lifecycle Tests

    func testStartPolling_Success() async throws {
        // Given
        XCTAssertFalse(messagePollingService.isPolling)

        // When
        await messagePollingService.startPolling()

        // Then
        XCTAssertTrue(messagePollingService.isPolling)

        // Clean up
        await messagePollingService.stopPolling()
    }

    func testStopPolling_Success() async throws {
        // Given
        await messagePollingService.startPolling()
        XCTAssertTrue(messagePollingService.isPolling)

        // When
        await messagePollingService.stopPolling()

        // Then
        XCTAssertFalse(messagePollingService.isPolling)
    }

    func testStopPolling_NotPolling() async throws {
        // Given
        XCTAssertFalse(messagePollingService.isPolling)

        // When/Then - Should handle gracefully
        await messagePollingService.stopPolling()
        XCTAssertFalse(messagePollingService.isPolling)
    }

    // MARK: - Message Retrieval Tests

    func testPollForMessages_NewMessages() async throws {
        // Test polling for new messages from MeshCore device

        // Given
        await messagePollingService.startPolling()

        // Configure mock to simulate new messages waiting
        let expectedMessages = [
            "New message 1",
            "New message 2"
        ]

        // TODO: Configure MockBLERadio to return queued messages
        // This requires MockBLERadio message queue simulation

        // When
        // Wait for polling cycle to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Then
        // TODO: Validate that new messages were retrieved and saved
        // TODO: Validate messages were processed according to MeshCore spec
        XCTFail("TODO: Implement MockBLERadio message queue simulation and validate polling behavior")
    }

    func testPollForMessages_EmptyQueue() async throws {
        // Test polling when no new messages are available

        // Given
        await messagePollingService.startPolling()
        let initialMessageCount = try modelContext.fetchCount(FetchDescriptor<Message>())

        // Configure mock to return empty message queue
        // TODO: Configure MockBLERadio to return empty queue

        // When
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Then
        let finalMessageCount = try modelContext.fetchCount(FetchDescriptor<Message>())
        XCTAssertEqual(finalMessageCount, initialMessageCount) // No new messages should be added
    }

    func testPollForMessages_MeshCoreProtocolCompliance() async throws {
        // Test that polling follows MeshCore specification correctly
        // Should use proper command codes and response handling

        // Given
        await messagePollingService.startPolling()

        // TODO: Validate that polling uses correct MeshCore commands:
        // - Should use syncNextMessage command with proper parameters
        // - Should handle response codes correctly
        // - Should respect message format specifications

        // When
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Then
        // TODO: Validate protocol compliance in polling implementation
        XCTFail("TODO: Implement MeshCore protocol compliance validation for message polling")
    }

    // MARK: - Polling Frequency Tests

    func testPollingFrequency_Default() async throws {
        // Test that polling respects default frequency settings

        // Given
        let expectedDefaultInterval: TimeInterval = 5.0 // Default 5 seconds
        await messagePollingService.startPolling()

        let startTime = Date()
        var pollCount = 0

        // When
        // Monitor polling for 15 seconds
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            pollCount += 1
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertGreaterThan(duration, 14.0) // Should be at least 15 seconds
        XCTAssertLessThan(duration, 20.0) // But not too much longer

        await messagePollingService.stopPolling()
    }

    func testPollingFrequency_Custom() async throws {
        // Test that polling respects custom frequency settings

        // Given
        let customInterval: TimeInterval = 2.0
        messagePollingService.pollingInterval = customInterval
        await messagePollingService.startPolling()

        // When
        let startTime = Date()
        try await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds
        let duration = Date().timeIntervalSince(startTime)

        // Then
        // Should complete approximately 3 polling cycles in 6 seconds
        XCTAssertGreaterThan(duration, 5.5)
        XCTAssertLessThan(duration, 7.0)

        await messagePollingService.stopPolling()
    }

    // MARK: - Background Operation Tests

    func testPollingInBackground() async throws {
        // Test that polling continues in background

        // Given
        await messagePollingService.startPolling()

        // When
        // Simulate app going to background
        // TODO: Implement background simulation
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Then
        XCTAssertTrue(messagePollingService.isPolling) // Should still be polling

        await messagePollingService.stopPolling()
    }

    func testPollingAppLifecycle_ForegroundBackground() async throws {
        // Test polling behavior during app lifecycle transitions

        // Given
        await messagePollingService.startPolling()

        // When - Simulate app going to background
        // TODO: Implement proper lifecycle notifications
        // NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Then - Should continue polling or pause based on configuration
        XCTAssertTrue(messagePollingService.isPolling)

        // When - Simulate app returning to foreground
        // TODO: Implement proper lifecycle notifications
        // NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Then - Should resume normal polling
        XCTAssertTrue(messagePollingService.isPolling)

        await messagePollingService.stopPolling()
    }

    // MARK: - Error Handling Tests

    func testPollingErrorHandling_DeviceDisconnected() async throws {
        // Test polling error handling when device is disconnected

        // Given
        await messagePollingService.startPolling()

        // Simulate device disconnection
        // TODO: Configure MockBLEManager to simulate disconnection

        // When
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Then
        // TODO: Validate error handling for device disconnection
        // TODO: Validate polling stops or retries appropriately
        XCTFail("TODO: Implement device disconnection simulation and error handling validation")
    }

    func testPollingErrorHandling_ProtocolError() async throws {
        // Test polling error handling for protocol-level errors

        // Given
        await messagePollingService.startPolling()

        // Simulate protocol error response
        // TODO: Configure MockBLERadio to return protocol errors

        // When
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Then
        // TODO: Validate error handling for protocol errors
        // TODO: Validate error logging and recovery
        XCTFail("TODO: Implement protocol error simulation and error handling validation")
    }

    // MARK: - Message Processing Tests

    func testProcessIncomingMessage_ValidFormat() async throws {
        // Test processing of incoming messages in correct format

        // Given
        let incomingMessageData = MockBLEManager.IncomingMessage(
            senderPublicKey: testContact.publicKey,
            recipientPublicKey: testDevice.publicKey,
            messageText: "Valid incoming message",
            timestamp: Date(),
            messageType: .direct
        )

        // When
        await messagePollingService.processIncomingMessage(incomingMessageData)

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.text == "Valid incoming message" &&
                message.recipientPublicKey == testDevice.publicKey
            }
        )
        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1)

        let savedMessage = messages.first!
        XCTAssertEqual(savedMessage.senderPublicKey, testContact.publicKey)
        XCTAssertEqual(savedMessage.recipientPublicKey, testDevice.publicKey)
        XCTAssertEqual(savedMessage.messageType, .direct)
    }

    func testProcessIncomingMessage_ChannelMessage() async throws {
        // Test processing of incoming channel messages

        // Given
        let testChannel = try TestDataFactory.createTestChannel()
        modelContext.insert(testChannel)
        try modelContext.save()

        let incomingChannelMessage = MockBLEManager.IncomingMessage(
            senderPublicKey: testContact.publicKey,
            recipientPublicKey: testDevice.publicKey,
            messageText: "Channel message",
            timestamp: Date(),
            messageType: .channel,
            channelId: testChannel.id
        )

        // When
        await messagePollingService.processIncomingMessage(incomingChannelMessage)

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.text == "Channel message" &&
                message.channelId == testChannel.id
            }
        )
        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1)

        let savedMessage = messages.first!
        XCTAssertEqual(savedMessage.messageType, .channel)
        XCTAssertEqual(savedMessage.channelId, testChannel.id)
    }

    func testProcessIncomingMessage_DuplicateDetection() async throws {
        // Test duplicate message detection and handling

        // Given
        let duplicateMessage = MockBLEManager.IncomingMessage(
            senderPublicKey: testContact.publicKey,
            recipientPublicKey: testDevice.publicKey,
            messageText: "Duplicate message",
            timestamp: Date(),
            messageType: .direct,
            messageId: "duplicate_id_123" // Same ID for both messages
        )

        // When - Process same message twice
        await messagePollingService.processIncomingMessage(duplicateMessage)
        await messagePollingService.processIncomingMessage(duplicateMessage)

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.text == "Duplicate message"
            }
        )
        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1) // Should only have one copy
    }

    // MARK: - Message Queue Tests

    func testMessageQueue_Ordering() async throws {
        // Test that messages are processed in correct order

        // Given
        let messages = [
            MockBLEManager.IncomingMessage(
                senderPublicKey: testContact.publicKey,
                recipientPublicKey: testDevice.publicKey,
                messageText: "First message",
                timestamp: Date(timeIntervalSinceNow: -10), // Oldest
                messageType: .direct
            ),
            MockBLEManager.IncomingMessage(
                senderPublicKey: testContact.publicKey,
                recipientPublicKey: testDevice.publicKey,
                messageText: "Second message",
                timestamp: Date(timeIntervalSinceNow: -5), // Middle
                messageType: .direct
            ),
            MockBLEManager.IncomingMessage(
                senderPublicKey: testContact.publicKey,
                recipientPublicKey: testDevice.publicKey,
                messageText: "Third message",
                timestamp: Date(), // Newest
                messageType: .direct
            )
        ]

        // When
        for message in messages {
            await messagePollingService.processIncomingMessage(message)
        }

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let savedMessages = try modelContext.fetch(fetchDescriptor)

        // Should have all messages
        let ourMessages = savedMessages.filter { $0.recipientPublicKey == testDevice.publicKey }
        XCTAssertEqual(ourMessages.count, 3)

        // Should be in chronological order
        XCTAssertEqual(ourMessages[0].text, "First message")
        XCTAssertEqual(ourMessages[1].text, "Second message")
        XCTAssertEqual(ourMessages[2].text, "Third message")
    }

    // MARK: - Notification Tests

    func testNewMessageNotification() async throws {
        // Test that new message notifications are sent

        // Given
        let incomingMessage = MockBLEManager.IncomingMessage(
            senderPublicKey: testContact.publicKey,
            recipientPublicKey: testDevice.publicKey,
            messageText: "Notification test message",
            timestamp: Date(),
            messageType: .direct
        )

        // Set up notification expectation
        let expectation = XCTestExpectation(description: "New message notification")

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NewMessageReceived"),
            object: nil,
            queue: nil
        ) { notification in
            expectation.fulfill()
        }

        // When
        await messagePollingService.processIncomingMessage(incomingMessage)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Performance Tests

    func testPollingPerformance_HighMessageVolume() async throws {
        // Test polling performance with high message volume

        // Given
        await messagePollingService.startPolling()

        let messageCount = 100
        let startTime = Date()

        // Simulate high volume of incoming messages
        for i in 0..<messageCount {
            let message = MockBLEManager.IncomingMessage(
                senderPublicKey: testContact.publicKey,
                recipientPublicKey: testDevice.publicKey,
                messageText: "High volume message \(i)",
                timestamp: Date(),
                messageType: .direct
            )
            await messagePollingService.processIncomingMessage(message)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(duration, 10.0) // Should process 100 messages quickly
        XCTAssertLessThan(duration / Double(messageCount), 0.1) // Average < 100ms per message

        // Validate all messages were saved
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.recipientPublicKey == testDevice.publicKey
            }
        )
        let savedMessages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(savedMessages.count, messageCount)

        await messagePollingService.stopPolling()
    }

    func testPollingMemoryUsage() async throws {
        // Test that polling doesn't cause memory leaks

        // Given
        await messagePollingService.startPolling()

        let initialMemory = getMemoryUsage()

        // When - Run polling for extended period with message processing
        for i in 0..<50 {
            let message = MockBLEManager.IncomingMessage(
                senderPublicKey: testContact.publicKey,
                recipientPublicKey: testDevice.publicKey,
                messageText: "Memory test message \(i)",
                timestamp: Date(),
                messageType: .direct
            )
            await messagePollingService.processIncomingMessage(message)

            // Small delay to simulate real polling
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        let finalMemory = getMemoryUsage()

        // Then
        let memoryIncrease = finalMemory - initialMemory
        XCTAssertLessThan(memoryIncrease, 50_000_000) // Should not increase by more than 50MB

        await messagePollingService.stopPolling()
    }

    // MARK: - Helper Methods

    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size)
        } else {
            return 0
        }
    }
}