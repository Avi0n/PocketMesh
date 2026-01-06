import Foundation
import SwiftData

/// Represents a single heard repeat of a sent channel message.
/// Each repeat is an observation of the message being re-broadcast by a repeater.
@Model
public final class MessageRepeat {
    @Attribute(.unique)
    public var id: UUID

    /// The parent message (cascade delete when message is deleted)
    public var message: Message?

    /// The message ID (kept for queries, matches message.id)
    public var messageID: UUID

    /// When this repeat was received by the companion radio
    public var receivedAt: Date

    /// Repeater public key prefixes (1 byte per hop in the path)
    public var pathNodes: Data

    /// Signal-to-noise ratio in dB
    public var snr: Double?

    /// Received signal strength indicator in dBm
    public var rssi: Int?

    /// Link to RxLogEntry for raw packet details
    public var rxLogEntryID: UUID?

    public init(
        id: UUID = UUID(),
        message: Message? = nil,
        messageID: UUID,
        receivedAt: Date = Date(),
        pathNodes: Data,
        snr: Double? = nil,
        rssi: Int? = nil,
        rxLogEntryID: UUID? = nil
    ) {
        self.id = id
        self.message = message
        self.messageID = messageID
        self.receivedAt = receivedAt
        self.pathNodes = pathNodes
        self.snr = snr
        self.rssi = rssi
        self.rxLogEntryID = rxLogEntryID
    }
}

// MARK: - DTO

/// Sendable DTO for cross-actor transfer of MessageRepeat data.
public struct MessageRepeatDTO: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let messageID: UUID
    public let receivedAt: Date
    public let pathNodes: Data
    public let snr: Double?
    public let rssi: Int?
    public let rxLogEntryID: UUID?

    public init(from model: MessageRepeat) {
        self.id = model.id
        self.messageID = model.messageID
        self.receivedAt = model.receivedAt
        self.pathNodes = model.pathNodes
        self.snr = model.snr
        self.rssi = model.rssi
        self.rxLogEntryID = model.rxLogEntryID
    }

    public init(
        id: UUID = UUID(),
        messageID: UUID,
        receivedAt: Date,
        pathNodes: Data,
        snr: Double?,
        rssi: Int?,
        rxLogEntryID: UUID?
    ) {
        self.id = id
        self.messageID = messageID
        self.receivedAt = receivedAt
        self.pathNodes = pathNodes
        self.snr = snr
        self.rssi = rssi
        self.rxLogEntryID = rxLogEntryID
    }

    // MARK: - Computed Properties

    /// First repeater's public key prefix byte, or nil if direct
    public var repeaterByte: UInt8? {
        pathNodes.first
    }

    /// Repeater hash formatted as hex (e.g., "31")
    public var repeaterHashFormatted: String {
        guard let byte = repeaterByte else { return "00" }
        // Hex format required for device identifier display - no SwiftUI alternative
        return String(format: "%02X", byte)
    }

    /// Path nodes as hex strings for display
    public var pathNodesHex: [String] {
        // Hex format required for device identifiers - no SwiftUI alternative
        pathNodes.map { String(format: "%02X", $0) }
    }

    /// SNR mapped to 0-1 for signal bars variableValue.
    /// Based on standard LoRa ranges: excellent > 10, good > 5, fair > 0, weak > -10.
    public var snrLevel: Double {
        guard let snr else { return 0 }
        if snr > 10 { return 1.0 }
        if snr > 5 { return 0.75 }
        if snr > 0 { return 0.5 }
        if snr > -10 { return 0.25 }
        return 0
    }

    /// RSSI formatted for display
    public var rssiFormatted: String {
        guard let rssi = rssi else { return "—" }
        return "\(rssi) dBm"
    }

    /// SNR formatted for display
    public var snrFormatted: String {
        guard let snr = snr else { return "—" }
        return snr.formatted(.number.precision(.fractionLength(1))) + " dB"
    }
}
