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
}
