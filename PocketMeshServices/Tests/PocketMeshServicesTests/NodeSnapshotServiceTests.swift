import Foundation
import SwiftData
import Testing
@testable import PocketMeshServices

@Suite("NodeSnapshotService Tests")
struct NodeSnapshotServiceTests {

    private let testPublicKey = Data(repeating: 0x42, count: 32)

    private func createTestService() async throws -> (NodeSnapshotService, PersistenceStore) {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let service = NodeSnapshotService(dataStore: store)
        return (service, store)
    }

    @Test("Save snapshot returns ID on first save")
    func saveFirstSnapshot() async throws {
        let (service, _) = try await createTestService()

        let id = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: 8.5,
            lastRSSI: -87,
            noiseFloor: -120,
            uptimeSeconds: 3600,
            rxAirtimeSeconds: 100,
            packetsSent: 500,
            packetsReceived: 1000
        )

        #expect(id != nil)
    }

    @Test("Save snapshot is throttled within 15 minutes")
    func throttledSnapshot() async throws {
        let (service, _) = try await createTestService()

        let first = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: 8.5,
            lastRSSI: -87,
            noiseFloor: -120,
            uptimeSeconds: nil,
            rxAirtimeSeconds: nil,
            packetsSent: nil,
            packetsReceived: nil
        )
        #expect(first != nil)

        let second = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3900,
            lastSNR: 9.0,
            lastRSSI: -85,
            noiseFloor: -118,
            uptimeSeconds: nil,
            rxAirtimeSeconds: nil,
            packetsSent: nil,
            packetsReceived: nil
        )
        #expect(second == nil, "Second snapshot should be throttled")
    }

    @Test("Different nodes are not throttled against each other")
    func differentNodesNotThrottled() async throws {
        let (service, _) = try await createTestService()
        let otherKey = Data(repeating: 0x99, count: 32)

        let first = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        #expect(first != nil)

        let second = await service.saveStatusSnapshot(
            nodePublicKey: otherKey,
            batteryMillivolts: 3700,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        #expect(second != nil, "Different node should not be throttled")
    }

    @Test("Enrich snapshot with neighbors")
    func enrichWithNeighbors() async throws {
        let (service, store) = try await createTestService()

        let id = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        guard let snapshotID = id else {
            Issue.record("Expected snapshot ID")
            return
        }

        let neighbors = [
            NeighborSnapshotEntry(publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04]), snr: 5.5, secondsAgo: 30)
        ]
        await service.enrichWithNeighbors(neighbors, snapshotID: snapshotID)

        let latest = try await store.fetchLatestNodeStatusSnapshot(nodePublicKey: testPublicKey)
        #expect(latest?.neighborSnapshots?.count == 1)
        #expect(latest?.neighborSnapshots?.first?.snr == 5.5)
    }

    @Test("Enrich snapshot with telemetry")
    func enrichWithTelemetry() async throws {
        let (service, store) = try await createTestService()

        let id = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        guard let snapshotID = id else {
            Issue.record("Expected snapshot ID")
            return
        }

        let telemetry = [
            TelemetrySnapshotEntry(channel: 0, type: "temperature", value: 32.5)
        ]
        await service.enrichWithTelemetry(telemetry, snapshotID: snapshotID)

        let latest = try await store.fetchLatestNodeStatusSnapshot(nodePublicKey: testPublicKey)
        #expect(latest?.telemetryEntries?.count == 1)
        #expect(latest?.telemetryEntries?.first?.value == 32.5)
    }

    @Test("Fetch previous snapshot returns correct result")
    func previousSnapshot() async throws {
        let (service, store) = try await createTestService()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3700,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        try await Task.sleep(for: .milliseconds(10))
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        let previous = await service.previousSnapshot(for: testPublicKey, before: .now)
        #expect(previous?.batteryMillivolts == 3850)
    }

    @Test("Fetch snapshots returns ascending order")
    func fetchSnapshotsOrdering() async throws {
        let (service, store) = try await createTestService()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3600,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        try await Task.sleep(for: .milliseconds(10))
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        let snapshots = await service.fetchSnapshots(for: testPublicKey)
        #expect(snapshots.count == 2)
        #expect(snapshots[0].batteryMillivolts == 3600)
        #expect(snapshots[1].batteryMillivolts == 3800)
    }

    @Test("Prune only deletes snapshots older than cutoff")
    func pruneOldSnapshots() async throws {
        let (service, store) = try await createTestService()

        // Save an "old" snapshot by writing directly to the store (bypass throttle)
        let oldID = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3600,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        // Save a "recent" snapshot
        try await Task.sleep(for: .milliseconds(10))
        let recentID = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        // Prune with a cutoff between the two snapshots (delete the old one)
        let cutoff = Date.now.addingTimeInterval(-0.005) // 5ms ago
        await service.pruneOldSnapshots(olderThan: cutoff)

        let remaining = await service.fetchSnapshots(for: testPublicKey)
        #expect(remaining.count == 1, "Old snapshot should be pruned, recent should remain")
        #expect(remaining.first?.id == recentID)
    }

    @Test("Prune with future cutoff does not delete recent snapshots")
    func prunePreservesRecentSnapshots() async throws {
        let (service, store) = try await createTestService()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3850,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        // Prune with a cutoff 1 year ago — recent data should survive
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        await service.pruneOldSnapshots(olderThan: oneYearAgo)

        let remaining = await service.fetchSnapshots(for: testPublicKey)
        #expect(remaining.count == 1, "Recent snapshot should not be pruned")
    }

    @Test("Fetch snapshots with since filter")
    func fetchSnapshotsSinceDate() async throws {
        let (service, store) = try await createTestService()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3600,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        try await Task.sleep(for: .milliseconds(10))

        let cutoff = Date.now

        try await Task.sleep(for: .milliseconds(10))
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        let snapshots = await service.fetchSnapshots(for: testPublicKey, since: cutoff)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].batteryMillivolts == 3800)
    }

    // MARK: - Round-trip enrichment tests

    @Test("Enrichment data survives save -> enrich -> fetchAll round-trip")
    func enrichmentRoundTrip() async throws {
        let (service, store) = try await createTestService()

        // Save two snapshots directly to the store (bypass throttle)
        let id1 = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3600,
            lastSNR: 7.0, lastRSSI: -90, noiseFloor: -120,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        try await Task.sleep(for: .milliseconds(10))
        let id2 = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3800,
            lastSNR: 8.5, lastRSSI: -85, noiseFloor: -118,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        // Enrich both with telemetry
        let telemetry1 = [TelemetrySnapshotEntry(channel: 0, type: "temperature", value: 25.0)]
        let telemetry2 = [TelemetrySnapshotEntry(channel: 0, type: "temperature", value: 30.0)]
        await service.enrichWithTelemetry(telemetry1, snapshotID: id1)
        await service.enrichWithTelemetry(telemetry2, snapshotID: id2)

        // Enrich both with neighbors
        let neighbors1 = [NeighborSnapshotEntry(publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04]), snr: 5.0, secondsAgo: 60)]
        let neighbors2 = [NeighborSnapshotEntry(publicKeyPrefix: Data([0x05, 0x06, 0x07, 0x08]), snr: 9.0, secondsAgo: 10)]
        await service.enrichWithNeighbors(neighbors1, snapshotID: id1)
        await service.enrichWithNeighbors(neighbors2, snapshotID: id2)

        // Fetch all via the method used by history views
        let snapshots = await service.fetchSnapshots(for: testPublicKey)
        #expect(snapshots.count == 2)

        // Verify enrichment data persisted on snapshot 1
        #expect(snapshots[0].telemetryEntries?.count == 1, "Snapshot 1 telemetry should persist")
        #expect(snapshots[0].telemetryEntries?.first?.value == 25.0)
        #expect(snapshots[0].neighborSnapshots?.count == 1, "Snapshot 1 neighbors should persist")
        #expect(snapshots[0].neighborSnapshots?.first?.snr == 5.0)

        // Verify enrichment data persisted on snapshot 2
        #expect(snapshots[1].telemetryEntries?.count == 1, "Snapshot 2 telemetry should persist")
        #expect(snapshots[1].telemetryEntries?.first?.value == 30.0)
        #expect(snapshots[1].neighborSnapshots?.count == 1, "Snapshot 2 neighbors should persist")
        #expect(snapshots[1].neighborSnapshots?.first?.snr == 9.0)
    }

    @Test("Enrichment via service.saveStatusSnapshot -> enrich -> fetchSnapshots round-trip")
    func enrichmentViaServiceRoundTrip() async throws {
        let (service, _) = try await createTestService()

        // Save first snapshot through the service (not throttled)
        let id1 = await service.saveStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3700,
            lastSNR: 7.0, lastRSSI: -90, noiseFloor: -120,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )
        guard let snapshotID = id1 else {
            Issue.record("First snapshot should not be throttled")
            return
        }

        // Enrich with telemetry and neighbors
        let telemetry = [
            TelemetrySnapshotEntry(channel: 0, type: "temperature", value: 28.5),
            TelemetrySnapshotEntry(channel: 1, type: "humidity", value: 65.0),
        ]
        let neighbors = [
            NeighborSnapshotEntry(publicKeyPrefix: Data([0xAA, 0xBB, 0xCC, 0xDD]), snr: 6.5, secondsAgo: 45),
        ]
        await service.enrichWithTelemetry(telemetry, snapshotID: snapshotID)
        await service.enrichWithNeighbors(neighbors, snapshotID: snapshotID)

        // Fetch via fetchSnapshots (history view path)
        let snapshots = await service.fetchSnapshots(for: testPublicKey)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].telemetryEntries?.count == 2, "Both telemetry entries should persist")
        #expect(snapshots[0].neighborSnapshots?.count == 1, "Neighbor entry should persist")
    }
}
