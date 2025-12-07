import Testing
import Foundation
import SwiftData
@testable import PocketMeshKit

@Suite("DataStore Integration Tests")
struct DataStoreIntegrationTests {

    // MARK: - Test Helpers

    private func createTestDataStore() async throws -> PocketMeshKit.DataStore {
        let container = try PocketMeshKit.DataStore.createContainer(inMemory: true)
        return PocketMeshKit.DataStore(modelContainer: container)
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
            multiAcks: false,
            telemetryModeBase: 2,
            telemetryModeLoc: 0,
            telemetryModeEnv: 0,
            advertLocationPolicy: 0,
            lastConnected: Date(),
            lastContactSync: 0,
            isActive: false
        ))
    }

    private func createTestContact(deviceID: UUID, name: String = "TestContact") -> ContactFrame {
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
        let store = try await createTestDataStore()
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
        let store = try await createTestDataStore()

        let device1 = createTestDevice()
        let device2 = createTestDevice()

        try await store.saveDevice(device1)
        try await store.saveDevice(device2)

        let devices = try await store.fetchDevices()
        #expect(devices.count == 2)
    }

    @Test("Set active device")
    func setActiveDevice() async throws {
        let store = try await createTestDataStore()

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
        let store = try await createTestDataStore()
        let device = createTestDevice()

        try await store.saveDevice(device)

        // Add a contact
        let contactFrame = createTestContact(deviceID: device.id)
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
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id, name: "Alice")
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        let contact = try await store.fetchContact(id: contactID)
        #expect(contact != nil)
        #expect(contact?.name == "Alice")
        #expect(contact?.type == .chat)
    }

    @Test("Fetch contact by public key")
    func fetchContactByPublicKey() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id, name: "Bob")
        _ = try await store.saveContact(deviceID: device.id, from: frame)

        let contact = try await store.fetchContact(deviceID: device.id, publicKey: frame.publicKey)
        #expect(contact != nil)
        #expect(contact?.name == "Bob")
    }

    @Test("Fetch contact by public key prefix")
    func fetchContactByPublicKeyPrefix() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id, name: "Charlie")
        _ = try await store.saveContact(deviceID: device.id, from: frame)

        let prefix = frame.publicKey.prefix(6)
        let contact = try await store.fetchContact(deviceID: device.id, publicKeyPrefix: prefix)
        #expect(contact != nil)
        #expect(contact?.name == "Charlie")
    }

    @Test("Update contact from frame")
    func updateContactFromFrame() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame1 = createTestContact(deviceID: device.id, name: "OldName")
        let contactID = try await store.saveContact(deviceID: device.id, from: frame1)

        // Update with same public key but different name
        let frame2 = ContactFrame(
            publicKey: frame1.publicKey,
            type: .chat,
            flags: 0,
            outPathLength: 3,
            outPath: Data([0x01, 0x02, 0x03]),
            name: "NewName",
            lastAdvertTimestamp: frame1.lastAdvertTimestamp + 100,
            latitude: frame1.latitude,
            longitude: frame1.longitude,
            lastModified: frame1.lastModified + 100
        )
        _ = try await store.saveContact(deviceID: device.id, from: frame2)

        let contact = try await store.fetchContact(id: contactID)
        #expect(contact?.name == "NewName")
        #expect(contact?.outPathLength == 3)
    }

    @Test("Update contact last message and unread count")
    func updateContactLastMessageAndUnread() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id)
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

    @Test("Fetch conversations with messages")
    func fetchConversations() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        // Create contacts with and without messages
        let frame1 = createTestContact(deviceID: device.id, name: "WithMessages")
        let frame2 = createTestContact(deviceID: device.id, name: "NoMessages")

        let contact1ID = try await store.saveContact(deviceID: device.id, from: frame1)
        _ = try await store.saveContact(deviceID: device.id, from: frame2)

        // Set last message date for contact1
        try await store.updateContactLastMessage(contactID: contact1ID, date: Date())

        let conversations = try await store.fetchConversations(deviceID: device.id)
        #expect(conversations.count == 1)
        #expect(conversations.first?.name == "WithMessages")
    }

    // MARK: - Message Tests

    @Test("Save and fetch messages for contact")
    func saveAndFetchMessagesForContact() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id)
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
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id)
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
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id)
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

    @Test("Count pending messages")
    func countPendingMessages() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let frame = createTestContact(deviceID: device.id)
        let contactID = try await store.saveContact(deviceID: device.id, from: frame)

        // Add pending messages
        for i in 0..<3 {
            let message = MessageDTO(from: Message(
                deviceID: device.id,
                contactID: contactID,
                text: "Pending \(i)",
                statusRawValue: MessageStatus.pending.rawValue
            ))
            try await store.saveMessage(message)
        }

        // Add sent message
        let sentMessage = MessageDTO(from: Message(
            deviceID: device.id,
            contactID: contactID,
            text: "Sent",
            statusRawValue: MessageStatus.sent.rawValue
        ))
        try await store.saveMessage(sentMessage)

        let count = try await store.countPendingMessages(deviceID: device.id)
        #expect(count == 3)
    }

    // MARK: - Channel Tests

    @Test("Save and fetch channels")
    func saveAndFetchChannels() async throws {
        let store = try await createTestDataStore()
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

    @Test("Fetch channel by index")
    func fetchChannelByIndex() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let channelInfo = ChannelInfo(index: 3, name: "Channel3", secret: Data(repeating: 0x33, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: channelInfo)

        let channel = try await store.fetchChannel(deviceID: device.id, index: 3)
        #expect(channel != nil)
        #expect(channel?.name == "Channel3")
        #expect(channel?.index == 3)

        let notFound = try await store.fetchChannel(deviceID: device.id, index: 7)
        #expect(notFound == nil)
    }

    @Test("Update channel from info")
    func updateChannelFromInfo() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let original = ChannelInfo(index: 2, name: "Original", secret: Data(repeating: 0, count: 16))
        let channelID = try await store.saveChannel(deviceID: device.id, from: original)

        let updated = ChannelInfo(index: 2, name: "Updated", secret: Data(repeating: 0xFF, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: updated)

        let channel = try await store.fetchChannel(deviceID: device.id, index: 2)
        #expect(channel?.id == channelID)
        #expect(channel?.name == "Updated")
        #expect(channel?.secret == Data(repeating: 0xFF, count: 16))
    }

    @Test("Fetch messages for channel")
    func fetchMessagesForChannel() async throws {
        let store = try await createTestDataStore()
        let device = createTestDevice()
        try await store.saveDevice(device)

        let channelInfo = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        _ = try await store.saveChannel(deviceID: device.id, from: channelInfo)

        // Add channel messages
        for i in 0..<3 {
            let message = MessageDTO(from: Message(
                deviceID: device.id,
                channelIndex: 0,
                text: "Channel msg \(i)",
                timestamp: UInt32(Date().timeIntervalSince1970) + UInt32(i)
            ))
            try await store.saveMessage(message)
        }

        let messages = try await store.fetchMessages(deviceID: device.id, channelIndex: 0)
        #expect(messages.count == 3)
        #expect(messages.allSatisfy { $0.channelIndex == 0 })
    }
}
