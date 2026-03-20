import MapLibre
import Network
import os

struct OfflinePackMetadata: Codable {
    let name: String
    let createdAt: Date
}

@MainActor @Observable
final class OfflineMapService {
    static let logger = Logger(subsystem: "com.pocketmesh", category: "OfflineMapService")

    private(set) var packs: [OfflinePack] = []
    private(set) var isNetworkAvailable = true

    private let monitor = NWPathMonitor()
    private var observationTasks: [Task<Void, Never>] = []
    private var pendingLoadTask: Task<Void, Never>?

    init() {
        let networkStream = AsyncStream<NWPath> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0) }
            // NWPathMonitor requires a DispatchQueue; no Swift concurrency alternative exists.
            monitor.start(queue: .global(qos: .utility))
        }
        observationTasks.append(Task { [weak self] in
            for await path in networkStream {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        })

        observationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .MLNOfflinePackProgressChanged) {
                self?.scheduleLoadPacks()
            }
        })
        observationTasks.append(Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .MLNOfflinePackError) {
                if let error = notification.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError {
                    Self.logger.warning("Offline pack error: \(error.localizedDescription)")
                }
            }
        })

        loadPacks()
    }

    isolated deinit {
        monitor.cancel()
        pendingLoadTask?.cancel()
        for task in observationTasks {
            task.cancel()
        }
    }

    func loadPacks() {
        packs = (MLNOfflineStorage.shared.packs ?? []).map { OfflinePack(pack: $0) }
    }

    /// Coalesces rapid progress notifications into a single `loadPacks()` call.
    private func scheduleLoadPacks() {
        pendingLoadTask?.cancel()
        pendingLoadTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            loadPacks()
        }
    }

    func downloadRegion(
        name: String,
        bounds: MLNCoordinateBounds,
        minZoom: Double = 10,
        maxZoom: Double = 15
    ) async throws {
        // swiftlint:disable:next force_unwrapping
        let styleURL = URL(string: MapTileURLs.openFreeMapLiberty)!
        let region = MLNTilePyramidOfflineRegion(
            styleURL: styleURL,
            bounds: bounds,
            fromZoomLevel: minZoom,
            toZoomLevel: maxZoom
        )

        let context = try JSONEncoder().encode(OfflinePackMetadata(name: name, createdAt: .now))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { pack, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    pack?.resume()
                    continuation.resume()
                }
            }
        }
        loadPacks()
    }

    func deletePack(_ pack: OfflinePack) async {
        await withCheckedContinuation { continuation in
            MLNOfflineStorage.shared.removePack(pack.mlnPack) { error in
                if let error {
                    Self.logger.error("Failed to delete offline pack: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
        loadPacks()
    }

    func resumeAllPacks() {
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            if pack.state == .inactive {
                pack.resume()
            }
        }
    }
}

struct OfflinePack: Identifiable {
    let id: ObjectIdentifier
    let mlnPack: MLNOfflinePack
    let name: String
    let createdAt: Date?
    let progress: MLNOfflinePackProgress
    let state: MLNOfflinePackState

    var completedFraction: Double {
        guard progress.countOfResourcesExpected > 0 else { return 0 }
        return Double(progress.countOfResourcesCompleted) / Double(progress.countOfResourcesExpected)
    }

    var completedBytes: UInt64 { progress.countOfBytesCompleted }
    var isComplete: Bool { state == .complete }

    init(pack: MLNOfflinePack) {
        self.id = ObjectIdentifier(pack)
        self.mlnPack = pack
        self.progress = pack.progress
        self.state = pack.state

        let context = pack.context
        if let metadata = try? JSONDecoder().decode(OfflinePackMetadata.self, from: context) {
            self.name = metadata.name
            self.createdAt = metadata.createdAt
        } else {
            self.name = L10n.Settings.OfflineMaps.unknownRegion
            self.createdAt = nil
        }
    }
}
