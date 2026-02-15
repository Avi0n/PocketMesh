import Foundation
import SwiftData

/// A channel sender name that the user has blocked.
/// Channel messages don't include sender keys, so blocking is name-based only.
@Model
public final class BlockedChannelSender {
    #Index<BlockedChannelSender>([\.deviceID, \.name])

    @Attribute(.unique)
    public var id: UUID

    /// The sender name to block (matched exactly as stored)
    public var name: String

    /// Which device this block applies to
    public var deviceID: UUID

    /// When the user blocked this name
    public var dateBlocked: Date

    public init(
        id: UUID = UUID(),
        name: String,
        deviceID: UUID,
        dateBlocked: Date = .now
    ) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.dateBlocked = dateBlocked
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of BlockedChannelSender for cross-actor transfers.
public struct BlockedChannelSenderDTO: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let deviceID: UUID
    public let dateBlocked: Date

    public init(
        id: UUID = UUID(),
        name: String,
        deviceID: UUID,
        dateBlocked: Date = .now
    ) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.dateBlocked = dateBlocked
    }

    public init(from model: BlockedChannelSender) {
        self.id = model.id
        self.name = model.name
        self.deviceID = model.deviceID
        self.dateBlocked = model.dateBlocked
    }
}
