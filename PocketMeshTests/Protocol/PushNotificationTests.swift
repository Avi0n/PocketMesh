import XCTest
@testable import PocketMesh
@testable import PocketMeshKit

@MainActor
final class PushNotificationTests: BaseTestCase {
    func testAdvertisementPushNotification() async throws {
        // Test PUSH_CODE_ADVERT (0x80) and PUSH_CODE_NEW_ADVERT (0x8A)

        let expectation = expectation(description: "Advertisement push received")

        // Subscribe to advertisements
        await meshProtocol.subscribeToAdvertisements { push in
            // Verify push within handler
            XCTAssertEqual(push.publicKeyPrefix.count, 6, "Public key prefix should be 6 bytes")
            expectation.fulfill()
        }

        // Simulate incoming advertisement
        let testPublicKey = TestDataFactory.alicePublicKey
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: testPublicKey,
            name: "Alice"
        )

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testMessageWaitingPushNotification() async throws {
        // Test PUSH_CODE_MSG_WAITING (0x83)

        let expectation = expectation(description: "Message waiting push received")

        await meshProtocol.subscribeToMessageNotifications { _ in
            expectation.fulfill()
        }

        // Simulate message waiting notification
        await mockRadio.simulateMessageWaiting()

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSendConfirmationPushNotification() async throws {
        // Test PUSH_CODE_SEND_CONFIRMED (0x82)

        // NOTE: MockBLERadio doesn't currently have a simulateAckConfirmation method
        // This test documents the expected behavior for when it's implemented

        // Expected workflow:
        // 1. Send a message
        // 2. Receive ACK code in response
        // 3. Wait for PUSH_CODE_SEND_CONFIRMED with matching ACK
        // 4. Verify round-trip time is included

        // TODO: Implement simulateAckConfirmation in MockBLERadio
        // Expected signature:
        // func simulateAckConfirmation(ackCode: UInt32, roundTripMs: UInt32) async

        throw XCTSkip("ACK confirmation simulation not yet implemented in MockBLERadio")
    }

    // MARK: - Multiple Push Notifications

    func testMultipleAdvertisementPushes() async throws {
        // Test receiving multiple advertisement pushes

        let expectation = expectation(description: "Multiple advertisements received")
        expectation.expectedFulfillmentCount = 3

        await meshProtocol.subscribeToAdvertisements { push in
            XCTAssertEqual(push.publicKeyPrefix.count, 6)
            expectation.fulfill()
        }

        // Simulate advertisements from different contacts
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: TestDataFactory.alicePublicKey,
            name: "Alice"
        )
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: TestDataFactory.bobPublicKey,
            name: "Bob"
        )
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: TestDataFactory.charliePublicKey,
            name: "Charlie"
        )

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testMultipleMessageWaitingNotifications() async throws {
        // Test receiving multiple message waiting notifications

        let expectation = expectation(description: "Multiple message notifications")
        expectation.expectedFulfillmentCount = 3

        await meshProtocol.subscribeToMessageNotifications { _ in
            expectation.fulfill()
        }

        // Simulate multiple message waiting notifications
        for _ in 0..<3 {
            await mockRadio.simulateMessageWaiting()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Push Notification Data Validation

    func testAdvertisementPushContainsValidData() async throws {
        // Verify advertisement push contains all expected fields

        let expectation = expectation(description: "Advertisement with valid data")

        await meshProtocol.subscribeToAdvertisements { push in
            XCTAssertEqual(push.publicKeyPrefix.count, 6)
            XCTAssertFalse(push.name.isEmpty, "Name should not be empty")
            expectation.fulfill()
        }

        let testPublicKey = TestDataFactory.alicePublicKey
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: testPublicKey,
            name: "TestContact"
        )

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Subscription Management

    func testMultipleSubscribersReceiveSamePush() async throws {
        // Test that multiple subscribers all receive the same push notification

        let expectation1 = expectation(description: "Subscriber 1 receives push")
        let expectation2 = expectation(description: "Subscriber 2 receives push")

        // Subscribe twice with different handlers
        await meshProtocol.subscribeToAdvertisements { _ in
            expectation1.fulfill()
        }

        await meshProtocol.subscribeToAdvertisements { _ in
            expectation2.fulfill()
        }

        // Simulate single advertisement
        let testPublicKey = TestDataFactory.bobPublicKey
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: testPublicKey,
            name: "Bob"
        )

        await fulfillment(of: [expectation1, expectation2], timeout: 2.0)
    }

    // MARK: - Push Notification Types

    func testDifferentPushTypesAreIndependent() async throws {
        // Verify that subscriptions to different push types don't interfere

        let advertExpectation = expectation(description: "Advertisement received")
        let messageExpectation = expectation(description: "Message notification received")

        await meshProtocol.subscribeToAdvertisements { _ in
            advertExpectation.fulfill()
        }

        await meshProtocol.subscribeToMessageNotifications { _ in
            messageExpectation.fulfill()
        }

        // Simulate both types
        await mockRadio.simulateIncomingAdvertisement(
            publicKey: TestDataFactory.alicePublicKey,
            name: "Alice"
        )
        await mockRadio.simulateMessageWaiting()

        await fulfillment(of: [advertExpectation, messageExpectation], timeout: 2.0)
    }

    // MARK: - Error Handling

    func testMalformedPushNotificationIsHandledGracefully() async throws {
        // Test that protocol handles malformed push notifications without crashing

        // NOTE: This would require direct manipulation of RX characteristic
        // to send invalid data, which isn't currently exposed in the mock API

        // TODO: Add method to MockBLERadio for simulating malformed frames
        // Expected: func simulateRawRXData(_ data: Data) async

        throw XCTSkip("Malformed push simulation not yet supported by MockBLERadio")
    }
}
