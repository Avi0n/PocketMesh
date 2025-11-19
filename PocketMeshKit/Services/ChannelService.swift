import Foundation
import SwiftData
import CryptoKit
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Channels")

@MainActor
public final class ChannelService: ObservableObject {

    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext

    @Published var channels: [Channel] = []

    private let maxChannels = 8 // Slots 0-7

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext) {
        self.protocol = `protocol`
        self.modelContext = modelContext
    }

    /// Create or join a channel by name
    /// If name starts with "#", auto-generate 16-byte secret via SHA-256
    func createChannel(name: String, device: Device) throws -> Channel {
        // Find available slot
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Channel>(
            predicate: #Predicate { $0.device?.publicKey == devicePublicKey },
            sortBy: [SortDescriptor(\.slotIndex)]
        )
        let existingChannels = try modelContext.fetch(descriptor)

        guard existingChannels.count < maxChannels else {
            throw ChannelError.allSlotsFull
        }

        // Find first available slot index
        let usedSlots = Set(existingChannels.map { $0.slotIndex })
        guard let nextSlot = (0..<UInt8(maxChannels)).first(where: { !usedSlots.contains($0) }) else {
            throw ChannelError.allSlotsFull
        }

        // Generate secret if name starts with "#"
        var secretHash: Data? = nil
        var channelName = name

        if name.hasPrefix("#") {
            channelName = String(name.dropFirst())
            secretHash = generateSecretHash(from: channelName)
            logger.info("Generated secret hash for channel: \(channelName)")
        }

        let channel = Channel(
            slotIndex: nextSlot,
            name: channelName,
            secretHash: secretHash,
            device: device
        )

        modelContext.insert(channel)
        try modelContext.save()

        logger.info("Created channel '\(channelName)' in slot \(nextSlot)")

        // Initialize public channel (slot 0) if this is it
        if nextSlot == 0 {
            channel.name = "Public"
        }

        return channel
    }

    /// Leave a channel by clearing its slot
    func leaveChannel(_ channel: Channel) throws {
        modelContext.delete(channel)
        try modelContext.save()
        logger.info("Left channel: \(channel.name)")
    }

    /// Send a message to a channel
    public func sendMessage(text: String, to channel: Channel, device: Device) async throws {
        guard text.utf8.count <= 160 else {
            throw ChannelError.messageTooLong
        }

        // Create message record
        let message = Message(
            text: text,
            isOutgoing: true,
            contact: nil,
            channel: channel,
            device: device
        )
        modelContext.insert(message)
        try modelContext.save()

        // Send via protocol (flood mode for channels)
        do {
            message.deliveryStatus = .sending
            try modelContext.save()

            try await `protocol`.sendChannelTextMessage(
                text: text,
                channelIndex: channel.slotIndex
            )

            message.deliveryStatus = .sent
            channel.lastMessageDate = Date()
            try modelContext.save()

            logger.info("Channel message sent to slot \(channel.slotIndex)")

        } catch {
            message.deliveryStatus = .failed
            try modelContext.save()
            throw error
        }
    }

    /// Load all channels for active device
    func loadChannels(for device: Device) throws {
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Channel>(
            predicate: #Predicate { $0.device?.publicKey == devicePublicKey },
            sortBy: [SortDescriptor(\.slotIndex)]
        )
        channels = try modelContext.fetch(descriptor)
    }

    // MARK: - Private Helpers

    private func generateSecretHash(from name: String) -> Data {
        // Generate 16-byte hash from channel name using SHA-256
        // Take first 16 bytes of hash
        let nameData = name.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: nameData)
        return Data(hash.prefix(16))
    }
}

public enum ChannelError: LocalizedError {
    case allSlotsFull
    case messageTooLong
    case invalidSlotIndex

    public var errorDescription: String? {
        switch self {
        case .allSlotsFull: return "All channel slots are full (max 8)"
        case .messageTooLong: return "Channel message exceeds 160 byte limit"
        case .invalidSlotIndex: return "Invalid channel slot index"
        }
    }
}
