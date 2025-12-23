import Foundation
import MeshCore
import SwiftData

// MARK: - PersistenceStore Errors

public enum PersistenceStoreError: Error, Sendable {
    case deviceNotFound
    case contactNotFound
    case messageNotFound
    case channelNotFound
    case remoteNodeSessionNotFound
    case saveFailed(String)
    case fetchFailed(String)
    case invalidData
}

// MARK: - PersistenceStore Actor

/// ModelActor for background SwiftData operations.
/// Provides per-device data isolation and thread-safe access.
@ModelActor
public actor PersistenceStore: PersistenceStoreProtocol {

    /// Shared schema for PocketMesh models
    public static let schema = Schema([
        Device.self,
        Contact.self,
        Message.self,
        Channel.self,
        RemoteNodeSession.self,
        RoomMessage.self
    ])

    /// Creates a ModelContainer for the app
    public static func createContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

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

    /// Fetch all confirmed contacts for a device (excludes discovered contacts)
    public func fetchContacts(deviceID: UUID) throws -> [ContactDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.isDiscovered == false
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.name)]
        )
        let contacts = try modelContext.fetch(descriptor)
        return contacts.map { ContactDTO(from: $0) }
    }

    /// Fetch contacts with recent messages (for chat list, excludes discovered contacts)
    public func fetchConversations(deviceID: UUID) throws -> [ContactDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.lastMessageDate != nil && contact.isDiscovered == false
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

    /// Save a discovered contact (from NEW_ADVERT push)
    /// These contacts are not yet on the device's contact table
    /// - Returns: Tuple of (contactID, isNew) where isNew is true only if contact was newly created
    public func saveDiscoveredContact(deviceID: UUID, from frame: ContactFrame) throws -> (contactID: UUID, isNew: Bool) {
        let targetDeviceID = deviceID
        let targetKey = frame.publicKey
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.publicKey == targetKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        let contact: Contact
        let isNew: Bool
        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing discovered contact
            existing.update(from: frame)
            contact = existing
            isNew = false
        } else {
            // Create new discovered contact
            contact = Contact(deviceID: deviceID, from: frame)
            contact.isDiscovered = true
            modelContext.insert(contact)
            isNew = true
        }

        try modelContext.save()
        return (contactID: contact.id, isNew: isNew)
    }

    /// Fetch all discovered (pending) contacts for a device
    public func fetchDiscoveredContacts(deviceID: UUID) throws -> [ContactDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<Contact> { contact in
            contact.deviceID == targetDeviceID && contact.isDiscovered == true
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.name)]
        )
        let contacts = try modelContext.fetch(descriptor)
        return contacts.map { ContactDTO(from: $0) }
    }

    /// Mark a discovered contact as confirmed (after adding to device)
    public func confirmContact(id: UUID) throws {
        let targetID = id
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let contact = try modelContext.fetch(descriptor).first {
            contact.isDiscovered = false
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

    /// Save a new message (with deduplication for incoming messages)
    public func saveMessage(_ dto: MessageDTO) throws {
        // Generate deduplication key for incoming messages
        let dedupKey: String?
        if dto.direction == .incoming {
            dedupKey = Message.generateDeduplicationKey(
                timestamp: dto.timestamp,
                senderKeyPrefix: dto.senderKeyPrefix,
                text: dto.text
            )
            // Check for duplicate
            if try isDuplicateMessage(deduplicationKey: dedupKey!) {
                return  // Silently skip duplicate
            }
        } else {
            dedupKey = nil
        }

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
            pathLength: dto.pathLength,
            snr: dto.snr,
            senderKeyPrefix: dto.senderKeyPrefix,
            senderNodeName: dto.senderNodeName,
            isRead: dto.isRead,
            replyToID: dto.replyToID,
            roundTripTime: dto.roundTripTime,
            heardRepeats: dto.heardRepeats,
            retryAttempt: dto.retryAttempt,
            maxRetryAttempts: dto.maxRetryAttempts,
            deduplicationKey: dedupKey
        )
        modelContext.insert(message)
        try modelContext.save()
    }

    /// Check if a message with the given deduplication key already exists
    public func isDuplicateMessage(deduplicationKey: String) throws -> Bool {
        let targetKey: String? = deduplicationKey
        let predicate = #Predicate<Message> { message in
            message.deduplicationKey == targetKey
        }
        return try modelContext.fetchCount(FetchDescriptor(predicate: predicate)) > 0
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

    /// Update message status with retry attempt information
    public func updateMessageRetryStatus(
        id: UUID,
        status: MessageStatus,
        retryAttempt: Int,
        maxRetryAttempts: Int
    ) throws {
        let targetID = id
        let predicate = #Predicate<Message> { message in
            message.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let message = try modelContext.fetch(descriptor).first {
            message.status = status
            message.retryAttempt = retryAttempt
            message.maxRetryAttempts = maxRetryAttempts
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

    /// Clear unread count for a channel by deviceID and index
    /// More efficient than fetching the full channel DTO when only clearing unread
    public func clearChannelUnreadCount(deviceID: UUID, index: UInt8) throws {
        let targetDeviceID = deviceID
        let targetIndex = index
        let predicate = #Predicate<Channel> { channel in
            channel.deviceID == targetDeviceID && channel.index == targetIndex
        }
        var descriptor = FetchDescriptor<Channel>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let channel = try modelContext.fetch(descriptor).first {
            channel.unreadCount = 0
            try modelContext.save()
        }
    }

    // MARK: - Badge Count Support

    /// Efficiently calculate total unread counts for badge display
    /// Returns tuple of (contactUnread, channelUnread) for preference-aware calculation
    /// Optimization: Only fetches entities with unread > 0 to minimize memory usage
    public func getTotalUnreadCounts() throws -> (contacts: Int, channels: Int) {
        // Only fetch contacts with unread messages (reduces memory pressure)
        let contactPredicate = #Predicate<Contact> { $0.unreadCount > 0 }
        let contactDescriptor = FetchDescriptor<Contact>(predicate: contactPredicate)
        let contactsWithUnread = try modelContext.fetch(contactDescriptor)
        let contactTotal = contactsWithUnread.reduce(0) { $0 + $1.unreadCount }

        // Only fetch channels with unread messages
        let channelPredicate = #Predicate<Channel> { $0.unreadCount > 0 }
        let channelDescriptor = FetchDescriptor<Channel>(predicate: channelPredicate)
        let channelsWithUnread = try modelContext.fetch(channelDescriptor)
        let channelTotal = channelsWithUnread.reduce(0) { $0 + $1.unreadCount }

        return (contacts: contactTotal, channels: channelTotal)
    }

    /// Get total unread count for a contact
    public func getUnreadCount(contactID: UUID) throws -> Int {
        let targetID = contactID
        let predicate = #Predicate<Contact> { contact in
            contact.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.unreadCount ?? 0
    }

    /// Get total unread count for a channel
    public func getChannelUnreadCount(channelID: UUID) throws -> Int {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.unreadCount ?? 0
    }

    // MARK: - Database Warm-up

    /// Forces SwiftData to initialize the database.
    /// Call this early in app lifecycle to avoid lazy initialization during user operations.
    public func warmUp() throws {
        // Perform a simple fetch to trigger modelContext initialization
        _ = try modelContext.fetchCount(FetchDescriptor<Device>())
    }

    // MARK: - RemoteNodeSession Operations

    /// Fetch remote node session by UUID
    public func fetchRemoteNodeSession(id: UUID) throws -> RemoteNodeSessionDTO? {
        let targetID = id
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { RemoteNodeSessionDTO(from: $0) }
    }

    /// Fetch remote node session by 32-byte public key
    public func fetchRemoteNodeSession(publicKey: Data) throws -> RemoteNodeSessionDTO? {
        let targetKey = publicKey
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.publicKey == targetKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { RemoteNodeSessionDTO(from: $0) }
    }

    /// Fetch remote node session by 6-byte public key prefix
    public func fetchRemoteNodeSessionByPrefix(_ prefix: Data) throws -> RemoteNodeSessionDTO? {
        // SwiftData predicates don't support prefix matching directly
        // Fetch all sessions and filter in memory
        let sessions = try modelContext.fetch(FetchDescriptor<RemoteNodeSession>())
        return sessions.first { $0.publicKey.prefix(6) == prefix }.map { RemoteNodeSessionDTO(from: $0) }
    }

    /// Fetch all connected sessions for re-authentication after BLE reconnection
    public func fetchConnectedRemoteNodeSessions() throws -> [RemoteNodeSessionDTO] {
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.isConnected == true
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let sessions = try modelContext.fetch(descriptor)
        return sessions.map { RemoteNodeSessionDTO(from: $0) }
    }

    /// Fetch all remote node sessions for a device
    public func fetchRemoteNodeSessions(deviceID: UUID) throws -> [RemoteNodeSessionDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.deviceID == targetDeviceID
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\RemoteNodeSession.name)]
        )
        let sessions = try modelContext.fetch(descriptor)
        return sessions.map { RemoteNodeSessionDTO(from: $0) }
    }

    /// Save or update a remote node session (void version for cross-actor calls)
    public func saveRemoteNodeSessionDTO(_ dto: RemoteNodeSessionDTO) throws {
        _ = try saveRemoteNodeSession(dto)
    }

    /// Save or update a remote node session
    @discardableResult
    public func saveRemoteNodeSession(_ dto: RemoteNodeSessionDTO) throws -> RemoteNodeSession {
        let targetID = dto.id
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            existing.deviceID = dto.deviceID
            existing.publicKey = dto.publicKey
            existing.name = dto.name
            existing.roleRawValue = dto.role.rawValue
            existing.latitude = dto.latitude
            existing.longitude = dto.longitude
            existing.isConnected = dto.isConnected
            existing.permissionLevelRawValue = dto.permissionLevel.rawValue
            existing.lastConnectedDate = dto.lastConnectedDate
            existing.lastBatteryMillivolts = dto.lastBatteryMillivolts
            existing.lastUptimeSeconds = dto.lastUptimeSeconds
            existing.lastNoiseFloor = dto.lastNoiseFloor
            existing.unreadCount = dto.unreadCount
            existing.lastRxAirtimeSeconds = dto.lastRxAirtimeSeconds
            existing.neighborCount = dto.neighborCount
            existing.lastSyncTimestamp = dto.lastSyncTimestamp
            try modelContext.save()
            return existing
        } else {
            // Create new
            let session = RemoteNodeSession(
                id: dto.id,
                deviceID: dto.deviceID,
                publicKey: dto.publicKey,
                name: dto.name,
                role: dto.role,
                latitude: dto.latitude,
                longitude: dto.longitude,
                isConnected: dto.isConnected,
                permissionLevel: dto.permissionLevel,
                lastConnectedDate: dto.lastConnectedDate,
                lastBatteryMillivolts: dto.lastBatteryMillivolts,
                lastUptimeSeconds: dto.lastUptimeSeconds,
                lastNoiseFloor: dto.lastNoiseFloor,
                unreadCount: dto.unreadCount,
                lastRxAirtimeSeconds: dto.lastRxAirtimeSeconds,
                neighborCount: dto.neighborCount,
                lastSyncTimestamp: dto.lastSyncTimestamp
            )
            modelContext.insert(session)
            try modelContext.save()
            return session
        }
    }

    /// Update session connection state
    public func updateRemoteNodeSessionConnection(
        id: UUID,
        isConnected: Bool,
        permissionLevel: RoomPermissionLevel
    ) throws {
        let targetID = id
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let session = try modelContext.fetch(descriptor).first {
            session.isConnected = isConnected
            session.permissionLevelRawValue = permissionLevel.rawValue
            if isConnected {
                session.lastConnectedDate = Date()
            }
            try modelContext.save()
        }
    }

    /// Reset all remote node sessions to disconnected state.
    /// Call this on app launch since connections don't persist across restarts.
    public func resetAllRemoteNodeSessionConnections() throws {
        let descriptor = FetchDescriptor<RemoteNodeSession>()
        let sessions = try modelContext.fetch(descriptor)
        for session in sessions {
            session.isConnected = false
        }
        try modelContext.save()
    }

    /// Delete remote node session and all associated room messages
    public func deleteRemoteNodeSession(id: UUID) throws {
        let targetID = id

        // Delete associated room messages
        let messagePredicate = #Predicate<RoomMessage> { message in
            message.sessionID == targetID
        }
        let messages = try modelContext.fetch(FetchDescriptor(predicate: messagePredicate))
        for message in messages {
            modelContext.delete(message)
        }

        // Delete the session
        let sessionPredicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        if let session = try modelContext.fetch(FetchDescriptor(predicate: sessionPredicate)).first {
            modelContext.delete(session)
        }

        try modelContext.save()
    }

    /// Update the last sync timestamp for a room session.
    /// Call this when messages are received to track sync progress.
    /// Only updates if the new timestamp is greater than the current one.
    public func updateRoomLastSyncTimestamp(_ sessionID: UUID, timestamp: UInt32) throws {
        let targetID = sessionID
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let session = try modelContext.fetch(descriptor).first {
            // Only update if newer than current
            if timestamp > session.lastSyncTimestamp {
                session.lastSyncTimestamp = timestamp
                try modelContext.save()
            }
        }
    }

    // MARK: - RoomMessage Operations

    /// Check for duplicate room message using deduplication key
    public func isDuplicateRoomMessage(sessionID: UUID, deduplicationKey: String) throws -> Bool {
        let targetSessionID = sessionID
        let targetKey = deduplicationKey
        let predicate = #Predicate<RoomMessage> { message in
            message.sessionID == targetSessionID && message.deduplicationKey == targetKey
        }
        return try modelContext.fetchCount(FetchDescriptor(predicate: predicate)) > 0
    }

    /// Save room message (checks deduplication automatically)
    public func saveRoomMessage(_ dto: RoomMessageDTO) throws {
        // Check for duplicate first
        if try isDuplicateRoomMessage(sessionID: dto.sessionID, deduplicationKey: dto.deduplicationKey) {
            return  // Silently ignore duplicates
        }

        let message = RoomMessage(
            id: dto.id,
            sessionID: dto.sessionID,
            authorKeyPrefix: dto.authorKeyPrefix,
            authorName: dto.authorName,
            text: dto.text,
            timestamp: dto.timestamp,
            isFromSelf: dto.isFromSelf
        )
        modelContext.insert(message)
        try modelContext.save()
    }

    /// Increment unread message count for a room session
    public func incrementRoomUnreadCount(_ sessionID: UUID) throws {
        let targetID = sessionID
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let session = try modelContext.fetch(descriptor).first {
            session.unreadCount += 1
            try modelContext.save()
        }
    }

    /// Reset unread count to zero (called when user views conversation)
    public func resetRoomUnreadCount(_ sessionID: UUID) throws {
        let targetID = sessionID
        let predicate = #Predicate<RemoteNodeSession> { session in
            session.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let session = try modelContext.fetch(descriptor).first {
            session.unreadCount = 0
            try modelContext.save()
        }
    }

    /// Fetch room messages for a session, ordered by timestamp
    public func fetchRoomMessages(sessionID: UUID, limit: Int? = nil, offset: Int? = nil) throws -> [RoomMessageDTO] {
        let targetSessionID = sessionID
        let predicate = #Predicate<RoomMessage> { message in
            message.sessionID == targetSessionID
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\RoomMessage.timestamp, order: .forward)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        if let offset {
            descriptor.fetchOffset = offset
        }
        let messages = try modelContext.fetch(descriptor)
        return messages.map { RoomMessageDTO(from: $0) }
    }

    // MARK: - Contact Helper Methods

    /// Find contact display name by 4-byte or 6-byte public key prefix.
    /// Returns nil if no matching contact found.
    public func findContactNameByKeyPrefix(_ prefix: Data) throws -> String? {
        // Fetch all contacts and filter by prefix match
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let prefixLength = prefix.count
        return contacts.first { contact in
            contact.publicKey.prefix(prefixLength) == prefix
        }?.displayName
    }

    /// Find contact by 4-byte or 6-byte public key prefix.
    /// Returns nil if no matching contact found.
    public func findContactByKeyPrefix(_ prefix: Data) throws -> ContactDTO? {
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let prefixLength = prefix.count
        return contacts.first { contact in
            contact.publicKey.prefix(prefixLength) == prefix
        }.map { ContactDTO(from: $0) }
    }

    /// Find contact by 32-byte public key
    public func findContactByPublicKey(_ publicKey: Data) throws -> ContactDTO? {
        let targetKey = publicKey
        let predicate = #Predicate<Contact> { contact in
            contact.publicKey == targetKey
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ContactDTO(from: $0) }
    }
}
