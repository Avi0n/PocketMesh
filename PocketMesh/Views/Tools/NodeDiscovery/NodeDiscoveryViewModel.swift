import MeshCore
import OSLog
import PocketMeshServices
import SwiftUI

// MARK: - Filter & Sort

enum NodeDiscoveryFilter: String, CaseIterable {
    case repeaters
    case sensors

    var filterValue: UInt8 {
        switch self {
        case .repeaters: 0x04
        case .sensors: 0x10
        }
    }

    var localizedTitle: String {
        switch self {
        case .repeaters: L10n.Tools.Tools.NodeDiscovery.repeaters
        case .sensors: L10n.Tools.Tools.NodeDiscovery.sensors
        }
    }
}

enum NodeDiscoverySortOrder: String, CaseIterable {
    case snr
    case name

    var localizedTitle: String {
        switch self {
        case .snr: L10n.Tools.Tools.NodeDiscovery.sortSignal
        case .name: L10n.Tools.Tools.NodeDiscovery.sortName
        }
    }
}

// MARK: - Result

struct NodeDiscoveryResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let publicKey: Data
    let snr: Double
    let snrIn: Double
    let rssi: Int
    let scanFilter: NodeDiscoveryFilter
    let receivedAt: Date
}

// MARK: - View Model

@Observable
@MainActor
final class NodeDiscoveryViewModel {
    private static let logger = Logger(subsystem: "com.pocketmesh", category: "NodeDiscoveryViewModel")
    private static let scanDuration: Duration = .seconds(15)

    // MARK: - Published state

    var results: [NodeDiscoveryResult] = []
    var isScanning = false
    var errorMessage: String?
    var filter: NodeDiscoveryFilter = .repeaters
    var sortOrder: NodeDiscoverySortOrder = .snr

    var scanStartHapticTrigger = 0
    var scanSuccessHapticTrigger = 0
    var scanEmptyHapticTrigger = 0

    // MARK: - Dependencies

    private var session: MeshCoreSession?
    private var dataStore: PersistenceStore?
    private var deviceID: UUID?

    // MARK: - Tasks

    private var scanTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Name resolution cache

    private var namesByKey: [Data: String] = [:]

    // MARK: - Configuration

    func configure(appState: AppState) {
        self.session = appState.services?.session
        self.dataStore = appState.offlineDataStore
        self.deviceID = appState.connectedDevice?.id
    }

    // MARK: - Scan

    func scan() {
        guard let session else {
            errorMessage = L10n.Tools.Tools.NodeDiscovery.notConnectedDescription(filter.localizedTitle)
            return
        }

        guard let deviceID else { return }

        stopScan()
        results.removeAll { $0.scanFilter == filter }
        errorMessage = nil
        isScanning = true
        scanStartHapticTrigger += 1

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                // Pre-load name resolution data
                await self.loadNameResolutionData(deviceID: deviceID)

                // Send discovery request
                let tag = try await session.sendNodeDiscoverRequest(
                    filter: self.filter.filterValue,
                    prefixOnly: false
                )
                let tagData = withUnsafeBytes(of: tag.littleEndian) { Data($0) }

                // Start timeout that cancels the scan task
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.scanDuration)
                    self?.scanTask?.cancel()
                }

                // Listen for responses
                let events = await session.events()
                for await event in events {
                    guard !Task.isCancelled else { break }

                    if case .discoverResponse(let response) = event,
                       response.tag == tagData {
                        self.appendOrUpdateResult(from: response)
                    }
                }
            } catch is CancellationError {
                // Normal timeout cancellation — not an error
            } catch {
                Self.logger.error("Node discovery failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
            }

            self.finishScan()
        }
    }

    func stopScan() {
        timeoutTask?.cancel()
        timeoutTask = nil
        scanTask?.cancel()
        scanTask = nil
        if isScanning {
            finishScan()
        }
    }

    // MARK: - Sorted results

    var sortedResults: [NodeDiscoveryResult] {
        let filtered = results.filter { $0.scanFilter == filter }
        return switch sortOrder {
        case .snr:
            filtered.sorted { $0.snr > $1.snr }
        case .name:
            filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - Private

    private func loadNameResolutionData(deviceID: UUID) async {
        guard let dataStore else { return }
        do {
            // Load discovered nodes first, then contacts — contacts take priority
            let nodes = try await dataStore.fetchDiscoveredNodes(deviceID: deviceID)
            namesByKey = Dictionary(
                nodes.map { ($0.publicKey, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
            let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
            for contact in contacts {
                namesByKey[contact.publicKey] = contact.name
            }
        } catch {
            Self.logger.error("Failed to load name resolution data: \(error.localizedDescription)")
        }
    }

    private func resolveName(for publicKey: Data) -> String {
        if let name = namesByKey[publicKey] {
            return name
        }
        let hexPrefix = publicKey.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "\(L10n.Tools.Tools.NodeDiscovery.unknownNode) (\(hexPrefix))"
    }

    private func appendOrUpdateResult(from response: DiscoverResponse) {
        let result = NodeDiscoveryResult(
            name: resolveName(for: response.publicKey),
            publicKey: response.publicKey,
            snr: response.snr,
            snrIn: response.snrIn,
            rssi: response.rssi,
            scanFilter: filter,
            receivedAt: Date()
        )
        if let existingIndex = results.firstIndex(where: { $0.publicKey == response.publicKey && $0.scanFilter == filter }) {
            results[existingIndex] = result
        } else {
            results.append(result)
        }
    }

    private func finishScan() {
        isScanning = false
        if results.contains(where: { $0.scanFilter == filter }) {
            scanSuccessHapticTrigger += 1
        } else {
            scanEmptyHapticTrigger += 1
        }
    }
}
