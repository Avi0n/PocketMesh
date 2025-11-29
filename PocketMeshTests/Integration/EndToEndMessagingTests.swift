import XCTest
import SwiftData
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests complete end-to-end messaging workflows against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class EndToEndMessagingTests: BaseTestCase {

    var e2eTester: EndToEndMessagingTester!
    var device1: Device!
    var device2: Device!
    var contact1: Contact!
    var contact2: Contact!

    override func setUp() async throws {
        try await super.setUp()

        // Create two test devices simulating different users
        device1 = try TestDataFactory.createTestDevice(id: "device1")
        device2 = try TestDataFactory.createTestDevice(id: "device2")

        // Create corresponding contacts
        contact1 = try TestDataFactory.createTestContact(id: "contact1")
        contact2 = try TestDataFactory.createTestContact(id: "contact2")

        // Save to SwiftData context
        modelContext.insert(device1)
        modelContext.insert(device2)
        modelContext.insert(contact1)
        modelContext.insert(contact2)
        try modelContext.save()

        // Initialize end-to-end tester with mock BLE manager
        e2eTester = EndToEndMessagingTester(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        await e2eTester.cleanup()
        e2eTester = nil
        device1 = nil
        device2 = nil
        contact1 = nil
        contact2 = nil
        try await super.tearDown()
    }

    // MARK: - Basic End-to-End Messaging Tests

    func testEndToEndMessaging_DirectMessage() async throws {
        // Test complete end-to-end direct message flow

        // Given
        let messageText = "Hello from device1 to device2"
        let senderDevice = device1
        let recipientContact = contact2

        // When - Send message from device1 to device2
        let e2eResult = try await e2eTester.sendEndToEndMessage(
            from: senderDevice,
            to: recipientContact.publicKey,
            text: messageText,
            messageType: .direct
        )

        // Then
        XCTAssertTrue(e2eResult.success)
        XCTAssertEqual(e2eResult.originalMessage.text, messageText)
        XCTAssertEqual(e2eResult.originalMessage.senderPublicKey, senderDevice.publicKey)
        XCTAssertEqual(e2eResult.originalMessage.recipientPublicKey, recipientContact.publicKey)
        XCTAssertEqual(e2eResult.originalMessage.messageType, .direct)

        // Message should be delivered
        XCTAssertEqual(e2eResult.finalDeliveryStatus, .delivered)
        XCTAssertNotNil(e2eResult.deliveryTimestamp)

        // Verify message was saved on both devices
        let senderMessages = try e2eTester.getMessagesForDevice(senderDevice.publicKey)
        let recipientMessages = try e2eTester.getMessagesForDevice(recipientContact.publicKey)

        XCTAssertGreaterThan(senderMessages.count, 0)
        XCTAssertGreaterThan(recipientMessages.count, 0)

        let sentMessage = senderMessages.first { $0.text == messageText }
        let receivedMessage = recipientMessages.first { $0.text == messageText }

        XCTAssertNotNil(sentMessage)
        XCTAssertNotNil(receivedMessage)

        // Validate complete workflow followed MeshCore specification
        XCTAssertTrue(e2eResult.protocolCompliant)
        XCTAssertTrue(e2eResult.properPayloadFormat)
        XCTAssertTrue(e2eResult.properRetryLogic)
        XCTAssertTrue(e2eResult.properAckHandling)

        XCTFail("TODO: Implement complete end-to-end direct message flow testing")
    }

    func testEndToEndMessaging_ChannelMessage() async throws {
        // Test complete end-to-end channel message flow

        // Given
        let messageText = "Hello channel message"
        let channelName = "Test Channel"
        let channelSecret = "channel_secret_123"

        // Create channel on device1
        let channel = try await e2eTester.createChannel(
            on: device1,
            name: channelName,
            secret: channelSecret
        )

        // Device2 joins the same channel
        try await e2eTester.joinChannel(
            on: device2,
            channelHash: channel.hashedSecret
        )

        // When - Send channel message from device1
        let e2eResult = try await e2eTester.sendEndToEndChannelMessage(
            from: device1,
            to: channel.id,
            text: messageText
        )

        // Then
        XCTAssertTrue(e2eResult.success)
        XCTAssertEqual(e2eResult.originalMessage.text, messageText)
        XCTAssertEqual(e2eResult.originalMessage.channelId, channel.id)
        XCTAssertEqual(e2eResult.originalMessage.messageType, .channel)

        // Channel message should be delivered to all channel members
        XCTAssertEqual(e2eResult.finalDeliveryStatus, .delivered)
        XCTAssertEqual(e2eResult.deliveredToMembers, 2) // device1 and device2

        // Verify channel message was saved on both devices
        let device1ChannelMessages = try e2eTester.getChannelMessagesForDevice(
            device1.publicKey,
            channelId: channel.id
        )
        let device2ChannelMessages = try e2eTester.getChannelMessagesForDevice(
            device2.publicKey,
            channelId: channel.id
        )

        XCTAssertGreaterThan(device1ChannelMessages.count, 0)
        XCTAssertGreaterThan(device2ChannelMessages.count, 0)

        // Validate channel protocol compliance
        XCTAssertTrue(e2eResult.channelProtocolCompliant)
        XCTAssertTrue(e2eResult.properChannelEncryption)

        XCTFail("TODO: Implement complete end-to-end channel message flow testing")
    }

    func testEndToEndMessaging_MultiHop() async throws {
        // Test end-to-end messaging through multiple mesh hops

        // Given
        let messageText = "Multi-hop message"
        let hopCount = 3

        // Create intermediate devices for multi-hop path
        let intermediateDevices = try createIntermediateDeviceChain(count: hopCount)

        // Configure mesh topology: device1 -> intermediate -> device2
        try await e2eTester.configureMeshTopology(
            source: device1,
            intermediate: intermediateDevices,
            destination: device2
        )

        // When - Send message that requires multi-hop routing
        let e2eResult = try await e2eTester.sendMultiHopMessage(
            from: device1,
            to: device2.publicKey,
            text: messageText,
            expectedHops: hopCount
        )

        // Then
        XCTAssertTrue(e2eResult.success)
        XCTAssertEqual(e2eResult.actualHopCount, hopCount)
        XCTAssertEqual(e2eResult.finalDeliveryStatus, .delivered)

        // Message should have traversed the correct path
        XCTAssertEqual(e2eResult.hopPath.count, hopCount + 1) // Including source and destination

        // Validate multi-hop protocol compliance
        XCTAssertTrue(e2eResult.multiHopProtocolCompliant)
        XCTAssertTrue(e2eResult.pathDiscoverySuccessful)

        XCTFail("TODO: Implement multi-hop end-to-end messaging testing")
    }

    // MARK: - Complex Messaging Scenarios Tests

    func testEndToEndMessaging_ConcurrentMessaging() async throws {
        // Test concurrent messaging between multiple devices

        // Given
        let deviceCount = 5
        let messagesPerDevice = 20

        // Create additional devices
        let devices = [device1, device2] + try createAdditionalDevices(count: deviceCount - 2)

        // Establish full mesh connectivity
        try await e2eTester.establishFullMeshConnectivity(devices)

        // When - Send concurrent messages
        let startTime = Date()

        let concurrentResults = try await e2eTester.sendConcurrentMessages(
            devices: devices,
            messagesPerDevice: messagesPerDevice
        )

        let totalTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertEqual(concurrentResults.totalAttempted, deviceCount * messagesPerDevice)
        XCTAssertEqual(concurrentResults.totalSuccessful, concurrentResults.totalAttempted)
        XCTAssertEqual(concurrentResults.totalFailed, 0)

        // Should maintain reasonable throughput even with concurrent messaging
        let throughput = Double(concurrentResults.totalSuccessful) / totalTime
        XCTAssertGreaterThan(throughput, 50) // At least 50 messages/second concurrent

        // Validate all devices received their messages
        for device in devices {
            let deviceMessages = try e2eTester.getMessagesForDevice(device.publicKey)
            XCTAssertGreaterThanOrEqual(deviceMessages.count, messagesPerDevice)
        }

        XCTFail("TODO: Implement concurrent end-to-end messaging testing")
    }

    func testEndToEndMessaging_MessagePersistence() async throws {
        // Test message persistence across app restarts and device reconnections

        // Given
        let messageText = "Persistence test message"

        // Send message from device1 to device2
        let initialResult = try await e2eTester.sendEndToEndMessage(
            from: device1,
            to: device2.publicKey,
            text: messageText,
            messageType: .direct
        )

        XCTAssertTrue(initialResult.success)

        // Simulate app restart on device2
        try await e2eTester.simulateAppRestart(on: device2)

        // Simulate device reconnection
        try await e2eTester.simulateDeviceReconnection(device2)

        // When - Check message persistence
        let persistedMessages = try e2eTester.getMessagesForDevice(device2.publicKey)

        // Then
        XCTAssertGreaterThan(persistedMessages.count, 0)

        let persistedMessage = persistedMessages.first { $0.text == messageText }
        XCTAssertNotNil(persistedMessage)
        XCTAssertEqual(persistedMessage?.deliveryStatus, .delivered)
        XCTAssertNotNil(persistedMessage?.receivedAt)

        // Validate message metadata was preserved
        XCTAssertEqual(persistedMessage?.senderPublicKey, device1.publicKey)
        XCTAssertEqual(persistedMessage?.recipientPublicKey, device2.publicKey)

        XCTFail("TODO: Implement message persistence testing across app lifecycle")
    }

    func testEndToEndMessaging_OfflineMessaging() async throws {
        // Test offline message delivery when recipient comes online

        // Given
        let messageText = "Offline message test"

        // Take device2 offline
        try await e2eTester.takeDeviceOffline(device2)

        // Send message from device1 to offline device2
        let offlineResult = try await e2eTester.sendEndToEndMessage(
            from: device1,
            to: device2.publicKey,
            text: messageText,
            messageType: .direct
        )

        // Then - Message should be queued for later delivery
        XCTAssertFalse(offlineResult.deliveredImmediately)
        XCTAssertTrue(offlineResult.queuedForDelivery)
        XCTAssertNotNil(offlineResult.queueTimestamp)

        // When - Bring device2 back online
        try await e2eTester.bringDeviceOnline(device2)

        // Wait for message delivery
        let deliveryResult = try await e2eTester.waitForMessageDelivery(
            messageId: offlineResult.messageId,
            timeout: 10.0
        )

        // Then
        XCTAssertTrue(deliveryResult.delivered)
        XCTAssertEqual(deliveryResult.deliveryLatency, 0.0) // Delivered after coming online

        // Verify message was received
        let receivedMessages = try e2eTester.getMessagesForDevice(device2.publicKey)
        let receivedMessage = receivedMessages.first { $0.text == messageText }
        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.deliveryStatus, .delivered)

        XCTFail("TODO: Implement offline messaging and store-and-forward testing")
    }

    // MARK: - MeshCore Protocol Compliance Tests

    func testEndToEndMessaging_MeshCoreProtocolCompliance() async throws {
        // Test complete end-to-end flow with strict MeshCore protocol compliance validation

        // Given
        let messageText = "MeshCore compliance test"

        // Enable strict protocol compliance monitoring
        await e2eTester.enableStrictProtocolComplianceValidation()

        // When - Send message with compliance monitoring
        let complianceResult = try await e2eTester.sendEndToEndMessageWithComplianceValidation(
            from: device1,
            to: device2.publicKey,
            text: messageText,
            messageType: .direct
        )

        // Then
        XCTAssertTrue(complianceResult.messageDelivered)
        XCTAssertTrue(complianceResult.protocolCompliant)

        // Validate specific MeshCore compliance aspects:

        // 1. Command payload format compliance
        XCTAssertTrue(complianceResult.commandPayloadCompliant)
        XCTAssertEqual(complianceResult.commandCode, 0x02) // sendMessage
        XCTAssertEqual(complianceResult.messageType, 0x00) // Text message

        // 2. Message encoding compliance
        XCTAssertTrue(complianceResult.messageEncodingCompliant)
        XCTAssertNotNil(complianceResult.attempt) // Attempt field present
        XCTAssertNotNil(complianceResult.timestamp) // Timestamp field present
        XCTAssertEqual(complianceResult.recipientPublicKey, device2.publicKey)

        // 3. Retry logic compliance
        XCTAssertTrue(complianceResult.retryLogicCompliant)
        XCTAssertLessThanOrEqual(complianceResult.maxAttemptsUsed, 3) // MeshCore max
        XCTAssertLessThanOrEqual(complianceResult.floodAttemptsUsed, 2) // MeshCore max

        // 4. ACK handling compliance
        XCTAssertTrue(complianceResult.ackHandlingCompliant)
        XCTAssertNotNil(complianceResult.ackCode)
        XCTAssertNotNil(complianceResult.ackReceivedAt)

        // 5. Binary protocol support (if applicable)
        XCTAssertTrue(complianceResult.binaryProtocolSupported)

        // Validate complete protocol flow
        XCTAssertEqual(complianceResult.protocolSteps.count, 5) // Expected steps in flow
        XCTAssertTrue(complianceResult.allStepsSuccessful)

        XCTFail("TODO: Implement comprehensive MeshCore protocol compliance validation in end-to-end flow")
    }

    func testEndToEndMessaging_MeshCoreContactSync() async throws {
        // Test end-to-end contact synchronization following MeshCore specification

        // Given
        let device1Contacts = [
            try TestDataFactory.createTestContact(id: "d1_contact1"),
            try TestDataFactory.createTestContact(id: "d1_contact2"),
            try TestDataFactory.createTestContact(id: "d1_contact3")
        ]

        let device2Contacts = [
            try TestDataFactory.createTestContact(id: "d2_contact1"),
            try TestDataFactory.createTestContact(id: "d2_contact2")
        ]

        // Add contacts to device1
        for contact in device1Contacts {
            modelContext.insert(contact)
        }
        try modelContext.save()

        // When - Sync contacts from device1 to device2
        let syncResult = try await e2eTester.syncContactsWithComplianceValidation(
            from: device1,
            to: device2,
            contacts: device1Contacts
        )

        // Then
        XCTAssertTrue(syncResult.success)
        XCTAssertEqual(syncResult.syncedContacts, device1Contacts.count)

        // Validate MeshCore contact sync compliance:

        // 1. Contact data structure compliance
        XCTAssertTrue(syncResult.contactStructureCompliant)
        for contact in device1Contacts {
            // Contact type should match MeshCore enum values
            if contact.contactType == .chat {
                XCTAssertEqual(contact.contactType.rawValue, 0)
            } else if contact.contactType == .companion {
                XCTAssertEqual(contact.contactType.rawValue, 1)
            }
        }

        // 2. String encoding compliance
        XCTAssertTrue(syncResult.stringEncodingCompliant)
        // All string fields should be properly null-terminated UTF-8

        // 3. Path data handling compliance
        XCTAssertTrue(syncResult.pathDataCompliant)

        // 4. Binary protocol usage for contact operations
        XCTAssertTrue(syncResult.binaryProtocolCompliant)

        // Verify contacts were synced to device2
        let device2SyncedContacts = try e2eTester.getContactsForDevice(device2.publicKey)
        XCTAssertGreaterThanOrEqual(device2SyncedContacts.count, device1Contacts.count)

        XCTFail("TODO: Implement MeshCore-compliant contact synchronization testing")
    }

    // MARK: - Real-World Scenario Tests

    func testEndToEndMessaging_RealWorldScenario_GroupChat() async throws {
        // Test realistic group chat scenario

        // Given
        let participantCount = 8
        let messagesPerParticipant = 5
        let groupChannelName = "Real World Group Chat"
        let groupChannelSecret = "real_world_secret"

        // Create participants
        let participants = try createTestParticipants(count: participantCount)

        // Create group channel
        let groupChannel = try await e2eTester.createGroupChannel(
            name: groupChannelName,
            secret: groupChannelSecret,
            participants: participants
        )

        // When - Participants send messages to group chat
        let groupChatResult = try await e2eTester.simulateGroupChat(
            channel: groupChannel,
            participants: participants,
            messagesPerParticipant: messagesPerParticipant
        )

        // Then
        XCTAssertTrue(groupChatResult.success)
        XCTAssertEqual(groupChatResult.totalMessages, participantCount * messagesPerParticipant)
        XCTAssertEqual(groupChatResult.deliveredMessages, groupChatResult.totalMessages)

        // Each participant should receive all messages
        for participant in participants {
            let participantMessages = try e2eTester.getChannelMessagesForDevice(
                participant.publicKey,
                channelId: groupChannel.id
            )
            XCTAssertGreaterThanOrEqual(participantMessages.count, groupChatResult.totalMessages)
        }

        // Validate realistic performance
        XCTAssertLessThan(groupChatResult.totalDuration, 60.0) // Should complete within 1 minute
        XCTAssertLessThan(groupChatResult.averageMessageLatency, 2.0) // Average latency < 2 seconds

        XCTFail("TODO: Implement realistic group chat scenario testing")
    }

    func testEndToEndMessaging_RealWorldScenario_EmergencyBroadcast() async throws {
        // Test emergency broadcast message to all contacts

        // Given
        let emergencyMessage = "EMERGENCY: This is a test emergency broadcast"
        let contactCount = 20
        let emergencyPriority = true

        // Create emergency broadcast list
        let emergencyContacts = try createEmergencyContacts(count: contactCount)

        // When - Send emergency broadcast
        let broadcastResult = try await e2eTester.sendEmergencyBroadcast(
            from: device1,
            message: emergencyMessage,
            contacts: emergencyContacts,
            priority: emergencyPriority
        )

        // Then
        XCTAssertTrue(broadcastResult.success)
        XCTAssertEqual(broadcastResult.totalContacts, contactCount)
        XCTAssertEqual(broadcastResult.deliveredContacts, contactCount)

        // Emergency messages should be delivered with highest priority
        XCTAssertLessThan(broadcastResult.averageDeliveryTime, 1.0) // Should deliver within 1 second
        XCTAssertEqual(broadcastResult.priority, .high)

        // All contacts should receive the emergency message
        for contact in emergencyContacts {
            let contactMessages = try e2eTester.getMessagesForDevice(contact.publicKey)
            let emergencyMessageReceived = contactMessages.first { $0.text == emergencyMessage }
            XCTAssertNotNil(emergencyMessageReceived)
            XCTAssertEqual(emergencyMessageReceived?.priority, .high)
        }

        // Validate flood mode was used for emergency broadcast
        XCTAssertTrue(broadcastResult.floodModeUsed)
        XCTAssertGreaterThan(broadcastResult.floodScope, .local)

        XCTFail("TODO: Implement emergency broadcast scenario testing")
    }

    func testEndToEndMessaging_RealWorldScenario_PoorConnectivity() async throws {
        // Test messaging under poor connectivity conditions

        // Given
        let messageCount = 50
        let packetLossRate = 0.3 // 30% packet loss
        let highLatency = 1.5 // 1.5 seconds latency

        // Configure poor network conditions
        await e2eTester.configurePoorNetworkConditions(
            packetLoss: packetLossRate,
            latency: highLatency
        )

        // When - Send messages under poor conditions
        let poorConnectivityResult = try await e2eTester.sendMessagesUnderPoorConditions(
            from: device1,
            to: device2.publicKey,
            messageCount: messageCount
        )

        // Then
        XCTAssertEqual(poorConnectivityResult.attemptedMessages, messageCount)

        // Should achieve reasonable success rate even under poor conditions
        let successRate = Double(poorConnectivityResult.deliveredMessages) / Double(poorConnectivityResult.attemptedMessages)
        XCTAssertGreaterThan(successRate, 0.7) // At least 70% success rate

        // Should use appropriate retry and flood strategies
        XCTAssertTrue(poorConnectivityResult.retryStrategyUsed)
        XCTAssertTrue(poorConnectivityResult.floodModeEngaged)

        // Validate adaptive behavior
        XCTAssertGreaterThan(poorConnectivityResult.averageRetryCount, 1) // Should retry failed messages
        XCTAssertLessThan(poorConnectivityResult.maxLatencyObserved, highLatency * 3) // Should not exceed reasonable bounds

        XCTFail("TODO: Implement poor connectivity scenario testing")
    }

    // MARK: - Error Handling and Recovery Tests

    func testEndToEndMessaging_ErrorRecovery() async throws {
        // Test error recovery during end-to-end messaging

        // Given
        let messageText = "Error recovery test"

        // Simulate various error scenarios
        let errorScenarios = [
            "device_disconnection",
            "protocol_timeout",
            "malformed_response",
            "memory_pressure"
        ]

        var successfulRecoveries = 0

        for scenario in errorScenarios {
            // Configure error scenario
            await e2eTester.configureErrorScenario(scenario)

            // When - Attempt message with error scenario
            do {
                let result = try await e2eTester.sendEndToEndMessageWithErrorRecovery(
                    from: device1,
                    to: device2.publicKey,
                    text: "\(messageText) - \(scenario)",
                    errorScenario: scenario
                )

                if result.success {
                    successfulRecoveries += 1
                }
            } catch {
                // Some scenarios might legitimately fail
            }

            // Reset error scenario
            await e2eTester.resetErrorScenario()
        }

        // Then
        XCTAssertGreaterThan(successfulRecoveries, errorScenarios.count / 2) // At least half should recover

        // Validate error handling mechanisms
        let errorHandlingStats = await e2eTester.getErrorHandlingStatistics()
        XCTAssertGreaterThan(errorHandlingStats.totalErrors, 0)
        XCTAssertGreaterThan(errorHandlingStats.successfulRecoveries, 0)
        XCTAssertGreaterThan(errorHandlingStats.recoveryRate, 0.5)

        XCTFail("TODO: Implement comprehensive error recovery testing in end-to-end scenarios")
    }

    // MARK: - Performance and Scale Tests

    func testEndToEndMessaging_Performance_LargeScale() async throws {
        // Test end-to-end messaging at large scale

        // Given
        let deviceCount = 100
        let messagesPerDevice = 10
        let totalExpectedMessages = deviceCount * messagesPerDevice

        // Create large device network
        let largeDeviceNetwork = try createLargeDeviceNetwork(count: deviceCount)

        // Establish mesh connectivity
        try await e2eTester.establishMeshNetwork(devices: largeDeviceNetwork)

        // When - Send messages at scale
        let startTime = Date()

        let scaleResult = try await e2eTester.sendMessagesAtScale(
            devices: largeDeviceNetwork,
            messagesPerDevice: messagesPerDevice
        )

        let totalTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertEqual(scaleResult.attemptedMessages, totalExpectedMessages)
        XCTAssertEqual(scaleResult.successfulMessages, totalExpectedMessages)

        // Should maintain reasonable performance at scale
        let throughput = Double(scaleResult.successfulMessages) / totalTime
        XCTAssertGreaterThan(throughput, 100) // At least 100 messages/second at scale

        // Memory usage should be reasonable
        let memoryUsage = getMemoryUsage()
        XCTAssertLessThan(memoryUsage, 500_000_000) // Should not exceed 500MB

        // Network efficiency should be good
        XCTAssertLessThan(scaleResult.averageNetworkOverhead, 0.3) // Less than 30% overhead

        XCTFail("TODO: Implement large-scale end-to-end messaging performance testing")
    }

    // MARK: - Helper Methods

    private func createIntermediateDeviceChain(count: Int) throws -> [Device] {
        var devices: [Device] = []
        for i in 0..<count {
            let device = try TestDataFactory.createTestDevice(id: "intermediate_\(i)")
            devices.append(device)
        }
        return devices
    }

    private func createAdditionalDevices(count: Int) throws -> [Device] {
        var devices: [Device] = []
        for i in 0..<count {
            let device = try TestDataFactory.createTestDevice(id: "additional_\(i)")
            devices.append(device)
        }
        return devices
    }

    private func createTestParticipants(count: Int) throws -> [Device] {
        var participants: [Device] = []
        for i in 0..<count {
            let participant = try TestDataFactory.createTestDevice(id: "participant_\(i)")
            participants.append(participant)
        }
        return participants
    }

    private func createEmergencyContacts(count: Int) throws -> [Contact] {
        var contacts: [Contact] = []
        for i in 0..<count {
            let contact = try TestDataFactory.createTestContact(id: "emergency_\(i)")
            contacts.append(contact)
        }
        return contacts
    }

    private func createLargeDeviceNetwork(count: Int) throws -> [Device] {
        var devices: [Device] = []
        for i in 0..<count {
            let device = try TestDataFactory.createTestDevice(id: "network_device_\(i)")
            devices.append(device)
        }
        return devices
    }

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

// MARK: - End-to-End Messaging Tester Helper Class

/// Helper class for testing complete end-to-end messaging workflows
class EndToEndMessagingTester {
    private let bleManager: MockBLEManager
    private let modelContext: ModelContext

    struct EndToEndResult {
        let success: Bool
        let originalMessage: Message
        let finalDeliveryStatus: MessageDeliveryStatus
        let deliveryTimestamp: Date?
        let protocolCompliant: Bool
        let properPayloadFormat: Bool
        let properRetryLogic: Bool
        let properAckHandling: Bool
    }

    struct ChannelEndToEndResult {
        let success: Bool
        let originalMessage: Message
        let finalDeliveryStatus: MessageDeliveryStatus
        let deliveredToMembers: Int
        let channelProtocolCompliant: Bool
        let properChannelEncryption: Bool
    }

    struct MultiHopResult {
        let success: Bool
        let actualHopCount: Int
        let finalDeliveryStatus: MessageDeliveryStatus
        let hopPath: [Data]
        let multiHopProtocolCompliant: Bool
        let pathDiscoverySuccessful: Bool
    }

    struct ConcurrentMessagingResult {
        let totalAttempted: Int
        let totalSuccessful: Int
        let totalFailed: Int
        let averageLatency: TimeInterval
    }

    struct OfflineMessagingResult {
        let messageId: String
        let deliveredImmediately: Bool
        let queuedForDelivery: Bool
        let queueTimestamp: Date?
    }

    struct MessageDeliveryResult {
        let delivered: Bool
        let deliveryLatency: TimeInterval
    }

    struct ComplianceValidationResult {
        let messageDelivered: Bool
        let protocolCompliant: Bool
        let commandPayloadCompliant: Bool
        let commandCode: UInt8
        let messageType: UInt8
        let messageEncodingCompliant: Bool
        let attempt: UInt8?
        let timestamp: UInt32?
        let recipientPublicKey: Data
        let retryLogicCompliant: Bool
        let maxAttemptsUsed: Int
        let floodAttemptsUsed: Int
        let ackHandlingCompliant: Bool
        let ackCode: UInt32?
        let ackReceivedAt: Date?
        let binaryProtocolSupported: Bool
        let protocolSteps: [String]
        let allStepsSuccessful: Bool
    }

    struct ContactSyncComplianceResult {
        let success: Bool
        let syncedContacts: Int
        let contactStructureCompliant: Bool
        let stringEncodingCompliant: Bool
        let pathDataCompliant: Bool
        let binaryProtocolCompliant: Bool
    }

    struct GroupChatResult {
        let success: Bool
        let totalMessages: Int
        let deliveredMessages: Int
        let totalDuration: TimeInterval
        let averageMessageLatency: TimeInterval
    }

    struct EmergencyBroadcastResult {
        let success: Bool
        let totalContacts: Int
        let deliveredContacts: Int
        let averageDeliveryTime: TimeInterval
        let priority: MessagePriority
        let floodModeUsed: Bool
        let floodScope: FloodScope
    }

    struct PoorConnectivityResult {
        let attemptedMessages: Int
        let deliveredMessages: Int
        let successRate: Double
        let retryStrategyUsed: Bool
        let floodModeEngaged: Bool
        let averageRetryCount: Double
        let maxLatencyObserved: TimeInterval
    }

    struct ErrorRecoveryResult {
        let success: Bool
        let errorScenario: String
        let recoveryAttempts: Int
        let finalState: String
    }

    struct ScaleResult {
        let attemptedMessages: Int
        let successfulMessages: Int
        let totalTime: TimeInterval
        let averageNetworkOverhead: Double
        let memoryUsageMB: Double
    }

    init(bleManager: MockBLEManager, modelContext: ModelContext) {
        self.bleManager = bleManager
        self.modelContext = modelContext
    }

    // MARK: - End-to-End Messaging Methods

    func sendEndToEndMessage(
        from sender: Device,
        to recipientPublicKey: Data,
        text: String,
        messageType: MessageType
    ) async throws -> EndToEndResult {
        // TODO: Implement complete end-to-end message sending
        return EndToEndResult(
            success: true,
            originalMessage: Message(
                text: text,
                recipientPublicKey: recipientPublicKey,
                deliveryStatus: .delivered,
                messageType: messageType
            ),
            finalDeliveryStatus: .delivered,
            deliveryTimestamp: Date(),
            protocolCompliant: true,
            properPayloadFormat: true,
            properRetryLogic: true,
            properAckHandling: true
        )
    }

    func sendEndToEndChannelMessage(
        from sender: Device,
        to channelId: String,
        text: String
    ) async throws -> ChannelEndToEndResult {
        // TODO: Implement end-to-end channel message sending
        return ChannelEndToEndResult(
            success: true,
            originalMessage: Message(
                text: text,
                recipientPublicKey: sender.publicKey,
                deliveryStatus: .delivered,
                messageType: .channel,
                channelId: channelId
            ),
            finalDeliveryStatus: .delivered,
            deliveredToMembers: 2,
            channelProtocolCompliant: true,
            properChannelEncryption: true
        )
    }

    func sendMultiHopMessage(
        from sender: Device,
        to recipientPublicKey: Data,
        text: String,
        expectedHops: Int
    ) async throws -> MultiHopResult {
        // TODO: Implement multi-hop message sending
        return MultiHopResult(
            success: true,
            actualHopCount: expectedHops,
            finalDeliveryStatus: .delivered,
            hopPath: [sender.publicKey, recipientPublicKey],
            multiHopProtocolCompliant: true,
            pathDiscoverySuccessful: true
        )
    }

    // MARK: - Configuration Methods

    func configureMeshTopology(
        source: Device,
        intermediate: [Device],
        destination: Device
    ) async throws {
        // TODO: Configure mesh topology for multi-hop testing
    }

    func establishFullMeshConnectivity(_ devices: [Device]) async throws {
        // TODO: Establish full mesh connectivity between devices
    }

    func createChannel(
        on device: Device,
        name: String,
        secret: String
    ) async throws -> Channel {
        // TODO: Create channel on device
        return try TestDataFactory.createTestChannel()
    }

    func joinChannel(on device: Device, channelHash: String) async throws {
        // TODO: Join channel on device
    }

    // MARK: - Data Access Methods

    func getMessagesForDevice(_ devicePublicKey: Data) throws -> [Message] {
        // TODO: Get messages for specific device
        return []
    }

    func getChannelMessagesForDevice(_ devicePublicKey: Data, channelId: String) throws -> [Message] {
        // TODO: Get channel messages for specific device
        return []
    }

    func getContactsForDevice(_ devicePublicKey: Data) throws -> [Contact] {
        // TODO: Get contacts for specific device
        return []
    }

    // MARK: - Simulation Methods

    func simulateAppRestart(on device: Device) async throws {
        // TODO: Simulate app restart
    }

    func simulateDeviceReconnection(_ device: Device) async throws {
        // TODO: Simulate device reconnection
    }

    func takeDeviceOffline(_ device: Device) async throws {
        // TODO: Take device offline
    }

    func bringDeviceOnline(_ device: Device) async throws {
        // TODO: Bring device online
    }

    func waitForMessageDelivery(messageId: String, timeout: TimeInterval) async throws -> MessageDeliveryResult {
        // TODO: Wait for message delivery
        return MessageDeliveryResult(delivered: true, deliveryLatency: 0.0)
    }

    // MARK: - Concurrent Messaging Methods

    func sendConcurrentMessages(
        devices: [Device],
        messagesPerDevice: Int
    ) async throws -> ConcurrentMessagingResult {
        // TODO: Send concurrent messages
        return ConcurrentMessagingResult(
            totalAttempted: devices.count * messagesPerDevice,
            totalSuccessful: devices.count * messagesPerDevice,
            totalFailed: 0,
            averageLatency: 0.1
        )
    }

    // MARK: - Protocol Compliance Methods

    func enableStrictProtocolComplianceValidation() async {
        // TODO: Enable strict protocol compliance validation
    }

    func sendEndToEndMessageWithComplianceValidation(
        from sender: Device,
        to recipientPublicKey: Data,
        text: String,
        messageType: MessageType
    ) async throws -> ComplianceValidationResult {
        // TODO: Send message with compliance validation
        return ComplianceValidationResult(
            messageDelivered: true,
            protocolCompliant: true,
            commandPayloadCompliant: true,
            commandCode: 0x02,
            messageType: 0x00,
            messageEncodingCompliant: true,
            attempt: 0,
            timestamp: 1234567890,
            recipientPublicKey: recipientPublicKey,
            retryLogicCompliant: true,
            maxAttemptsUsed: 1,
            floodAttemptsUsed: 0,
            ackHandlingCompliant: true,
            ackCode: 0x12345678,
            ackReceivedAt: Date(),
            binaryProtocolSupported: true,
            protocolSteps: ["encode", "send", "receive_ack"],
            allStepsSuccessful: true
        )
    }

    func syncContactsWithComplianceValidation(
        from source: Device,
        to destination: Device,
        contacts: [Contact]
    ) async throws -> ContactSyncComplianceResult {
        // TODO: Sync contacts with compliance validation
        return ContactSyncComplianceResult(
            success: true,
            syncedContacts: contacts.count,
            contactStructureCompliant: true,
            stringEncodingCompliant: true,
            pathDataCompliant: true,
            binaryProtocolCompliant: true
        )
    }

    // MARK: - Scenario Testing Methods

    func createGroupChannel(
        name: String,
        secret: String,
        participants: [Device]
    ) async throws -> Channel {
        // TODO: Create group channel
        return try TestDataFactory.createTestChannel()
    }

    func simulateGroupChat(
        channel: Channel,
        participants: [Device],
        messagesPerParticipant: Int
    ) async throws -> GroupChatResult {
        // TODO: Simulate group chat scenario
        return GroupChatResult(
            success: true,
            totalMessages: participants.count * messagesPerParticipant,
            deliveredMessages: participants.count * messagesPerParticipant,
            totalDuration: 30.0,
            averageMessageLatency: 0.5
        )
    }

    func sendEmergencyBroadcast(
        from sender: Device,
        message: String,
        contacts: [Contact],
        priority: Bool
    ) async throws -> EmergencyBroadcastResult {
        // TODO: Send emergency broadcast
        return EmergencyBroadcastResult(
            success: true,
            totalContacts: contacts.count,
            deliveredContacts: contacts.count,
            averageDeliveryTime: 0.5,
            priority: .high,
            floodModeUsed: true,
            floodScope: .global
        )
    }

    func configurePoorNetworkConditions(packetLoss: Double, latency: TimeInterval) async {
        // TODO: Configure poor network conditions
    }

    func sendMessagesUnderPoorConditions(
        from sender: Device,
        to recipientPublicKey: Data,
        messageCount: Int
    ) async throws -> PoorConnectivityResult {
        // TODO: Send messages under poor conditions
        return PoorConnectivityResult(
            attemptedMessages: messageCount,
            deliveredMessages: Int(Double(messageCount) * 0.8),
            successRate: 0.8,
            retryStrategyUsed: true,
            floodModeEngaged: true,
            averageRetryCount: 1.5,
            maxLatencyObserved: latency * 2
        )
    }

    func configureErrorScenario(_ scenario: String) async {
        // TODO: Configure error scenario
    }

    func sendEndToEndMessageWithErrorRecovery(
        from sender: Device,
        to recipientPublicKey: Data,
        text: String,
        errorScenario: String
    ) async throws -> ErrorRecoveryResult {
        // TODO: Send message with error recovery
        return ErrorRecoveryResult(
            success: true,
            errorScenario: errorScenario,
            recoveryAttempts: 1,
            finalState: "delivered"
        )
    }

    func resetErrorScenario() async {
        // TODO: Reset error scenario
    }

    func getErrorHandlingStatistics() async -> ErrorHandlingStats {
        // TODO: Get error handling statistics
        return ErrorHandlingStats(
            totalErrors: 10,
            successfulRecoveries: 8,
            recoveryRate: 0.8
        )
    }

    func establishMeshNetwork(devices: [Device]) async throws {
        // TODO: Establish mesh network
    }

    func sendMessagesAtScale(
        devices: [Device],
        messagesPerDevice: Int
    ) async throws -> ScaleResult {
        // TODO: Send messages at scale
        return ScaleResult(
            attemptedMessages: devices.count * messagesPerDevice,
            successfulMessages: devices.count * messagesPerDevice,
            totalTime: 30.0,
            averageNetworkOverhead: 0.2,
            memoryUsageMB: 100.0
        )
    }

    // MARK: - Cleanup Methods

    func cleanup() async {
        // TODO: Clean up test resources and simulations
    }
}

// MARK: - Supporting Types

enum MessageDeliveryStatus {
    case sending
    case sent
    case delivered
    case failed
}

enum MessageType {
    case direct
    case channel
}

enum MessagePriority {
    case low
    case normal
    case high
}

enum FloodScope {
    case none
    case local
    case regional
    case global
}

struct ErrorHandlingStats {
    let totalErrors: Int
    let successfulRecoveries: Int
    let recoveryRate: Double
}