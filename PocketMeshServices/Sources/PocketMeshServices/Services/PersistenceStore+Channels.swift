import Foundation
import MeshCore
import SwiftData

extension PersistenceStore {

    // MARK: - Blocked Channel Senders

    public func saveBlockedChannelSender(_ dto: BlockedChannelSenderDTO) throws {
        let targetDeviceID = dto.deviceID
        let targetName = dto.name
        let predicate = #Predicate<BlockedChannelSender> { entry in
            entry.deviceID == targetDeviceID && entry.name == targetName
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.dateBlocked = dto.dateBlocked
        } else {
            let entry = BlockedChannelSender(
                id: dto.id,
                name: targetName,
                deviceID: dto.deviceID,
                dateBlocked: dto.dateBlocked
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
    }

    public func deleteBlockedChannelSender(deviceID: UUID, name: String) throws {
        let targetDeviceID = deviceID
        let targetName = name
        let predicate = #Predicate<BlockedChannelSender> { entry in
            entry.deviceID == targetDeviceID && entry.name == targetName
        }
        if let entry = try modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
            modelContext.delete(entry)
            try modelContext.save()
        }
    }

    public func fetchBlockedChannelSenders(deviceID: UUID) throws -> [BlockedChannelSenderDTO] {
        let targetDeviceID = deviceID
        let predicate = #Predicate<BlockedChannelSender> { entry in
            entry.deviceID == targetDeviceID
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dateBlocked, order: .reverse)]
        )
        let entries = try modelContext.fetch(descriptor)
        return entries.map { BlockedChannelSenderDTO(from: $0) }
    }

    // MARK: - Mention Tracking

    public func incrementChannelUnreadMentionCount(channelID: UUID) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else { return }
        channel.unreadMentionCount += 1
        try modelContext.save()
    }

    public func decrementChannelUnreadMentionCount(channelID: UUID) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else { return }
        channel.unreadMentionCount = max(0, channel.unreadMentionCount - 1)
        try modelContext.save()
    }

    public func clearChannelUnreadMentionCount(channelID: UUID) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { channel in
            channel.id == targetID
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else { return }
        channel.unreadMentionCount = 0
        try modelContext.save()
    }

    public func fetchUnseenChannelMentionIDs(deviceID: UUID, channelIndex: UInt8) throws -> [UUID] {
        let targetDeviceID = deviceID
        let targetIndex: UInt8? = channelIndex
        let predicate = #Predicate<Message> { message in
            message.deviceID == targetDeviceID &&
            message.channelIndex == targetIndex &&
            message.containsSelfMention == true &&
            message.mentionSeen == false
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]

        let messages = try modelContext.fetch(descriptor)
        return messages.map(\.id)
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
            existing.apply(dto)
        } else {
            let channel = Channel(
                id: dto.id,
                deviceID: dto.deviceID,
                index: dto.index,
                name: dto.name,
                secret: dto.secret,
                isEnabled: dto.isEnabled,
                lastMessageDate: dto.lastMessageDate,
                unreadCount: dto.unreadCount,
                unreadMentionCount: dto.unreadMentionCount,
                notificationLevel: dto.notificationLevel,
                isFavorite: dto.isFavorite
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

    /// Delete all messages for a channel
    public func deleteMessagesForChannel(deviceID: UUID, channelIndex: UInt8) throws {
        let targetDeviceID = deviceID
        let targetChannelIndex: UInt8? = channelIndex
        try modelContext.delete(model: Message.self, where: #Predicate {
            $0.deviceID == targetDeviceID && $0.channelIndex == targetChannelIndex
        })
        try modelContext.save()
    }

    /// Update channel's last message info (nil clears the date)
    public func updateChannelLastMessage(channelID: UUID, date: Date?) throws {
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

    /// Sets the muted state for a channel
    public func setChannelMuted(_ channelID: UUID, isMuted: Bool) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { $0.id == targetID }
        var descriptor = FetchDescriptor<Channel>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else {
            throw PersistenceStoreError.channelNotFound
        }

        channel.notificationLevel = isMuted ? .muted : .all
        try modelContext.save()
    }

    /// Sets the notification level for a channel
    public func setChannelNotificationLevel(_ channelID: UUID, level: NotificationLevel) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { $0.id == targetID }
        var descriptor = FetchDescriptor<Channel>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else {
            throw PersistenceStoreError.channelNotFound
        }

        channel.notificationLevel = level
        try modelContext.save()
    }

    /// Sets the favorite state for a channel
    public func setChannelFavorite(_ channelID: UUID, isFavorite: Bool) throws {
        let targetID = channelID
        let predicate = #Predicate<Channel> { $0.id == targetID }
        var descriptor = FetchDescriptor<Channel>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let channel = try modelContext.fetch(descriptor).first else {
            throw PersistenceStoreError.channelNotFound
        }

        channel.isFavorite = isFavorite
        try modelContext.save()
    }
}
