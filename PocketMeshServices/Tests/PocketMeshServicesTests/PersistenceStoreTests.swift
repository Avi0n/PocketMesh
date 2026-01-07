import Foundation
import SwiftData
import Testing
import MeshCore
@testable import PocketMeshServices

@Suite("PersistenceStore Tests")
struct PersistenceStoreTests {

    // MARK: - Test Helpers

    private func createTestStore() async throws -> PersistenceStore {
        let container = try PersistenceStore.createContainer(inMemory: true)
        return PersistenceStore(modelContainer: container)
    }

    private func createTestDevice(id: UUID = UUID()) -> DeviceDTO {
        DeviceDTO(from: Device(
            id: id,
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            nodeName: "TestDevice",
            firmwareVersion: 8,
            firmwareVersionString: "v1.11.0",
            manufacturerName: "TestMfg",
            buildDate: "06 Dec 2025",
            maxContacts: 100,
            maxChannels: 8,
            frequency: 915_000,
            bandwidth: 250_000,
            spreadingFactor: 10,
            codingRate: 5,
            txPower: 20,
            maxTxPower: 20,
            latitude: 37.7749,
            longitude: -122.4194,
            blePin: 0,
            manualAddContacts: false,
            multiAcks: 0,
            telemetryModeBase: 2,
            telemetryModeLoc: 0,
            telemetryModeEnv: 0,
            advertLocationPolicy: 0,
            lastConnected: Date(),
            lastContactSync: 0,
            isActive: false
        ))
    }

    private func createTestContactFrame(name: String = "TestContact") -> ContactFrame {
        ContactFrame(
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            type: .chat,
            flags: 0,
            outPathLength: 2,
            outPath: Data([0x01, 0x02]),
            name: name,
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
    }

    // MARK: - Device Tests

    @Test("Save and fetch device")
    func saveAndFetchDevice() async throws {
        let store = try await createTestStore()
        let deviceDTO = createTestDevice()

        try await store.saveDevice(deviceDTO)

        let fetched = try await store.fetchDevice(id: deviceDTO.id)
        #expect(fetched != nil)
        #expect(fetched?.nodeName == "TestDevice")
        #expect(fetched?.firmwareVersion == 8)
        #expect(fetched?.frequency == 915_000)
    }

    @Test("Fetch all devices")
    func fetchAllDevices() async throws {
        let store = try await createTestStore()

        let device1 = createTestDevice()
        let device2 = createTestDevice()

        try await store.saveDevice(device1)
        try await store.saveDevice(device2)

        let devices = try await store.fetchDevices()
        #expect(devices.count == 2)
    }

    @Test("Set active device")
    func setActiveDevice() async throws {
        let store = try await createTestStore()

        let device1 = createTestDevice()
        let device2 = createTestDevice()

        try await store.saveDevice(device1)
        try await store.saveDevice(device2)

        try await store.setActiveDevice(id: device1.id)

        let active = try await store.fetchActiveDevice()
        #expect(active?.id == device1.id)
        #expect(active?.isActive == true)

        // Now set device2 as active
        try await store.setActiveDevice(id: device2.id)

        let newActive = try await store.fetchActiveDevice()
        #expect(newActive?.id == device2.id)

        // Verify device1 is no longer active
        let device1Fetched = try await store.fetchDevice(id: device1.id)
        #expect(device1Fetched?.isActive == false)
    }

    @Test("Delete device cascades to contacts and messages")
    func deleteDeviceCascade() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()

        try await store.saveDevice(device)

        // Add a contact
        let contactFrame = createTestContactFrame()
        let contactID = try await store.saveContact(deviceID: device.id, from: contactFrame)

        // Add a message
        let message = MessageDTO(from: Message(
            deviceID: device.id,
            contactID: contactID,
            text: "Hello!",
            timestamp: UInt32(Date().timeIntervalSince1970)
        ))
        try await store.saveMessage(message)

        // Add a channel
        let channelInfo = ChannelInfo(index: 1, name: "Private", secret: Data(repeating: 0x42, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: channelInfo)

        // Verify data exists
        var contacts = try await store.fetchContacts(deviceID: device.id)
        #expect(contacts.count == 1)

        var channels = try await store.fetchChannels(deviceID: device.id)
        #expect(channels.count == 1)

        // Delete device
        try await store.deleteDevice(id: device.id)

        // Verify all data is gone
        contacts = try await store.fetchContacts(deviceID: device.id)
        #expect(contacts.isEmpty)

        channels = try await store.fetchChannels(deviceID: device.id)
        #expect(channels.isEmpty)

        let deletedDevice = try await store.fetchDevice(id: device.id)
        #expect(deletedDevice == nil)
    }

    // MARK: - Contact Tests

    @Test("Save and fetch contact from frame")
    func saveAndFetchContactFromFrame() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame(name: "Alice")
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        let contact = try await store.fetchContact(id: contactID)
        #expect(contact != nil)
        #expect(contact?.name == "Alice")
        #expect(contact?.type == .chat)
    }

    @Test("Fetch contact by public key")
    func fetchContactByPublicKey() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame(name: "Bob")
        _ = try await store.saveContact(deviceID: device.id, from: frame)

        let contact = try await store.fetchContact(deviceID: device.id, publicKey: frame.publicKey)
        #expect(contact != nil)
        #expect(contact?.name == "Bob")
    }

    @Test("Update contact last message and unread count")
    func updateContactLastMessageAndUnread() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame()
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        let now = Date()
        try await store.updateContactLastMessage(contactID: contactID, date: now)
        try await store.incrementUnreadCount(contactID: contactID)
        try await store.incrementUnreadCount(contactID: contactID)

        var contact = try await store.fetchContact(id: contactID)
        #expect(contact?.unreadCount == 2)
        #expect(contact?.lastMessageDate != nil)

        try await store.clearUnreadCount(contactID: contactID)

        contact = try await store.fetchContact(id: contactID)
        #expect(contact?.unreadCount == 0)
    }

    @Test("deleteMessagesForContact removes all messages for a contact")
    func deleteMessagesForContactRemovesAll() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        // Create first contact
        let frame1 = createTestContactFrame(name: "Contact1")
        let contact1ID = try await store.saveContact(deviceID: device.id, from: frame1)

        // Create multiple messages for this contact
        for i in 0..<5 {
            let message = MessageDTO(from: Message(
                deviceID: device.id,
                contactID: contact1ID,
                text: "Message \(i)",
                timestamp: UInt32(Date().timeIntervalSince1970) + UInt32(i)
            ))
            try await store.saveMessage(message)
        }

        // Create a second contact with a message (should not be deleted)
        let frame2 = createTestContactFrame(name: "Contact2")
        let contact2ID = try await store.saveContact(deviceID: device.id, from: frame2)
        let otherMessage = MessageDTO(from: Message(
            deviceID: device.id,
            contactID: contact2ID,
            text: "Other message",
            timestamp: UInt32(Date().timeIntervalSince1970) + 100
        ))
        try await store.saveMessage(otherMessage)

        // Verify messages exist before deletion
        var contact1Messages = try await store.fetchMessages(contactID: contact1ID)
        #expect(contact1Messages.count == 5)

        var contact2Messages = try await store.fetchMessages(contactID: contact2ID)
        #expect(contact2Messages.count == 1)

        // Delete messages for the first contact
        try await store.deleteMessagesForContact(contactID: contact1ID)

        // Verify messages for deleted contact are gone
        contact1Messages = try await store.fetchMessages(contactID: contact1ID)
        #expect(contact1Messages.isEmpty)

        // Verify messages for other contact still exist
        contact2Messages = try await store.fetchMessages(contactID: contact2ID)
        #expect(contact2Messages.count == 1)
    }

    // MARK: - Message Tests

    @Test("Save and fetch messages for contact")
    func saveAndFetchMessagesForContact() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame()
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        // Save multiple messages
        for i in 0..<5 {
            let message = MessageDTO(from: Message(
                deviceID: device.id,
                contactID: contactID,
                text: "Message \(i)",
                timestamp: UInt32(Date().timeIntervalSince1970) + UInt32(i)
            ))
            try await store.saveMessage(message)
        }

        let messages = try await store.fetchMessages(contactID: contactID)
        #expect(messages.count == 5)
        // Messages should be in chronological order (oldest first)
        #expect(messages.first?.text == "Message 0")
        #expect(messages.last?.text == "Message 4")
    }

    @Test("Update message status")
    func updateMessageStatus() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame()
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        let message = MessageDTO(from: Message(
            deviceID: device.id,
            contactID: contactID,
            text: "Test",
            statusRawValue: MessageStatus.pending.rawValue
        ))
        try await store.saveMessage(message)

        // Update status to sending
        try await store.updateMessageStatus(id: message.id, status: .sending)
        var fetched = try await store.fetchMessage(id: message.id)
        #expect(fetched?.status == .sending)

        // Update status to sent
        try await store.updateMessageStatus(id: message.id, status: .sent)
        fetched = try await store.fetchMessage(id: message.id)
        #expect(fetched?.status == .sent)
    }

    @Test("Update message by ACK code")
    func updateMessageByAckCode() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContactFrame()
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        let message = MessageDTO(from: Message(
            deviceID: device.id,
            contactID: contactID,
            text: "Test",
            statusRawValue: MessageStatus.sending.rawValue,
            ackCode: 12345
        ))
        try await store.saveMessage(message)

        // Simulate ACK received
        try await store.updateMessageByAckCode(12345, status: .delivered, roundTripTime: 250)

        let fetched = try await store.fetchMessage(id: message.id)
        #expect(fetched?.status == .delivered)
        #expect(fetched?.roundTripTime == 250)
    }

    // MARK: - Channel Tests

    @Test("Save and fetch channels")
    func saveAndFetchChannels() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        // Add public channel
        let publicChannel = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: publicChannel)

        // Add private channel
        let privateChannel = ChannelInfo(index: 1, name: "Private", secret: Data(repeating: 0x42, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: privateChannel)

        let channels = try await store.fetchChannels(deviceID: device.id)
        #expect(channels.count == 2)
        #expect(channels[0].index == 0)
        #expect(channels[0].name == "Public")
        #expect(channels[1].index == 1)
        #expect(channels[1].name == "Private")
    }

    // MARK: - RemoteNodeSession Tests

    private func createTestRoomSession(deviceID: UUID) -> RemoteNodeSessionDTO {
        RemoteNodeSessionDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            name: "TestRoom",
            role: .roomServer,
            latitude: 37.7749,
            longitude: -122.4194,
            isConnected: false,
            permissionLevel: .guest,
            lastSyncTimestamp: 0
        )
    }

    @Test("Save and fetch remote node session")
    func saveAndFetchRemoteNodeSession() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let session = createTestRoomSession(deviceID: device.id)
        try await store.saveRemoteNodeSessionDTO(session)

        let fetched = try await store.fetchRemoteNodeSession(id: session.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "TestRoom")
        #expect(fetched?.role == .roomServer)
    }

    @Test("Update room last sync timestamp")
    func updateRoomLastSyncTimestamp() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let session = createTestRoomSession(deviceID: device.id)
        try await store.saveRemoteNodeSessionDTO(session)

        // Update timestamp to 1000
        try await store.updateRoomLastSyncTimestamp(session.id, timestamp: 1000)

        var fetched = try await store.fetchRemoteNodeSession(id: session.id)
        #expect(fetched?.lastSyncTimestamp == 1000)

        // Update to higher timestamp
        try await store.updateRoomLastSyncTimestamp(session.id, timestamp: 2000)

        fetched = try await store.fetchRemoteNodeSession(id: session.id)
        #expect(fetched?.lastSyncTimestamp == 2000)
    }

    @Test("Update room last sync timestamp ignores older values")
    func updateRoomLastSyncTimestampIgnoresOlder() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let session = createTestRoomSession(deviceID: device.id)
        try await store.saveRemoteNodeSessionDTO(session)

        // Set initial timestamp
        try await store.updateRoomLastSyncTimestamp(session.id, timestamp: 5000)

        var fetched = try await store.fetchRemoteNodeSession(id: session.id)
        #expect(fetched?.lastSyncTimestamp == 5000)

        // Try to update with older timestamp - should be ignored
        try await store.updateRoomLastSyncTimestamp(session.id, timestamp: 3000)

        fetched = try await store.fetchRemoteNodeSession(id: session.id)
        #expect(fetched?.lastSyncTimestamp == 5000)  // Should still be 5000
    }

    // MARK: - RoomMessage Tests

    @Test("Save and fetch room messages")
    func saveAndFetchRoomMessages() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let session = createTestRoomSession(deviceID: device.id)
        try await store.saveRemoteNodeSessionDTO(session)

        // Save room messages
        for i in 0..<3 {
            let message = RoomMessageDTO(
                sessionID: session.id,
                authorKeyPrefix: Data([0x01, 0x02, 0x03, 0x04]),
                authorName: "Author\(i)",
                text: "Room message \(i)",
                timestamp: UInt32(Date().timeIntervalSince1970) + UInt32(i)
            )
            try await store.saveRoomMessage(message)
        }

        let messages = try await store.fetchRoomMessages(sessionID: session.id)
        #expect(messages.count == 3)
    }

    @Test("Room message deduplication")
    func roomMessageDeduplication() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let session = createTestRoomSession(deviceID: device.id)
        try await store.saveRemoteNodeSessionDTO(session)

        let timestamp = UInt32(Date().timeIntervalSince1970)
        let authorKeyPrefix = Data([0x01, 0x02, 0x03, 0x04])
        let text = "Duplicate message"

        // Save message
        let message1 = RoomMessageDTO(
            sessionID: session.id,
            authorKeyPrefix: authorKeyPrefix,
            text: text,
            timestamp: timestamp
        )
        try await store.saveRoomMessage(message1)

        // Try to save duplicate (same timestamp, author, and content hash)
        let message2 = RoomMessageDTO(
            sessionID: session.id,
            authorKeyPrefix: authorKeyPrefix,
            text: text,
            timestamp: timestamp
        )
        try await store.saveRoomMessage(message2)

        // Should only have one message
        let messages = try await store.fetchRoomMessages(sessionID: session.id)
        #expect(messages.count == 1)
    }

    // MARK: - Badge Count Tests

    @Test("Get total unread counts")
    func getTotalUnreadCounts() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        // Create contacts with unread messages
        let frame1 = createTestContactFrame(name: "Contact1")
        let contact1ID = try await store.saveContact(deviceID: device.id, from: frame1)
        try await store.incrementUnreadCount(contactID: contact1ID)
        try await store.incrementUnreadCount(contactID: contact1ID)

        let frame2 = createTestContactFrame(name: "Contact2")
        let contact2ID = try await store.saveContact(deviceID: device.id, from: frame2)
        try await store.incrementUnreadCount(contactID: contact2ID)

        // Create channel with unread messages
        let channelInfo = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        let channelID = try await store.saveChannel(deviceID: device.id, from: channelInfo)
        try await store.incrementChannelUnreadCount(channelID: channelID)
        try await store.incrementChannelUnreadCount(channelID: channelID)
        try await store.incrementChannelUnreadCount(channelID: channelID)

        let (contacts, channels) = try await store.getTotalUnreadCounts()
        #expect(contacts == 3)  // 2 + 1
        #expect(channels == 3)
    }

    // MARK: - Warm-up Test

    @Test("Database warm-up")
    func databaseWarmUp() async throws {
        let store = try await createTestStore()

        // Should not throw
        try await store.warmUp()
    }

    // MARK: - RxLogEntry Tests

    private func createTestRxLogEntryDTO(
        deviceID: UUID,
        senderTimestamp: UInt32? = nil
    ) -> RxLogEntryDTO {
        // Create minimal ParsedRxLogData for the DTO
        let parsed = ParsedRxLogData(
            snr: 10.5,
            rssi: -65,
            rawPayload: Data([0x15, 0x01, 0x02, 0x03]),
            routeType: .flood,
            payloadType: .groupText,
            payloadVersion: 0,
            transportCode: nil,
            pathLength: 1,
            pathNodes: [0x42],
            packetPayload: Data([0xAB, 0xCD, 0xEF])
        )

        return RxLogEntryDTO(
            deviceID: deviceID,
            from: parsed,
            channelHash: 1,
            channelName: "TestChannel",
            decryptStatus: .success,
            senderTimestamp: senderTimestamp,
            decodedText: "Hello mesh!"
        )
    }

    @Test("Save and fetch RxLogEntry preserves senderTimestamp")
    func saveAndFetchRxLogEntryPreservesSenderTimestamp() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let expectedTimestamp: UInt32 = 1703123456
        let dto = createTestRxLogEntryDTO(deviceID: device.id, senderTimestamp: expectedTimestamp)

        try await store.saveRxLogEntry(dto)

        let entries = try await store.fetchRxLogEntries(deviceID: device.id)
        #expect(entries.count == 1)
        #expect(entries.first?.senderTimestamp == expectedTimestamp)
    }

    @Test("Save and fetch RxLogEntry with nil senderTimestamp")
    func saveAndFetchRxLogEntryWithNilTimestamp() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let dto = createTestRxLogEntryDTO(deviceID: device.id, senderTimestamp: nil)

        try await store.saveRxLogEntry(dto)

        let entries = try await store.fetchRxLogEntries(deviceID: device.id)
        #expect(entries.count == 1)
        #expect(entries.first?.senderTimestamp == nil)
    }

    @Test("RxLogEntryDTO init from model preserves senderTimestamp")
    func rxLogEntryDTOInitFromModelPreservesTimestamp() async throws {
        let store = try await createTestStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        // Save with timestamp
        let expectedTimestamp: UInt32 = 1703123456
        let dto = createTestRxLogEntryDTO(deviceID: device.id, senderTimestamp: expectedTimestamp)
        try await store.saveRxLogEntry(dto)

        // Fetch back (this uses RxLogEntryDTO.init(from: RxLogEntry))
        let entries = try await store.fetchRxLogEntries(deviceID: device.id)
        #expect(entries.first?.senderTimestamp == expectedTimestamp)

        // Verify the conversion handles the Int -> UInt32 correctly
        // The model stores Int, DTO uses UInt32
        #expect(entries.first?.senderTimestamp == 1703123456)
    }
}
