import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests MessageService integration with MockBLERadio against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class MessageServiceTests: BaseTestCase {

    var messageService: MessageService!
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

        // Initialize MessageService with mock BLE manager
        messageService = MessageService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        messageService = nil
        testDevice = nil
        testContact = nil
        try await super.tearDown()
    }

    // MARK: - Message Sending Tests

    func testSendTextMessage_Success() async throws {
        // Given
        let messageText = "Test message"
        let recipientPublicKey = testContact.publicKey

        // When - Send message using MessageService
        try await messageService.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientPublicKey
        )

        // Then - Message should be saved with correct delivery status
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.recipientPublicKey == recipientPublicKey &&
                message.text == messageText
            }
        )

        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1)

        let savedMessage = messages.first!
        XCTAssertEqual(savedMessage.text, messageText)
        XCTAssertEqual(savedMessage.recipientPublicKey, recipientPublicKey)
        XCTAssertEqual(savedMessage.deliveryStatus, .sent) // Should be .sent after successful send

        // Validate protocol calls were made correctly
        // TODO: Validate exact bytes sent match MeshCore specification
        // Message format: [0x02][0x00][attempt:1][timestamp:4][recipient:32][text:UTF8]
    }

    func testSendTextMessage_SpecCompliance_PayloadFormat() async throws {
        // Given
        let messageText = "Hello MeshCore"
        let recipientPublicKey = testContact.publicKey

        // Configure mock to capture outgoing bytes for validation
        // TODO: This requires MockBLERadio TX capture functionality

        // When
        try await messageService.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientPublicKey
        )

        // Then - Validate payload format matches MeshCore specification
        // Expected format according to spec:
        // - attempt: 1 byte (little-endian)
        // - timestamp: 4 bytes (little-endian)
        // - recipient_key: 32 bytes
        // - text: UTF-8 encoded message
        // No floodMode or textType fields (these are PocketMesh violations)

        // TODO: Implement TX capture in MockBLERadio to validate bytes
        XCTFail("TODO: Implement MockBLERadio TX capture to validate message payload format")
    }

    func testSendTextMessage_SpecCompliance_RetryLogic() async throws {
        // Given
        let messageText = "Test retry logic"

        // Configure mock to simulate message sending failures
        // TODO: Configure MockBLERadio to simulate send failures for retry testing

        // When
        do {
            try await messageService.sendTextMessage(
                text: messageText,
                recipientPublicKey: testContact.publicKey
            )

            // Then - Should attempt retry according to MeshCore specification
            // Spec allows max_attempts=3 (attempts 0,1,2)
            // Should switch to flood mode at attempt 2 (flood_after=2)
            // Must call CMD_RESET_PATH when switching to flood mode

            // TODO: Validate retry behavior matches spec
            XCTFail("TODO: Implement retry logic validation")

        } catch {
            // Expected if all retry attempts fail
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Retry Logic Specification Compliance

    func testRetryLogic_SpecCompliance_UnifiedCounter() async throws {
        // Test that MessageService uses unified retry counter as per MeshCore spec
        // Current PocketMesh: 2 direct + 1 flood = 3 total (separate phases) - INCORRECT
        // Spec requirement: Maximum 3 total attempts (0,1,2) with unified loop - CORRECT

        // Given
        // Configure mock to require multiple attempts

        // When
        try await messageService.sendTextMessage(
            text: "Unified counter test",
            recipientPublicKey: testContact.publicKey
        )

        // Then
        // TODO: Validate that MessageService uses:
        // - Single unified counter (not separate direct/flood counters)
        // - Condition: while attempts < max_attempts AND (not flood OR flood_attempts < max_flood_attempts)
        // - Default values: max_attempts=3, flood_after=2, max_flood_attempts=2

        XCTFail("TODO: Implement unified counter validation - current PocketMesh implementation violates spec")
    }

    func testRetryLogic_SpecCompliance_ResetPathCall() async throws {
        // Test that MessageService calls CMD_RESET_PATH when switching to flood mode
        // Current PocketMesh: Only sets floodMode=true - INCORRECT
        // Spec requirement: Must call CMD_RESET_PATH (13) when switching to flood mode - CORRECT

        // Given
        // Configure mock to simulate direct message failure requiring flood mode

        // When
        try await messageService.sendTextMessage(
            text: "Reset path test",
            recipientPublicKey: testContact.publicKey
        )

        // Then
        // TODO: Validate that CMD_RESET_PATH (13) is called when flood_after=2 is reached
        // This clears the routing table before flood attempts

        XCTFail("TODO: Implement resetPath call validation - current PocketMesh implementation misses this required call")
    }

    func testRetryLogic_SpecCompliance_ACKWaiting() async throws {
        // Test that MessageService waits for PUSH_CODE_SEND_CONFIRMED (0x82)
        // Current PocketMesh: Doesn't wait for ACK, only stores ackCode - INCORRECT
        // Spec requirement: Must wait for ACK confirmation with matching ackCode - CORRECT

        // Given
        let expectedAckCode: UInt32 = 0x12345678

        // Configure mock to simulate ACK confirmation
        // TODO: This requires MockBLERadio ACK simulation capability

        // When
        try await messageService.sendTextMessage(
            text: "ACK waiting test",
            recipientPublicKey: testContact.publicKey
        )

        // Then
        // TODO: Validate that MessageService:
        // 1. Subscribes to PUSH_CODE_SEND_CONFIRMED notifications
        // 2. Waits for ACK with matching ackCode
        // 3. Uses timeout per spec: timeout = suggested_timeout / 1000 * 1.2
        // 4. Handles per-contact timeout if contact.ackTimeout is set

        XCTFail("TODO: Implement ACK waiting validation - current PocketMesh implementation doesn't wait for ACK confirmation")
    }

    // MARK: - Message Status Tracking Tests

    func testMessageStatusUpdate_DeliveryConfirmed() async throws {
        // Given
        let message = Message(
            text: "Status test",
            recipientPublicKey: testContact.publicKey,
            deliveryStatus: .sending,
            messageType: .direct
        )
        modelContext.insert(message)
        try modelContext.save()

        // Simulate ACK confirmation from MeshCore device
        // TODO: Simulate PUSH_CODE_SEND_CONFIRMED with matching ackCode

        // When
        // MessageService receives ACK confirmation

        // Then
        // TODO: Validate that message.deliveryStatus is updated to .delivered
        // This requires proper ACK waiting implementation in MessageService

        XCTFail("TODO: Implement ACK confirmation simulation and status update validation")
    }

    func testMessageStatusUpdate_DeliveryFailed() async throws {
        // Given
        let message = Message(
            text: "Failure test",
            recipientPublicKey: testContact.publicKey,
            deliveryStatus: .sending,
            messageType: .direct
        )
        modelContext.insert(message)
        try modelContext.save()

        // Simulate all retry attempts failing
        // TODO: Configure MockBLERadio to simulate persistent send failures

        // When
        do {
            try await messageService.sendTextMessage(
                text: "Failure test",
                recipientPublicKey: testContact.publicKey
            )
        } catch {
            // Expected when all attempts fail
        }

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { msg in
                msg.text == "Failure test"
            }
        )

        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1)

        let failedMessage = messages.first!
        XCTAssertEqual(failedMessage.deliveryStatus, .failed) // Should be .failed after all retries exhausted
    }

    // MARK: - Multiple Messages Tests

    func testSendMultipleMessages_Queueing() async throws {
        // Given
        let messages = [
            "Message 1",
            "Message 2",
            "Message 3"
        ]

        // When
        for messageText in messages {
            try await messageService.sendTextMessage(
                text: messageText,
                recipientPublicKey: testContact.publicKey
            )
        }

        // Then
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.recipientPublicKey == testContact.publicKey
            }
        )

        let savedMessages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(savedMessages.count, messages.count)

        // Validate all messages have correct status
        for message in savedMessages {
            XCTAssertTrue(messages.contains(message.text))
            XCTAssertEqual(message.recipientPublicKey, testContact.publicKey)
        }
    }

    func testSendMultipleMessages_Concurrent() async throws {
        // Test concurrent message sending to multiple contacts
        let contact2 = try TestDataFactory.createTestContact(id: "contact2")
        modelContext.insert(contact2)
        try modelContext.save()

        let messages = [
            (text: "To contact 1", recipient: testContact.publicKey),
            (text: "To contact 2", recipient: contact2.publicKey)
        ]

        // Send messages concurrently
        await withTaskGroup(of: Void.self) { group in
            for message in messages {
                group.addTask {
                    try await self.messageService.sendTextMessage(
                        text: message.text,
                        recipientPublicKey: message.recipient
                    )
                }
            }
        }

        // Validate all messages were saved
        let fetchDescriptor = FetchDescriptor<Message>()
        let allMessages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(allMessages.count, messages.count)
    }

    // MARK: - Message Deletion Tests

    func testDeleteMessage_Success() async throws {
        // Given
        let message = Message(
            text: "To be deleted",
            recipientPublicKey: testContact.publicKey,
            deliveryStatus: .sent,
            messageType: .direct
        )
        modelContext.insert(message)
        try modelContext.save()

        let initialCount = try modelContext.fetchCount(FetchDescriptor<Message>())

        // When
        modelContext.delete(message)
        try modelContext.save()

        // Then
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Message>())
        XCTAssertEqual(finalCount, initialCount - 1)

        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { msg in
                msg.text == "To be deleted"
            }
        )
        let remainingMessages = try modelContext.fetch(fetchDescriptor)
        XCTAssertTrue(remainingMessages.isEmpty)
    }

    // MARK: - Per-Contact Timeout Tests

    func testSendTextMessage_PerContactTimeout() async throws {
        // Test that MessageService respects per-contact timeout if specified
        // Spec supports per-contact timeout configuration

        // Given
        testContact.ackTimeout = 45.0 // 45 seconds for this contact
        try modelContext.save()

        // When
        try await messageService.sendTextMessage(
            text: "Custom timeout test",
            recipientPublicKey: testContact.publicKey
        )

        // Then
        // TODO: Validate that MessageService uses contact.ackTimeout instead of default
        // This requires Contact model to have ackTimeout property (currently missing)

        XCTFail("TODO: Implement Contact.ackTimeout property in Contact model and validate usage in MessageService")
    }

    // MARK: - Message Length Validation Tests

    func testSendTextMessage_MaxLength() async throws {
        // Given - Very long message that exceeds MTU
        let longMessage = String(repeating: "This is a very long message. ", count: 50)

        // When/Then - Should handle message fragmentation according to MeshCore spec
        // TODO: Validate MTU fragmentation behavior

        do {
            try await messageService.sendTextMessage(
                text: longMessage,
                recipientPublicKey: testContact.publicKey
            )

            // Validate message was saved correctly despite length
            let fetchDescriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { message in
                    message.text == longMessage
                }
            )
            let messages = try modelContext.fetch(fetchDescriptor)
            XCTAssertEqual(messages.count, 1)

        } catch {
            // Should handle gracefully or reject appropriately
            XCTFail("Long messages should be handled with MTU fragmentation, not rejected: \(error)")
        }
    }

    // MARK: - Binary Protocol Support Tests

    func testBinaryProtocolSupport_Missing() async throws {
        // Validate that MessageService would support binary protocol requests (0x32)
        // Current PocketMesh: Completely missing binary protocol support - INCORRECT
        // Spec requirement: Must support send_binary_req command (0x32) - CORRECT

        // TODO: This test documents missing functionality
        // Binary protocol support should be added to MessageService/Protocol layer

        XCTFail("TODO: Implement binary protocol support in MeshCoreProtocol - completely missing from current PocketMesh implementation")
    }

    // MARK: - Message Polling Tests

    func testMessagePollingService_Integration() async throws {
        // Test integration with MessagePollingService for background message retrieval
        // TODO: Implement MessagePollingService and test integration

        // Given
        let pollingService = MessagePollingService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )

        // When
        await pollingService.startPolling()

        // Then
        // TODO: Validate that polling service checks for new messages periodically
        // and integrates properly with MessageService

        await pollingService.stopPolling()
        XCTFail("TODO: Implement MessagePollingService and test integration")
    }
}