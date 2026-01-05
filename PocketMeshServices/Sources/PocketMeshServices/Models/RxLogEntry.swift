// PocketMeshServices/Sources/PocketMeshServices/Models/RxLogEntry.swift
import Foundation
import MeshCore
import SwiftData

/// SwiftData model for persisted RX log packets.
@Model
public final class RxLogEntry {
    @Attribute(.unique)
    public var id: UUID

    public var deviceID: UUID

    public var receivedAt: Date

    // From MeshCore ParsedRxLogData
    public var snr: Double?
    public var rssi: Int?
    public var routeType: Int
    public var payloadType: Int
    public var payloadVersion: Int
    public var transportCode: Data?
    public var pathLength: Int
    public var pathNodes: Data  // Raw bytes, 1 byte per hop
    public var packetPayload: Data
    public var rawPayload: Data

    // Correlation key for "heard repeats"
    public var packetHash: String

    // App-level decoding
    public var channelHash: Int?
    public var channelName: String?
    public var decryptStatus: Int
    public var fromContactName: String?
    public var toContactName: String?

    // Privacy: Never persisted — decrypted on demand
    @Transient
    public var decodedText: String?

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        receivedAt: Date = Date(),
        snr: Double? = nil,
        rssi: Int? = nil,
        routeType: Int,
        payloadType: Int,
        payloadVersion: Int,
        transportCode: Data? = nil,
        pathLength: Int,
        pathNodes: Data,
        packetPayload: Data,
        rawPayload: Data,
        packetHash: String,
        channelHash: Int? = nil,
        channelName: String? = nil,
        decryptStatus: Int = DecryptStatus.notApplicable.rawValue,
        fromContactName: String? = nil,
        toContactName: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.receivedAt = receivedAt
        self.snr = snr
        self.rssi = rssi
        self.routeType = routeType
        self.payloadType = payloadType
        self.payloadVersion = payloadVersion
        self.transportCode = transportCode
        self.pathLength = pathLength
        self.pathNodes = pathNodes
        self.packetPayload = packetPayload
        self.rawPayload = rawPayload
        self.packetHash = packetHash
        self.channelHash = channelHash
        self.channelName = channelName
        self.decryptStatus = decryptStatus
        self.fromContactName = fromContactName
        self.toContactName = toContactName
    }
}

/// Sendable DTO for cross-actor transfer of RxLogEntry data.
public struct RxLogEntryDTO: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let deviceID: UUID
    public let receivedAt: Date
    public let snr: Double?
    public let rssi: Int?
    public let routeType: RouteType
    public let payloadType: PayloadType
    public let payloadVersion: UInt8
    public let transportCode: Data?
    public let pathLength: UInt8
    public let pathNodes: Data
    public let packetPayload: Data
    public let rawPayload: Data
    public let packetHash: String
    public let channelHash: UInt8?
    public let channelName: String?
    public let decryptStatus: DecryptStatus
    public let fromContactName: String?
    public let toContactName: String?

    // Transient - set by UI layer after decryption
    public var decodedText: String?

    /// Initialize from SwiftData model.
    public init(from model: RxLogEntry) {
        self.id = model.id
        self.deviceID = model.deviceID
        self.receivedAt = model.receivedAt
        self.snr = model.snr
        self.rssi = model.rssi
        self.routeType = RouteType(rawValue: UInt8(model.routeType)) ?? .flood
        self.payloadType = PayloadType(rawValue: UInt8(model.payloadType)) ?? .unknown
        self.payloadVersion = UInt8(model.payloadVersion)
        self.transportCode = model.transportCode
        self.pathLength = UInt8(model.pathLength)
        self.pathNodes = model.pathNodes
        self.packetPayload = model.packetPayload
        self.rawPayload = model.rawPayload
        self.packetHash = model.packetHash
        self.channelHash = model.channelHash.map { UInt8($0) }
        self.channelName = model.channelName
        self.decryptStatus = DecryptStatus(rawValue: model.decryptStatus) ?? .notApplicable
        self.fromContactName = model.fromContactName
        self.toContactName = model.toContactName
        self.decodedText = model.decodedText
    }

    /// Initialize from ParsedRxLogData (for new entries).
    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        receivedAt: Date = Date(),
        from parsed: ParsedRxLogData,
        channelHash: UInt8? = nil,
        channelName: String? = nil,
        decryptStatus: DecryptStatus = .notApplicable,
        fromContactName: String? = nil,
        toContactName: String? = nil,
        decodedText: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.receivedAt = receivedAt
        self.snr = parsed.snr
        self.rssi = parsed.rssi
        self.routeType = parsed.routeType
        self.payloadType = parsed.payloadType
        self.payloadVersion = parsed.payloadVersion
        self.transportCode = parsed.transportCode
        self.pathLength = parsed.pathLength
        self.pathNodes = Data(parsed.pathNodes)
        self.packetPayload = parsed.packetPayload
        self.rawPayload = parsed.rawPayload
        self.packetHash = parsed.packetHash
        self.channelHash = channelHash
        self.channelName = channelName
        self.decryptStatus = decryptStatus
        self.fromContactName = fromContactName
        self.toContactName = toContactName
        self.decodedText = decodedText
    }

    // MARK: - Computed Properties

    /// Path nodes as hex strings for display.
    public var pathNodesHex: [String] {
        pathNodes.map { String(format: "%02X", $0) }
    }

    /// Formatted path string for compact display.
    public var pathDisplayString: String {
        if pathLength == 0 {
            return "direct"
        }
        let hexNodes = pathNodesHex.joined(separator: ":")
        return "via [\(hexNodes)]"
    }

    /// Whether this is a flood-type route.
    public var isFlood: Bool {
        routeType == .flood || routeType == .tcFlood
    }

    // MARK: - Signal Quality

    /// RSSI mapped to 0-1 for SF Symbol cellularbars variableValue.
    /// Based on standard LoRa ranges: excellent > -70, good > -90, fair > -110, weak > -120.
    public var rssiLevel: Double {
        guard let rssi else { return 0 }
        if rssi > -70 { return 1.0 }
        if rssi > -90 { return 0.75 }
        if rssi > -110 { return 0.5 }
        if rssi > -120 { return 0.25 }
        return 0.1
    }

    /// Human-readable RSSI quality label for accessibility.
    public var rssiQualityLabel: String {
        guard let rssi else { return "Unknown" }
        if rssi > -70 { return "Excellent" }
        if rssi > -90 { return "Good" }
        if rssi > -110 { return "Fair" }
        if rssi > -120 { return "Weak" }
        return "Marginal"
    }

    /// Formatted SNR string (no label, includes sign for negative).
    public var snrDisplayString: String? {
        guard let snr else { return nil }
        return snr.formatted(.number.precision(.fractionLength(1))) + " dB"
    }

    /// Route type display - "FLOOD" or "DIRECT" (simplified from TC variants).
    public var routeTypeSimple: String {
        isFlood ? "FLOOD" : "DIRECT"
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
