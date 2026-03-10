import Foundation
import SwiftData

/// Codable entry representing a single neighbor's state at snapshot time.
public struct NeighborSnapshotEntry: Codable, Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let snr: Double
    public let secondsAgo: Int

    public init(publicKeyPrefix: Data, snr: Double, secondsAgo: Int) {
        self.publicKeyPrefix = publicKeyPrefix
        self.snr = snr
        self.secondsAgo = secondsAgo
    }
}

/// Codable entry representing a single telemetry reading at snapshot time.
public struct TelemetrySnapshotEntry: Codable, Sendable, Equatable {
    public let channel: Int
    public let type: String
    public let value: Double

    public init(channel: Int, type: String, value: Double) {
        self.channel = channel
        self.type = type
        self.value = value
    }
}

/// Point-in-time snapshot of a remote node's status, captured when the user views it.
@Model
public final class NodeStatusSnapshot {
    #Index<NodeStatusSnapshot>([\.nodePublicKey, \.timestamp])

    @Attribute(.unique)
    public var id: UUID

    /// When this snapshot was captured
    public var timestamp: Date

    /// The node's full public key (32 bytes) -- links to RemoteNodeSession
    public var nodePublicKey: Data

    // MARK: - Radio metrics
    // Intentionally excluded: txQueueLength, airtime, sentFlood, sentDirect,
    // receivedFlood, receivedDirect, fullEvents, directDuplicates, floodDuplicates, receiveErrors

    public var batteryMillivolts: UInt16?
    public var lastSNR: Double?
    public var lastRSSI: Int16?
    public var noiseFloor: Int16?
    public var uptimeSeconds: UInt32?
    public var rxAirtimeSeconds: UInt32?
    public var packetsSent: UInt32?
    public var packetsReceived: UInt32?

    // MARK: - Optional neighbor/telemetry data

    /// Neighbor data, only populated if the user expanded the neighbors section.
    public var neighborSnapshots: [NeighborSnapshotEntry]?

    /// Telemetry data, only populated if the user expanded the telemetry section.
    public var telemetryEntries: [TelemetrySnapshotEntry]?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        nodePublicKey: Data,
        batteryMillivolts: UInt16? = nil,
        lastSNR: Double? = nil,
        lastRSSI: Int16? = nil,
        noiseFloor: Int16? = nil,
        uptimeSeconds: UInt32? = nil,
        rxAirtimeSeconds: UInt32? = nil,
        packetsSent: UInt32? = nil,
        packetsReceived: UInt32? = nil,
        neighborSnapshots: [NeighborSnapshotEntry]? = nil,
        telemetryEntries: [TelemetrySnapshotEntry]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.nodePublicKey = nodePublicKey
        self.batteryMillivolts = batteryMillivolts
        self.lastSNR = lastSNR
        self.lastRSSI = lastRSSI
        self.noiseFloor = noiseFloor
        self.uptimeSeconds = uptimeSeconds
        self.rxAirtimeSeconds = rxAirtimeSeconds
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.neighborSnapshots = neighborSnapshots
        self.telemetryEntries = telemetryEntries
    }
}

// MARK: - Sendable DTO

public struct NodeStatusSnapshotDTO: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let nodePublicKey: Data
    public let batteryMillivolts: UInt16?
    public let lastSNR: Double?
    public let lastRSSI: Int16?
    public let noiseFloor: Int16?
    public let uptimeSeconds: UInt32?
    public let rxAirtimeSeconds: UInt32?
    public let packetsSent: UInt32?
    public let packetsReceived: UInt32?
    public let neighborSnapshots: [NeighborSnapshotEntry]?
    public let telemetryEntries: [TelemetrySnapshotEntry]?

    init(from model: NodeStatusSnapshot) {
        self.id = model.id
        self.timestamp = model.timestamp
        self.nodePublicKey = model.nodePublicKey
        self.batteryMillivolts = model.batteryMillivolts
        self.lastSNR = model.lastSNR
        self.lastRSSI = model.lastRSSI
        self.noiseFloor = model.noiseFloor
        self.uptimeSeconds = model.uptimeSeconds
        self.rxAirtimeSeconds = model.rxAirtimeSeconds
        self.packetsSent = model.packetsSent
        self.packetsReceived = model.packetsReceived
        self.neighborSnapshots = model.neighborSnapshots
        self.telemetryEntries = model.telemetryEntries
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        nodePublicKey: Data,
        batteryMillivolts: UInt16? = nil,
        lastSNR: Double? = nil,
        lastRSSI: Int16? = nil,
        noiseFloor: Int16? = nil,
        uptimeSeconds: UInt32? = nil,
        rxAirtimeSeconds: UInt32? = nil,
        packetsSent: UInt32? = nil,
        packetsReceived: UInt32? = nil,
        neighborSnapshots: [NeighborSnapshotEntry]? = nil,
        telemetryEntries: [TelemetrySnapshotEntry]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.nodePublicKey = nodePublicKey
        self.batteryMillivolts = batteryMillivolts
        self.lastSNR = lastSNR
        self.lastRSSI = lastRSSI
        self.noiseFloor = noiseFloor
        self.uptimeSeconds = uptimeSeconds
        self.rxAirtimeSeconds = rxAirtimeSeconds
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.neighborSnapshots = neighborSnapshots
        self.telemetryEntries = telemetryEntries
    }
}
