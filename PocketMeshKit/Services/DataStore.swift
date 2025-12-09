import Foundation
import SwiftData

// MARK: - DataStore Errors

public enum DataStoreError: Error, Sendable {
    case deviceNotFound
    case contactNotFound
    case messageNotFound
    case channelNotFound
    case saveFailed(String)
    case fetchFailed(String)
    case invalidData
}

// MARK: - DataStore Actor

/// ModelActor for background SwiftData operations.
/// Provides per-device data isolation and thread-safe access.
@ModelActor
public actor DataStore {

    /// Shared schema for PocketMesh models
    public static let schema = Schema([
        Device.self,
        Contact.self,
        Message.self,
        Channel.self
    ])

    /// Creates a ModelContainer for the app
    public static func createContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Device Operations

    /// Fetch all devices
    public func fetchDevices() throws -> [DeviceDTO] {
        let descriptor = FetchDescriptor<Device>(
            sortBy: [SortDescriptor(\Device.lastConnected, order: .reverse)]
        )
        let devices = try modelContext.fetch(descriptor)
        return devices.map { DeviceDTO(from: $0) }
    }

    /// Fetch a device by ID
    public func fetchDevice(id: UUID) throws -> DeviceDTO? {
        let targetID = id
        let predicate = #Predicate<Device> { device in
            device.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { DeviceDTO(from: $0) }
    }

    /// Fetch the active device
    public func fetchActiveDevice() throws -> DeviceDTO? {
        let predicate = #Predicate<Device> { device in
            device.isActive == true
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { DeviceDTO(from: $0) }
    }

    /// Save or update a device
    public func saveDevice(_ dto: DeviceDTO) throws {
        let targetID = dto.id
        let predicate = #Predicate<Device> { device in
            device.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            existing.publicKey = dto.publicKey
            existing.nodeName = dto.nodeName
            existing.firmwareVersion = dto.firmwareVersion
            existing.firmwareVersionString = dto.firmwareVersionString
            existing.manufacturerName = dto.manufacturerName
            existing.buildDate = dto.buildDate
            existing.maxContacts = dto.maxContacts
            existing.maxChannels = dto.maxChannels
            existing.frequency = dto.frequency
            existing.bandwidth = dto.bandwidth
            existing.spreadingFactor = dto.spreadingFactor
            existing.codingRate = dto.codingRate
            existing.txPower = dto.txPower
            existing.maxTxPower = dto.maxTxPower
            existing.latitude = dto.latitude
            existing.longitude = dto.longitude
            existing.blePin = dto.blePin
            existing.manualAddContacts = dto.manualAddContacts
            existing.multiAcks = dto.multiAcks
            existing.telemetryModeBase = dto.telemetryModeBase
            existing.telemetryModeLoc = dto.telemetryModeLoc
            existing.telemetryModeEnv = dto.telemetryModeEnv
            existing.advertLocationPolicy = dto.advertLocationPolicy
            existing.lastConnected = dto.lastConnected
            existing.lastContactSync = dto.lastContactSync
            existing.isActive = dto.isActive
        } else {
            // Create new
            let device = Device(
                id: dto.id,
                publicKey: dto.publicKey,
                nodeName: dto.nodeName,
                firmwareVersion: dto.firmwareVersion,
                firmwareVersionString: dto.firmwareVersionString,
                manufacturerName: dto.manufacturerName,
                buildDate: dto.buildDate,
                maxContacts: dto.maxContacts,
                maxChannels: dto.maxChannels,
                frequency: dto.frequency,
                bandwidth: dto.bandwidth,
                spreadingFactor: dto.spreadingFactor,
                codingRate: dto.codingRate,
                txPower: dto.txPower,
                maxTxPower: dto.maxTxPower,
                latitude: dto.latitude,
                longitude: dto.longitude,
                blePin: dto.blePin,
                manualAddContacts: dto.manualAddContacts,
                multiAcks: dto.multiAcks,
                telemetryModeBase: dto.telemetryModeBase,
                telemetryModeLoc: dto.telemetryModeLoc,
                telemetryModeEnv: dto.telemetryModeEnv,
                advertLocationPolicy: dto.advertLocationPolicy,
                lastConnected: dto.lastConnected,
                lastContactSync: dto.lastContactSync,
                isActive: dto.isActive
            )
            modelContext.insert(device)
        }

        try modelContext.save()
    }

    /// Set a device as active (deactivates others)
    public func setActiveDevice(id: UUID) throws {
        // Deactivate all devices first
        let allDevices = try modelContext.fetch(FetchDescriptor<Device>())
        for device in allDevices {
            device.isActive = false
        }

        // Activate the specified device
        let targetID = id
        let predicate = #Predicate<Device> { device in
            device.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let device = try modelContext.fetch(descriptor).first {
            device.isActive = true
            device.lastConnected = Date()
        }

        try modelContext.save()
    }

    /// Delete a device and all its associated data
    public func deleteDevice(id: UUID) throws {
        let targetID = id

        // Delete associated contacts
        let contactPredicate = #Predicate<Contact> { contact in
            contact.deviceID == targetID
        }
        let contacts = try modelContext.fetch(FetchDescriptor(predicate: contactPredicate))
        for contact in contacts {
            modelContext.delete(contact)
        }

        // Delete associated messages
        let messagePredicate = #Predicate<Message> { message in
            message.deviceID == targetID
        }
        let messages = try modelContext.fetch(FetchDescriptor(predicate: messagePredicate))
        for message in messages {
            modelContext.delete(message)
        }

        // Delete associated channels
        let channelPredicate = #Predicate<Channel> { channel in
            channel.deviceID == targetID
        }
        let channels = try modelContext.fetch(FetchDescriptor(predicate: channelPredicate))
        for channel in channels {
            modelContext.delete(channel)
        }

        // Delete the device
        let devicePredicate = #Predicate<Device> { device in
            device.id == targetID
        }
        if let device = try modelContext.fetch(FetchDescriptor(predicate: devicePredicate)).first {
            modelContext.delete(device)
        }

        try modelContext.save()
    }

    // MARK: - Contact Operations

    /// Fetch all contacts for a device
    public func fetchContacts(deviceID: UUID) throws -> [ContactDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.name)]
        )
        let contacts = try modelContext.fetch(descriptor)
        return contacts.map { ContactDTO(from: $0) }
    }

    /// Fetch contacts with recent messages (for chat list)
    public func fetchConversations(deviceID: UUID) throws -> [ContactDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.lastMessageDate != nil
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\Contact.lastMessageDate, order: .reverse)]
        )
        let contacts = try modelContext.fetch(descriptor)
        return contacts.map { ContactDTO(from: $0) }
    }

    /// Fetch a contact by ID
    public func fetchContact(id: UUID) throws -> ContactDTO? {
        let targetID = id
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ContactDTO(from: $0) }
    }

    /// Fetch a contact by public key
    public func fetchContact(deviceID: UUID, publicKey: Data) throws -> ContactDTO? {
        let targetDeviceID = deviceID
        let targetKey = publicKey
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.publicKey == targetKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ContactDTO(from: $0) }
    }

    /// Fetch a contact by public key prefix (6 bytes)
    public func fetchContact(deviceID: UUID, publicKeyPrefix: Data) throws -> ContactDTO? {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID
        }
        let contacts = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        return contacts.first { $0.publicKey.prefix(6) == publicKeyPrefix }.map { ContactDTO(from: $0) }
    }

    /// Save or update a contact from a ContactFrame
    public func saveContact(deviceID: UUID, from frame: ContactFrame) throws -> UUID {
        let targetDeviceID = deviceID
        let targetKey = frame.publicKey
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.publicKey == targetKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let contact: Contact
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: frame)
            contact = existing
        } else {
            contact = Contact(deviceID: deviceID, from: frame)
            modelContext.insert(contact)
        }

        try modelContext.save()
        return contact.id
    }

    /// Save or update a contact from DTO
    public func saveContact(_ dto: ContactDTO) throws {
        let targetID = dto.id
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = dto.name
            existing.typeRawValue = dto.typeRawValue
            existing.flags = dto.flags
            existing.outPathLength = dto.outPathLength
            existing.outPath = dto.outPath
            existing.lastAdvertTimestamp = dto.lastAdvertTimestamp
            existing.latitude = dto.latitude
            existing.longitude = dto.longitude
            existing.lastModified = dto.lastModified
            existing.nickname = dto.nickname
            existing.isBlocked = dto.isBlocked
            existing.isFavorite = dto.isFavorite
            existing.lastMessageDate = dto.lastMessageDate
            existing.unreadCount = dto.unreadCount
        } else {
            let contact = Contact(
                id: dto.id,
                deviceID: dto.deviceID,
                publicKey: dto.publicKey,
                name: dto.name,
                typeRawValue: dto.typeRawValue,
                flags: dto.flags,
                outPathLength: dto.outPathLength,
                outPath: dto.outPath,
                lastAdvertTimestamp: dto.lastAdvertTimestamp,
                latitude: dto.latitude,
                longitude: dto.longitude,
                lastModified: dto.lastModified,
                nickname: dto.nickname,
                isBlocked: dto.isBlocked,
                isFavorite: dto.isFavorite,
                lastMessageDate: dto.lastMessageDate,
                unreadCount: dto.unreadCount
            )
            modelContext.insert(contact)
        }

        try modelContext.save()
    }

    /// Delete a contact
    public func deleteContact(id: UUID) throws {
        let targetID = id
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        if let contact = try modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
            modelContext.delete(contact)
            try modelContext.save()
        }
    }

    /// Update contact's last message info
    public func updateContactLastMessage(contactID: UUID, date: Date) throws {
        let targetID = contactID
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let contact = try modelContext.fetch(descriptor).first {
            contact.lastMessageDate = date
            try modelContext.save()
        }
    }

    /// Increment unread count for a contact
    public func incrementUnreadCount(contactID: UUID) throws {
        let targetID = contactID
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let contact = try modelContext.fetch(descriptor).first {
            contact.unreadCount += 1
            try modelContext.save()
        }
    }

    /// Clear unread count for a contact
    public func clearUnreadCount(contactID: UUID) throws {
        let targetID = contactID
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let contact = try modelContext.fetch(descriptor).first {
            contact.unreadCount = 0
            try modelContext.save()
        }
    }

    // MARK: - Message Operations

    /// Fetch messages for a contact
    public func fetchMessages(contactID: UUID, limit: Int = 50, offset: Int = 0) throws -> [MessageDTO] {
        let targetContactID: UUID? = contactID
        let predicate = #Predicate<Message> { message in
            message.contactID == targetContactID
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\Message.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        let messages = try modelContext.fetch(descriptor)
        return messages.reversed().map { MessageDTO(from: $0) }
    }

    /// Fetch messages for a channel
    public func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int = 50, offset: Int = 0) throws -> [MessageDTO] {
        let targetDeviceID = deviceID
        let targetChannelIndex: UInt8? = channelIndex
        let predicate = #Predicate<Message> { message in
            message.deviceID == targetDeviceID && message.channelIndex == targetChannelIndex
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\Message.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        let messages = try modelContext.fetch(descriptor)
        return messages.reversed().map { MessageDTO(from: $0) }
    }

    /// Fetch a message by ID
    public func fetchMessage(id: UUID) throws -> MessageDTO? {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { MessageDTO(from: $0) }
    }

    /// Fetch a message by ACK code
    public func fetchMessage(ackCode: UInt32) throws -> MessageDTO? {
        let targetAckCode: UInt32? = ackCode
        let predicate = #Predicate<Message> { message in
            message.ackCode == targetAckCode
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { MessageDTO(from: $0) }
    }

    /// Save a new message
    public func saveMessage(_ dto: MessageDTO) throws {
        let message = Message(
            id: dto.id,
            deviceID: dto.deviceID,
            contactID: dto.contactID,
            channelIndex: dto.channelIndex,
            text: dto.text,
            timestamp: dto.timestamp,
            createdAt: dto.createdAt,
            directionRawValue: dto.direction.rawValue,
            statusRawValue: dto.status.rawValue,
            textTypeRawValue: dto.textType.rawValue,
            ackCode: dto.ackCode,
            attemptCount: dto.attemptCount,
            pathLength: dto.pathLength,
            snr: dto.snr,
            senderKeyPrefix: dto.senderKeyPrefix,
            senderNodeName: dto.senderNodeName,
            isRead: dto.isRead,
            replyToID: dto.replyToID,
            roundTripTime: dto.roundTripTime,
            heardRepeats: dto.heardRepeats
        )
        modelContext.insert(message)
        try modelContext.save()
    }

    /// Update message status
    public func updateMessageStatus(id: UUID, status: MessageStatus) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.status = status
            try modelContext.save()
        }
    }

    /// Update message ACK info
    public func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32? = nil) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.ackCode = ackCode
            message.status = status
            message.roundTripTime = roundTripTime
            try modelContext.save()
        }
    }

    /// Update message status by ACK code
    public func updateMessageByAckCode(_ ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32? = nil) throws {
        let targetAckCode: UInt32? = ackCode
        let predicate = #Predicate<Message> { message in
            message.ackCode == targetAckCode
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.status = status
            message.roundTripTime = roundTripTime
            try modelContext.save()
        }
    }

    /// Mark a message as read
    public func markMessageAsRead(id: UUID) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.isRead = true
            try modelContext.save()
        }
    }

    /// Updates the heard repeats count for a message
    public func updateMessageHeardRepeats(id: UUID, heardRepeats: Int) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.heardRepeats = heardRepeats
            try modelContext.save()
        }
    }

    /// Delete a message
    public func deleteMessage(id: UUID) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        if let message = try modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
            modelContext.delete(message)
            try modelContext.save()
        }
    }

    /// Count pending messages for a device
    public func countPendingMessages(deviceID: UUID) throws -> Int {
        let targetDeviceID = deviceID
        let pendingStatus = MessageStatus.pending.rawValue
        let sendingStatus = MessageStatus.sending.rawValue
        let predicate = #Predicate<Message> { message in
            message.deviceID == targetDeviceID &&
            (message.statusRawValue == pendingStatus ||
             message.statusRawValue == sendingStatus)
        }
        return try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
    }

    // MARK: - Channel Operations

    /// Fetch all channels for a device
    public func fetchChannels(deviceID: UUID) throws -> [ChannelDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Channel> { channel in
            channel.deviceID == targetDeviceID
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.index)]
        )
        let channels = try modelContext.fetch(descriptor)
        return channels.map { ChannelDTO(from: $0) }
    }

    /// Fetch a channel by index
    public func fetchChannel(deviceID: UUID, index: UInt8) throws -> ChannelDTO? {
        let targetDeviceID = deviceID
        let targetIndex = index
        let predicate = #Predicate<Channel> { channel in
            channel.deviceID == targetDeviceID && channel.index == targetIndex
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ChannelDTO(from: $0) }
    }

    /// Fetch a channel by ID
    public func fetchChannel(id: UUID) throws -> ChannelDTO? {
        let targetID = id
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ChannelDTO(from: $0) }
    }

    /// Save or update a channel from ChannelInfo
    public func saveChannel(deviceID: UUID, from info: ChannelInfo) throws -> UUID {
        let targetDeviceID = deviceID
        let targetIndex = info.index
        let predicate = #Predicate<Channel> { channel in
            channel.deviceID == targetDeviceID && channel.index == targetIndex
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let channel: Channel
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: info)
            channel = existing
        } else {
            channel = Channel(deviceID: deviceID, from: info)
            modelContext.insert(channel)
        }

        try modelContext.save()
        return channel.id
    }

    /// Save or update a channel from DTO
    public func saveChannel(_ dto: ChannelDTO) throws {
        let targetID = dto.id
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = dto.name
            existing.secret = dto.secret
            existing.isEnabled = dto.isEnabled
            existing.lastMessageDate = dto.lastMessageDate
            existing.unreadCount = dto.unreadCount
        } else {
            let channel = Channel(
                id: dto.id,
                deviceID: dto.deviceID,
                index: dto.index,
                name: dto.name,
                secret: dto.secret,
                isEnabled: dto.isEnabled,
                lastMessageDate: dto.lastMessageDate,
                unreadCount: dto.unreadCount
            )
            modelContext.insert(channel)
        }

        try modelContext.save()
    }

    /// Delete a channel
    public func deleteChannel(id: UUID) throws {
        let targetID = id
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        if let channel = try modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
            modelContext.delete(channel)
            try modelContext.save()
        }
    }

    /// Update channel's last message info
    public func updateChannelLastMessage(channelID: UUID, date: Date) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let channel = try modelContext.fetch(descriptor).first {
            channel.lastMessageDate = date
            try modelContext.save()
        }
    }

    // MARK: - Channel Unread Count

    /// Increment unread count for a channel
    public func incrementChannelUnreadCount(channelID: UUID) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let channel = try modelContext.fetch(descriptor).first {
            channel.unreadCount += 1
            try modelContext.save()
        }
    }

    /// Clear unread count for a channel
    public func clearChannelUnreadCount(channelID: UUID) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let channel = try modelContext.fetch(descriptor).first {
            channel.unreadCount = 0
            try modelContext.save()
        }
    }

    // MARK: - Database Warm-up

    /// Forces SwiftData to initialize the database.
    /// Call this early in app lifecycle to avoid lazy initialization during user operations.
    public func warmUp() throws {
        // Perform a simple fetch to trigger modelContext initialization
        _ = try modelContext.fetchCount(FetchDescriptor<Device>())
    }
}
