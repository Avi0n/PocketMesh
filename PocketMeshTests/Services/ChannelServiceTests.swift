import XCTest
import SwiftData
import CryptoKit
@testable import PocketMesh
@testable import PocketMeshKit

/// Tests ChannelService integration with MockBLERadio against CORRECT MeshCore specification
///
/// IMPORTANT: These tests validate against the CORRECT MeshCore specification as implemented
/// in the official Python client, not the current (incorrect) PocketMesh implementation.
/// Tests will FAIL until PocketMesh is fixed to match the specification.
@MainActor
final class ChannelServiceTests: BaseTestCase {

    var channelService: ChannelService!
    var testDevice: Device!
    var testContact: Contact!
    var testChannel: Channel!

    override func setUp() async throws {
        try await super.setUp()

        // Create test device and contact
        testDevice = try TestDataFactory.createTestDevice()
        testContact = try TestDataFactory.createTestContact()

        // Create test channel
        testChannel = try TestDataFactory.createTestChannel()

        // Save to SwiftData context
        modelContext.insert(testDevice)
        modelContext.insert(testContact)
        modelContext.insert(testChannel)
        try modelContext.save()

        // Initialize ChannelService with mock BLE manager
        channelService = ChannelService(
            bleManager: mockBLEManager,
            modelContext: modelContext
        )
    }

    override func tearDown() async throws {
        channelService = nil
        testDevice = nil
        testContact = nil
        testChannel = nil
        try await super.tearDown()
    }

    // MARK: - Channel Creation Tests

    func testCreateChannel_Success() async throws {
        // Given
        let channelName = "Test Channel"
        let secret = "test_secret_123"

        // When
        let createdChannel = try await channelService.createChannel(
            name: channelName,
            secret: secret
        )

        // Then
        XCTAssertNotNil(createdChannel)
        XCTAssertEqual(createdChannel.name, channelName)
        XCTAssertNotNil(createdChannel.hashedSecret)
        XCTAssertNotEqual(createdChannel.hashedSecret, secret) // Should be hashed
        XCTAssertEqual(createdChannel.createdBy, testDevice.publicKey)

        // Validate secret was hashed with SHA-256 as per MeshCore specification
        let expectedHash = SHA256.hash(data: Data(secret.utf8))
        let expectedHashString = expectedHash.compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(createdChannel.hashedSecret, expectedHashString)

        // Validate channel was saved to database
        let fetchDescriptor = FetchDescriptor<Channel>(
            predicate: #Predicate<Channel> { channel in
                channel.name == channelName
            }
        )
        let channels = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.hashedSecret, expectedHashString)
    }

    func testCreateChannel_HashedSecretSecurity() async throws {
        // Test that channel secrets are properly hashed for security
        // MeshCore specification requires SHA-256 hashing of channel secrets

        // Given
        let channelName = "Secure Channel"
        let secret = "super_secret_password_that_should_be_hashed"

        // When
        let createdChannel = try await channelService.createChannel(
            name: channelName,
            secret: secret
        )

        // Then - Secret should be hashed, not stored in plaintext
        XCTAssertNotEqual(createdChannel.hashedSecret, secret)
        XCTAssertEqual(createdChannel.hashedSecret.count, 64) // SHA-256 hex string length

        // Verify it's a valid SHA-256 hash
        let hashData = Data(createdChannel.hashedSecret.utf8)
        XCTAssertEqual(hashData.count, 64) // 32 bytes * 2 hex chars = 64 chars

        // Validate deterministic hashing
        let secondChannel = try await channelService.createChannel(
            name: "Another Channel",
            secret: secret
        )
        XCTAssertEqual(createdChannel.hashedSecret, secondChannel.hashedSecret) // Same secret = same hash
    }

    func testCreateChannel_MaxSlots() async throws {
        // Test that ChannelService respects maximum slot limit (8 channels per spec)
        // MeshCore specification: Maximum 8 channel slots

        // Given - Create 8 channels (maximum allowed)
        var createdChannels: [Channel] = []
        for i in 1...8 {
            let channel = try await channelService.createChannel(
                name: "Channel \(i)",
                secret: "secret_\(i)"
            )
            createdChannels.append(channel)
        }

        XCTAssertEqual(createdChannels.count, 8)

        // When - Try to create 9th channel (should fail)
        do {
            let _ = try await channelService.createChannel(
                name: "Channel 9",
                secret: "secret_9"
            )
            XCTFail("Creating 9th channel should fail due to slot limit")
        } catch {
            // Expected - should throw slot limit error
            XCTAssertTrue(error.localizedDescription.contains("slot") || error.localizedDescription.contains("maximum"))
        }
    }

    func testCreateChannel_SlotReuse() async throws {
        // Test that deleted channel slots can be reused
        // MeshCore specification should allow slot reuse after deletion

        // Given - Create maximum channels
        var createdChannels: [Channel] = []
        for i in 1...8 {
            let channel = try await channelService.createChannel(
                name: "Channel \(i)",
                secret: "secret_\(i)"
            )
            createdChannels.append(channel)
        }

        // When - Delete one channel and create a new one
        let channelToDelete = createdChannels.first!
        modelContext.delete(channelToDelete)
        try modelContext.save()

        // Should be able to create new channel now
        let newChannel = try await channelService.createChannel(
            name: "New Channel",
            secret: "new_secret"
        )

        // Then - New channel should be created successfully
        XCTAssertNotNil(newChannel)
        XCTAssertEqual(newChannel.name, "New Channel")

        // Total channel count should still be 8
        let finalCount = try modelContext.fetchCount(FetchDescriptor<Channel>())
        XCTAssertEqual(finalCount, 8)
    }

    // MARK: - Channel Joining Tests

    func testJoinChannel_Success() async throws {
        // Given
        let channelName = "Joinable Channel"
        let secret = "join_secret"
        let creatorChannel = try await channelService.createChannel(
            name: channelName,
            secret: secret
        )

        // When - Another device joins the channel
        let joinedChannel = try await channelService.joinChannel(
            hashedSecret: creatorChannel.hashedSecret,
            name: channelName
        )

        // Then
        XCTAssertNotNil(joinedChannel)
        XCTAssertEqual(joinedChannel.hashedSecret, creatorChannel.hashedSecret)
        XCTAssertEqual(joinedChannel.name, channelName)
        XCTAssertNotEqual(joinedChannel.id, creatorChannel.id) // Should be different channel entry for each device

        // Validate both channels exist in database
        let fetchDescriptor = FetchDescriptor<Channel>(
            predicate: #Predicate<Channel> { channel in
                channel.hashedSecret == creatorChannel.hashedSecret
            }
        )
        let channels = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(channels.count, 2) // Creator + Joiner
    }

    func testJoinChannel_WrongSecret() async throws {
        // Given
        let correctSecret = "correct_secret"
        let wrongSecret = "wrong_secret"

        let correctChannel = try await channelService.createChannel(
            name: "Protected Channel",
            secret: correctSecret
        )

        // When - Try to join with wrong secret
        let wrongHash = SHA256.hash(data: Data(wrongSecret.utf8))
        let wrongHashString = wrongHash.compactMap { String(format: "%02x", $0) }.joined()

        do {
            let _ = try await channelService.joinChannel(
                hashedSecret: wrongHashString,
                name: "Protected Channel"
            )
            XCTFail("Joining channel with wrong secret should fail")
        } catch {
            // Expected - should throw authentication error
            XCTAssertTrue(error.localizedDescription.contains("secret") || error.localizedDescription.contains("auth"))
        }
    }

    // MARK: - Channel Leaving Tests

    func testLeaveChannel_Success() async throws {
        // Given
        let channel = try await channelService.createChannel(
            name: "Leavable Channel",
            secret: "leave_secret"
        )

        // Ensure channel exists
        let initialCount = try modelContext.fetchCount(FetchDescriptor<Channel>())
        XCTAssertGreaterThanOrEqual(initialCount, 1)

        // When
        try await channelService.leaveChannel(channelId: channel.id)

        // Then
        let fetchDescriptor = FetchDescriptor<Channel>(
            predicate: #Predicate<Channel> { ch in
                ch.id == channel.id
            }
        )
        let channels = try modelContext.fetch(fetchDescriptor)
        XCTAssertTrue(channels.isEmpty)

        let finalCount = try modelContext.fetchCount(FetchDescriptor<Channel>())
        XCTAssertEqual(finalCount, initialCount - 1)
    }

    func testLeaveChannel_NonExistent() async throws {
        // Given
        let nonExistentChannelId = "non_existent_channel"

        // When/Then - Should handle gracefully
        do {
            try await channelService.leaveChannel(channelId: nonExistentChannelId)
            XCTFail("Leaving non-existent channel should throw error")
        } catch {
            // Expected - should throw not found error
            XCTAssertTrue(error.localizedDescription.contains("not found") || error.localizedDescription.contains("channel"))
        }
    }

    // MARK: - Channel Message Tests

    func testSendChannelMessage_Success() async throws {
        // Given
        let messageText = "Hello channel!"
        let channel = try await channelService.createChannel(
            name: "Message Channel",
            secret: "message_secret"
        )

        // When
        let sentMessage = try await channelService.sendChannelMessage(
            text: messageText,
            channelId: channel.id
        )

        // Then
        XCTAssertNotNil(sentMessage)
        XCTAssertEqual(sentMessage.text, messageText)
        XCTAssertEqual(sentMessage.channelId, channel.id)
        XCTAssertEqual(sentMessage.messageType, .channel)
        XCTAssertEqual(sentMessage.deliveryStatus, .sent)

        // Validate message was saved to database
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.channelId == channel.id && message.text == messageText
            }
        )
        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, 1)
    }

    func testSendChannelMessage_LengthValidation() async throws {
        // Test channel message length validation
        // MeshCore specification may have message length limits

        // Given
        let channel = try await channelService.createChannel(
            name: "Length Test Channel",
            secret: "length_secret"
        )

        // When - Send very long message
        let longMessage = String(repeating: "This is a very long channel message. ", count: 100)

        do {
            let sentMessage = try await channelService.sendChannelMessage(
                text: longMessage,
                channelId: channel.id
            )

            // Then - Should handle with proper fragmentation
            XCTAssertNotNil(sentMessage)
            XCTAssertEqual(sentMessage.text, longMessage)

        } catch {
            // Or reject if exceeds maximum length
            XCTAssertTrue(error.localizedDescription.contains("length") || error.localizedDescription.contains("too long"))
        }
    }

    func testSendChannelMessage_NonExistentChannel() async throws {
        // Given
        let nonExistentChannelId = "non_existent_channel"
        let messageText = "Message to nowhere"

        // When/Then
        do {
            let _ = try await channelService.sendChannelMessage(
                text: messageText,
                channelId: nonExistentChannelId
            )
            XCTFail("Sending to non-existent channel should fail")
        } catch {
            // Expected - should throw not found error
            XCTAssertTrue(error.localizedDescription.contains("not found") || error.localizedDescription.contains("channel"))
        }
    }

    // MARK: - Channel List Tests

    func testGetJoinedChannels_Success() async throws {
        // Given
        let channel1 = try await channelService.createChannel(
            name: "Channel 1",
            secret: "secret1"
        )
        let channel2 = try await channelService.createChannel(
            name: "Channel 2",
            secret: "secret2"
        )

        // When
        let joinedChannels = try await channelService.getJoinedChannels()

        // Then
        XCTAssertGreaterThanOrEqual(joinedChannels.count, 2)
        XCTAssertTrue(joinedChannels.contains { $0.id == channel1.id })
        XCTAssertTrue(joinedChannels.contains { $0.id == channel2.id })
    }

    func testGetJoinedChannels_Empty() async throws {
        // Given - Remove all existing channels
        let allChannels = try modelContext.fetch(FetchDescriptor<Channel>())
        for channel in allChannels {
            modelContext.delete(channel)
        }
        try modelContext.save()

        // When
        let joinedChannels = try await channelService.getJoinedChannels()

        // Then
        XCTAssertTrue(joinedChannels.isEmpty)
    }

    // MARK: - Channel Metadata Tests

    func testUpdateChannelLastMessageDate() async throws {
        // Test that lastMessageDate is updated when messages are sent

        // Given
        let channel = try await channelService.createChannel(
            name: "Timestamp Test Channel",
            secret: "timestamp_secret"
        )

        let initialLastMessageDate = channel.lastMessageDate

        // Wait a bit to ensure different timestamp
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // When
        let messageText = "Timestamp test message"
        let _ = try await channelService.sendChannelMessage(
            text: messageText,
            channelId: channel.id
        )

        // Then
        let fetchDescriptor = FetchDescriptor<Channel>(
            predicate: #Predicate<Channel> { ch in
                ch.id == channel.id
            }
        )
        let updatedChannels = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(updatedChannels.count, 1)

        let updatedChannel = updatedChannels.first!
        XCTAssertNotNil(updatedChannel.lastMessageDate)
        if let initialDate = initialLastMessageDate, let updatedDate = updatedChannel.lastMessageDate {
            XCTAssertGreaterThan(updatedDate, initialDate)
        }
    }

    func testChannelSorting_ByLastMessageDate() async throws {
        // Test that channels are properly sorted by lastMessageDate

        // Given
        let channel1 = try await channelService.createChannel(
            name: "First Channel",
            secret: "secret1"
        )

        // Wait and send message to channel 1
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        let _ = try await channelService.sendChannelMessage(
            text: "Message 1",
            channelId: channel1.id
        )

        let channel2 = try await channelService.createChannel(
            name: "Second Channel",
            secret: "secret2"
        )

        // Wait and send message to channel 2
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        let _ = try await channelService.sendChannelMessage(
            text: "Message 2",
            channelId: channel2.id
        )

        // When
        let joinedChannels = try await channelService.getJoinedChannels()

        // Then - Should be sorted by lastMessageDate (most recent first)
        guard joinedChannels.count >= 2 else {
            XCTFail("Should have at least 2 channels")
            return
        }

        // Find our test channels in the sorted list
        let sortedChannel1 = joinedChannels.first { $0.id == channel1.id }
        let sortedChannel2 = joinedChannels.first { $0.id == channel2.id }

        XCTAssertNotNil(sortedChannel1)
        XCTAssertNotNil(sortedChannel2)

        // Channel 2 should appear before Channel 1 (more recent message)
        let channel1Index = joinedChannels.firstIndex { $0.id == channel1.id }!
        let channel2Index = joinedChannels.firstIndex { $0.id == channel2.id }!
        XCTAssertLessThan(channel2Index, channel1Index)
    }

    // MARK: - Multi-Device Isolation Tests

    func testChannelDeviceIsolation() async throws {
        // Test that channels are properly isolated per device
        // Each device should have its own channel entries

        // Given
        let channelName = "Multi-Device Channel"
        let secret = "multi_device_secret"

        // Device 1 creates channel
        let device1Channel = try await channelService.createChannel(
            name: channelName,
            secret: secret
        )

        // Simulate Device 2 joining same channel
        let device2Channel = try await channelService.joinChannel(
            hashedSecret: device1Channel.hashedSecret,
            name: channelName
        )

        // When - Get channels for current device
        let currentDeviceChannels = try await channelService.getJoinedChannels()

        // Then
        // Should have separate channel entries for each device
        XCTAssertNotEqual(device1Channel.id, device2Channel.id)
        XCTAssertEqual(device1Channel.hashedSecret, device2Channel.hashedSecret) // Same channel content

        // Current device should see its channel entry
        XCTAssertTrue(currentDeviceChannels.contains { $0.id == device1Channel.id })

        // Validate both channels exist in database
        let fetchDescriptor = FetchDescriptor<Channel>(
            predicate: #Predicate<Channel> { channel in
                channel.hashedSecret == device1Channel.hashedSecret
            }
        )
        let allChannels = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(allChannels.count, 2) // Both device entries
    }

    // MARK: - Channel Failure Handling Tests

    func testChannelCreation_Failure() async throws {
        // Test channel creation failure scenarios

        // Given
        let channelName = ""
        let secret = "test_secret" // Empty name should fail

        // When/Then
        do {
            let _ = try await channelService.createChannel(
                name: channelName,
                secret: secret
            )
            XCTFail("Creating channel with empty name should fail")
        } catch {
            // Expected - should throw validation error
            XCTAssertTrue(error.localizedDescription.contains("name") || error.localizedDescription.contains("invalid"))
        }
    }

    func testChannelMessageSending_Failure() async throws {
        // Test channel message sending failure scenarios

        // Given
        let channel = try await channelService.createChannel(
            name: "Failure Test Channel",
            secret: "failure_secret"
        )

        // Configure mock to simulate send failure
        // TODO: Configure MockBLERadio to simulate send failures

        // When
        do {
            let _ = try await channelService.sendChannelMessage(
                text: "This should fail",
                channelId: channel.id
            )
            XCTFail("Message sending should fail with mock configuration")
        } catch {
            // Expected - should handle send failure appropriately
            XCTAssertNotNil(error)
        }

        // Then - Message should be saved with failed status
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.channelId == channel.id && message.deliveryStatus == .failed
            }
        )
        let failedMessages = try modelContext.fetch(fetchDescriptor)
        XCTAssertGreaterThan(failedMessages.count, 0)
    }

    // MARK: - MeshCore Protocol Compliance Tests

    func testChannelProtocol_SpecCompliance() async throws {
        // Test that ChannelService follows MeshCore specification exactly
        // This test documents current violations and required fixes

        // TODO: Validate that ChannelService:
        // 1. Uses correct channel message payload format
        // 2. Implements proper SHA-256 hashing for channel secrets
        // 3. Respects maximum channel slots (8) as per spec
        // 4. Handles channel joining with proper authentication
        // 5. Implements proper message routing for channels

        // Test channel secret hashing compliance
        let secret = "compliance_test_secret"
        let channel = try await channelService.createChannel(
            name: "Compliance Test Channel",
            secret: secret
        )

        // Validate SHA-256 hashing
        let expectedHash = SHA256.hash(data: Data(secret.utf8))
        let expectedHashString = expectedHash.compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(channel.hashedSecret, expectedHashString)

        // TODO: Add more comprehensive spec compliance validation
        XCTFail("TODO: Implement comprehensive MeshCore channel protocol compliance validation")
    }

    // MARK: - Performance Tests

    func testChannelPerformance_HighVolume() async throws {
        // Test ChannelService performance under high message volume

        // Given
        let channel = try await channelService.createChannel(
            name: "Performance Test Channel",
            secret: "performance_secret"
        )

        let highVolumeCount = 100
        let startTime = Date()

        // When
        for i in 0..<highVolumeCount {
            let _ = try await channelService.sendChannelMessage(
                text: "Performance test message \(i)",
                channelId: channel.id
            )
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then - Should handle high volume efficiently
        XCTAssertLessThan(duration, 30.0) // Should complete within 30 seconds
        XCTAssertLessThan(duration / Double(highVolumeCount), 0.5) // Average < 500ms per message

        // Validate all messages were saved
        let fetchDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.channelId == channel.id
            }
        )
        let messages = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(messages.count, highVolumeCount)
    }

    func testChannelListPerformance_LargeNumberOfChannels() async throws {
        // Test performance with large number of channels

        // Given
        let channelCount = 50
        var createdChannels: [Channel] = []

        let startTime = Date()

        // When
        for i in 0..<channelCount {
            let channel = try await channelService.createChannel(
                name: "Performance Channel \(i)",
                secret: "secret_\(i)"
            )
            createdChannels.append(channel)
        }

        // Get channel list
        let joinedChannels = try await channelService.getJoinedChannels()

        let duration = Date().timeIntervalSince(startTime)

        // Then - Should handle large number of channels efficiently
        XCTAssertLessThan(duration, 15.0) // Should complete within 15 seconds
        XCTAssertGreaterThanOrEqual(joinedChannels.count, channelCount)
    }
}