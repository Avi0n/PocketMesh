import Foundation
import SwiftData

@Model
public final class Message {
    public var id: UUID
    public var text: String
    public var timestamp: Date
    public var senderTimestamp: Date? // From protocol
    public var isOutgoing: Bool
    public var deliveryStatus: DeliveryStatus

    // ACK tracking for outgoing messages
    public var ackCode: UInt32?
    public var expectedAckTimeout: Date?
    public var retryCount: Int
    public var lastRetryDate: Date?
    public var routingMode: MessageRoutingMode?

    // Incoming message metadata
    public var senderPublicKeyPrefix: Data? // First 6 bytes
    public var pathLength: UInt8?
    public var snr: Double? // SNR * 4 from v3 protocol

    // Message type
    public var messageType: MessageType

    // Relationships
    public var device: Device?
    public var contact: Contact? // For direct messages
    public var channel: Channel? // For channel messages

    public init(
        text: String,
        isOutgoing: Bool,
        contact: Contact? = nil,
        channel: Channel? = nil,
        device: Device? = nil,
    ) {
        id = UUID()
        self.text = text
        timestamp = Date()
        self.isOutgoing = isOutgoing
        deliveryStatus = isOutgoing ? .queued : .received
        retryCount = 0
        messageType = channel != nil ? .channel : .direct
        self.contact = contact
        self.channel = channel
        self.device = device
    }
}

public enum DeliveryStatus: String, CaseIterable, Codable, Sendable {
    case queued
    case sending
    case sent
    case delivered
    case failed
    case received
}

public enum MessageType: String, CaseIterable, Codable, Sendable {
    case direct
    case channel
}

public enum MessageRoutingMode: String, CaseIterable, Codable, Sendable {
    case direct
    case storeAndForward
    case meshBroadcast
}
