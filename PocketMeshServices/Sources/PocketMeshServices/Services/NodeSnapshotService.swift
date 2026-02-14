import Foundation
import OSLog

/// Service for managing node status snapshots with throttled capture.
public actor NodeSnapshotService {
    private let dataStore: PersistenceStore
    private let logger = Logger(subsystem: "com.pocketmesh.services", category: "NodeSnapshotService")

    /// Minimum interval between snapshots for the same node (15 minutes)
    private static let minimumInterval: TimeInterval = 15 * 60

    public init(dataStore: PersistenceStore) {
        self.dataStore = dataStore
    }

    /// Save a status snapshot if enough time has passed since the last one.
    /// Returns the snapshot ID if saved, nil if throttled.
    public func saveStatusSnapshot(
        nodePublicKey: Data,
        batteryMillivolts: UInt16?,
        lastSNR: Double?,
        lastRSSI: Int16?,
        noiseFloor: Int16?,
        uptimeSeconds: UInt32?,
        rxAirtimeSeconds: UInt32?,
        packetsSent: UInt32?,
        packetsReceived: UInt32?
    ) async -> UUID? {
        do {
            if let latest = try await dataStore.fetchLatestNodeStatusSnapshot(nodePublicKey: nodePublicKey),
               latest.timestamp.distance(to: .now) < Self.minimumInterval {
                logger.debug("Snapshot throttled for node (last: \(latest.timestamp))")
                return nil
            }

            let id = try await dataStore.saveNodeStatusSnapshot(
                nodePublicKey: nodePublicKey,
                batteryMillivolts: batteryMillivolts,
                lastSNR: lastSNR,
                lastRSSI: lastRSSI,
                noiseFloor: noiseFloor,
                uptimeSeconds: uptimeSeconds,
                rxAirtimeSeconds: rxAirtimeSeconds,
                packetsSent: packetsSent,
                packetsReceived: packetsReceived
            )
            logger.info("Saved status snapshot for node")
            return id
        } catch {
            logger.error("Failed to save snapshot: \(error)")
            return nil
        }
    }

    /// Enrich an existing snapshot with neighbor data.
    public func enrichWithNeighbors(_ neighbors: [NeighborSnapshotEntry], snapshotID: UUID) async {
        do {
            try await dataStore.updateSnapshotNeighbors(id: snapshotID, neighbors: neighbors)
        } catch {
            logger.error("Failed to enrich snapshot with neighbors: \(error)")
        }
    }

    /// Enrich an existing snapshot with telemetry data.
    public func enrichWithTelemetry(_ telemetry: [TelemetrySnapshotEntry], snapshotID: UUID) async {
        do {
            try await dataStore.updateSnapshotTelemetry(id: snapshotID, telemetry: telemetry)
        } catch {
            logger.error("Failed to enrich snapshot with telemetry: \(error)")
        }
    }

    /// Fetch the most recent snapshot before the given date (for delta calculation).
    public func previousSnapshot(for nodePublicKey: Data, before date: Date) async -> NodeStatusSnapshotDTO? {
        do {
            return try await dataStore.fetchPreviousNodeStatusSnapshot(nodePublicKey: nodePublicKey, before: date)
        } catch {
            logger.error("Failed to fetch previous snapshot: \(error)")
            return nil
        }
    }

    /// Fetch all snapshots for a node, optionally filtered by date range.
    public func fetchSnapshots(for nodePublicKey: Data, since: Date? = nil) async -> [NodeStatusSnapshotDTO] {
        do {
            return try await dataStore.fetchNodeStatusSnapshots(nodePublicKey: nodePublicKey, since: since)
        } catch {
            logger.error("Failed to fetch snapshots: \(error)")
            return []
        }
    }
}
