import XCTest
@testable import PocketMesh
@testable import PocketMeshKit

@MainActor
final class MessagingProtocolTests: BaseTestCase {
    func testSendTextMessageCommand() async throws {
        // Test CMD_SEND_TXT_MSG (2) → RESP_CODE_SENT (6)
        let recipientKey = TestDataFactory.alicePublicKey
        let messageText = "Hello, World!"

        let result = try await meshProtocol.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientKey,
            floodMode: false,
            scope: nil
        )

        // Verify result structure
        XCTAssertGreaterThan(result.expectedAck, 0, "Expected ACK should be returned")
        XCTAssertGreaterThan(result.estimatedTimeout, 0, "Estimated timeout should be > 0")
    }

    func testSendTextMessageBinaryPayload() async throws {
        // Test against CORRECT MeshCore specification
        // Current PocketMesh payload structure per protocol implementation
        // Spec payload: [attempt:1][timestamp:4][recipientKey:32][text:N]

        let recipientKey = TestDataFactory.bobPublicKey
        let messageText = "Test message"

        // NOTE: Binary encoding validation requires capturing TX writes.
        // The current mock infrastructure doesn't expose TX writes for inspection.
        // This test documents the expected behavior.

        // Expected structure per MeshCore specification with little-endian encoding:
        // [CMD_SEND_TXT_MSG:1][attempt:1][timestamp:4le][recipientKey:32][text:UTF8]

        let result = try await meshProtocol.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientKey,
            floodMode: false,
            scope: nil
        )

        // Verify command completed successfully
        XCTAssertGreaterThan(result.expectedAck, 0)

        // TODO: Add TX write capture to validate exact bytes sent
        // Expected validations:
        // - Frame should contain command, attempt, timestamp, recipient, and text
        // - Command code should be CMD_SEND_TXT_MSG (2)
        // - First attempt should be 0
        // - Timestamp should be encoded in little-endian
        // - Recipient key should match
        // - Text should be UTF-8 encoded at the end
    }

    func testSyncNextMessageCommand() async throws {
        // Test CMD_SYNC_NEXT_MESSAGE (10)

        // First call should return nil (no messages in queue)
        let message1 = try await meshProtocol.syncNextMessage()
        XCTAssertNil(message1, "Expected no messages on first sync")

        // TODO: Simulate queued message and verify retrieval
        // Would require MockBLERadio to support message queue simulation
    }

    func testFloodScopeCommands() async throws {
        // Test CMD_SET_FLOOD_SCOPE (54) and CMD_GET_FLOOD_SCOPE (57)

        // Set flood scope to global
        try await meshProtocol.setFloodScope("*")

        // Get flood scope back
        let scope = try await meshProtocol.getFloodScope()
        XCTAssertEqual(scope, "*", "Flood scope should be set to global")
    }

    func testChannelMessageCommand() async throws {
        // Test CMD_SEND_CHANNEL_TXT_MSG (3) → RESP_CODE_OK (0)

        try await meshProtocol.sendChannelTextMessage(
            text: "Channel message",
            channelIndex: 1,
            scope: nil
        )

        // Channel messages have no ACK, just verify no error thrown
    }

    func testBinaryProtocolRequestStructure() async throws {
        // Test binary request protocol (0x32) with request type correlation
        // This test validates the missing binary protocol implementation

        // CRITICAL: PocketMesh currently lacks binary protocol support (0x32 command)
        // The binary protocol is used for:
        // - STATUS_REQUEST (0x01)
        // - TELEMETRY_REQUEST (0x02)
        // - MMA_REQUEST (0x03)
        // - And other async request/response patterns

        // Expected binary request structure per spec:
        // [CMD_BINARY_REQ:1][tag:1][request_type:1][optional_payload:N]
        // Where tag is used for request/response correlation

        // TODO: Implement binary request method in MeshCoreProtocol
        // Expected method signature:
        // func sendBinaryRequest(requestType: UInt8, payload: Data?, tag: UInt8) async throws -> Data

        // For now, document that this feature is missing
        // This test intentionally fails to document the gap
        XCTFail("Binary protocol not implemented - requires MeshCoreProtocol.sendBinaryRequest()")
    }

    // MARK: - Message Validation Tests

    func testSendTextMessageWithMaxLength() async throws {
        // Test message at maximum length (160 bytes per spec)
        let recipientKey = TestDataFactory.charliePublicKey
        let messageText = String(repeating: "A", count: 160)

        let result = try await meshProtocol.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientKey,
            floodMode: false,
            scope: nil
        )

        XCTAssertGreaterThan(result.expectedAck, 0)
    }

    func testSendTextMessageWithFloodMode() async throws {
        // Test sending message with flood mode enabled
        let recipientKey = TestDataFactory.alicePublicKey
        let messageText = "Flood message"

        let result = try await meshProtocol.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientKey,
            floodMode: true,
            scope: nil
        )

        XCTAssertGreaterThan(result.expectedAck, 0)
        // Flood mode messages should still return ACK code
    }

    func testSendChannelMessageWithScope() async throws {
        // Test channel message with scope restriction
        try await meshProtocol.sendChannelTextMessage(
            text: "Scoped channel message",
            channelIndex: 2,
            scope: "test-scope"
        )

        // Should complete without error
    }

    func testMultipleMessagesInSequence() async throws {
        // Test sending multiple messages sequentially
        let recipientKey = TestDataFactory.bobPublicKey

        for i in 0..<3 {
            let result = try await meshProtocol.sendTextMessage(
                text: "Message \(i)",
                recipientPublicKey: recipientKey,
                floodMode: false,
                scope: nil
            )
            XCTAssertGreaterThan(result.expectedAck, 0)
        }
    }

    // MARK: - Error Handling Tests

    func testSendTextMessageWithInvalidRecipient() async throws {
        // Test with empty recipient key (should fail)
        let emptyKey = Data()
        let messageText = "Test"

        do {
            _ = try await meshProtocol.sendTextMessage(
                text: messageText,
                recipientPublicKey: emptyKey,
                floodMode: false,
                scope: nil
            )
            XCTFail("Expected error for invalid recipient key")
        } catch {
            // Expected - invalid recipient key should cause error
        }
    }

    func testSendTextMessageWithEmptyText() async throws {
        // Test with empty message text
        let recipientKey = TestDataFactory.alicePublicKey
        let messageText = ""

        // Empty message should be allowed (edge case)
        let result = try await meshProtocol.sendTextMessage(
            text: messageText,
            recipientPublicKey: recipientKey,
            floodMode: false,
            scope: nil
        )

        XCTAssertGreaterThan(result.expectedAck, 0)
    }
}
