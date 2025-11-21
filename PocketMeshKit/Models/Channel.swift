import Foundation
import SwiftData

@Model
public final class Channel {
    public var id: UUID
    public var slotIndex: UInt8 // 0-7 (0 = public, 1-7 = custom)
    public var name: String
    public var secretHash: Data? // 16 bytes for non-public channels
    public var createdDate: Date
    public var lastMessageDate: Date?

    // Relationships
    public var device: Device?

    @Relationship(deleteRule: .cascade, inverse: \Message.channel)
    public var messages: [Message] = []

    public init(
        slotIndex: UInt8,
        name: String,
        secretHash: Data? = nil,
        device: Device? = nil,
    ) {
        id = UUID()
        self.slotIndex = slotIndex
        self.name = name
        self.secretHash = secretHash
        createdDate = Date()
        self.device = device
    }

    public var isPublic: Bool {
        slotIndex == 0
    }
}
