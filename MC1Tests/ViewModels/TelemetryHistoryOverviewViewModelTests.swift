import Foundation
import MeshCore
import Testing

@testable import MC1
@testable import MC1Services

@Suite("TelemetryHistoryOverviewViewModel Tests")
@MainActor
struct TelemetryHistoryOverviewViewModelTests {

    private let testPublicKey = Data(repeating: 0xAB, count: 32)
    private let testDeviceID = UUID()

    private func createStore() async throws -> PersistenceStore {
        let container = try PersistenceStore.createContainer(inMemory: true)
        return PersistenceStore(modelContainer: container)
    }

    private func createContactDTO(ocvPreset: String? = nil) -> ContactDTO {
        ContactDTO(
            id: UUID(),
            deviceID: testDeviceID,
            publicKey: testPublicKey,
            name: "Test Repeater",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0,
            ocvPreset: ocvPreset
        )
    }

    // MARK: - Loading

    @Test("loadData fetches snapshots from persistence store")
    func loadDataFetchesSnapshots() async throws {
        let store = try await createStore()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3800, lastSNR: 8.0, lastRSSI: -90,
            noiseFloor: -120, uptimeSeconds: 3600, rxAirtimeSeconds: 100,
            packetsSent: 500, packetsReceived: 1000
        )
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey,
            batteryMillivolts: 3750, lastSNR: 7.5, lastRSSI: -92,
            noiseFloor: -118, uptimeSeconds: 7200, rxAirtimeSeconds: 200,
            packetsSent: 600, packetsReceived: 1100
        )

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )

        #expect(viewModel.snapshots.count == 2)
    }

    @Test("loadData with no snapshots leaves empty array")
    func loadDataNoSnapshots() async throws {
        let store = try await createStore()

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )

        #expect(viewModel.snapshots.isEmpty)
    }

    // MARK: - OCV Resolution

    @Test("loadData resolves OCV from contact preset")
    func loadDataResolvesOCVFromContact() async throws {
        let store = try await createStore()

        let contact = createContactDTO(ocvPreset: OCVPreset.liFePO4.rawValue)
        try await store.saveContact(contact)

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )

        #expect(viewModel.ocvArray == OCVPreset.liFePO4.ocvArray)
    }

    @Test("loadData defaults to liIon when no contact found")
    func loadDataDefaultsToLiIon() async throws {
        let store = try await createStore()

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )

        #expect(viewModel.ocvArray == OCVPreset.liIon.ocvArray)
    }

    // MARK: - Filtering

    @Test("filteredSnapshots returns all when timeRange is .all")
    func filteredSnapshotsAll() async throws {
        let store = try await createStore()

        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey, batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )
        viewModel.timeRange = .all

        #expect(viewModel.filteredSnapshots.count == 1)
    }

    @Test("filteredSnapshots excludes old snapshots for .week range")
    func filteredSnapshotsWeek() async throws {
        let store = try await createStore()

        // Save an old snapshot (30 days ago)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        _ = try await store.saveNodeStatusSnapshot(
            timestamp: thirtyDaysAgo,
            nodePublicKey: testPublicKey, batteryMillivolts: 3600,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        // Save a recent snapshot
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey, batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        let viewModel = TelemetryHistoryOverviewViewModel()
        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )
        viewModel.timeRange = .week

        #expect(viewModel.filteredSnapshots.count == 1)
        #expect(viewModel.filteredSnapshots.first?.batteryMillivolts == 3800)
    }

    // MARK: - Computed Properties

    @Test("hasSnapshots reflects snapshot count")
    func hasSnapshots() async throws {
        let viewModel = TelemetryHistoryOverviewViewModel()
        #expect(!viewModel.hasSnapshots)

        let store = try await createStore()
        _ = try await store.saveNodeStatusSnapshot(
            nodePublicKey: testPublicKey, batteryMillivolts: 3800,
            lastSNR: nil, lastRSSI: nil, noiseFloor: nil,
            uptimeSeconds: nil, rxAirtimeSeconds: nil,
            packetsSent: nil, packetsReceived: nil
        )

        await viewModel.loadData(
            dataStore: store, publicKey: testPublicKey, deviceID: testDeviceID
        )
        #expect(viewModel.hasSnapshots)
    }
}
