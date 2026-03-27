import Foundation
import MapLibre
import Network
import os

enum OfflineMapLayer: String, Codable {
    case base
    case topo

    var label: String {
        switch self {
        case .base: L10n.Settings.OfflineMaps.Layer.base
        case .topo: L10n.Settings.OfflineMaps.Layer.topo
        }
    }

    var maxDownloadZoom: Double {
        switch self {
        case .base: 14
        case .topo: 17
        }
    }

    var styleURL: URL? {
        switch self {
        case .base:
            URL(string: MapTileURLs.openFreeMapLiberty)
        case .topo:
            Bundle.main.url(forResource: "topo-offline", withExtension: "json")
        }
    }
}

struct OfflinePackMetadata: Codable {
    let name: String
    let createdAt: Date
    var layer: OfflineMapLayer

    init(name: String, createdAt: Date, layer: OfflineMapLayer = .base) {
        self.name = name
        self.createdAt = createdAt
        self.layer = layer
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        layer = try container.decodeIfPresent(OfflineMapLayer.self, forKey: .layer) ?? .base
    }
}

enum OfflineMapError: LocalizedError {
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace:
            L10n.Settings.OfflineMaps.Error.insufficientDiskSpace
        }
    }
}

@MainActor @Observable
final class OfflineMapService {
    private static let logger = Logger(subsystem: "com.mc1", category: "OfflineMapService")

    private static let minimumDiskSpaceBytes: Int64 = 100_000_000

    private(set) var packs: [OfflinePack] = []
    private(set) var databaseSize: Int64 = 0
    private(set) var isNetworkAvailable = true
    private(set) var lastPackError: String?

    private let monitor = NWPathMonitor()
    private var observationTasks: [Task<Void, Never>] = []
    private var pendingLoadTask: Task<Void, Never>?
    private var highWaterMarks: [ObjectIdentifier: Double] = [:]
    private var byteSnapshots: [ObjectIdentifier: (bytes: UInt64, time: ContinuousClock.Instant)] = [:]
    private var downloadSpeeds: [ObjectIdentifier: Int64] = [:]
    private var metadataCache: [ObjectIdentifier: OfflinePackMetadata?] = [:]
    private var deletingPackIDs: Set<ObjectIdentifier> = []

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
                    self?.lastPackError = error.localizedDescription
                }
            }
        })
        observationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .MLNOfflinePackMaximumMapboxTilesReached
            ) {
                Self.logger.warning("Offline pack tile limit reached")
                self?.lastPackError = L10n.Settings.OfflineMaps.Error.tileLimitReached
            }
        })

        excludeDatabaseFromBackup()
        loadPacks()
        updateDatabaseSize()

        // MLNOfflineStorage.shared.packs may be nil until async DB load completes.
        // Retry once after a delay to catch late initialization.
        if MLNOfflineStorage.shared.packs == nil {
            observationTasks.append(Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                self?.loadPacks()
            })
        }
    }

    isolated deinit {
        monitor.cancel()
        pendingLoadTask?.cancel()
        for task in observationTasks {
            task.cancel()
        }
    }

    func hasCompletedPack(for layer: OfflineMapLayer) -> Bool {
        packs.contains { $0.layer == layer && $0.isComplete }
    }

    func loadPacks() {
        let mlnPacks = MLNOfflineStorage.shared.packs ?? []
        let currentIDs = Set(mlnPacks.map { ObjectIdentifier($0) })
        let now = ContinuousClock.now

        // Remove tracking data for deleted packs
        highWaterMarks = highWaterMarks.filter { currentIDs.contains($0.key) }
        byteSnapshots = byteSnapshots.filter { currentIDs.contains($0.key) }
        downloadSpeeds = downloadSpeeds.filter { currentIDs.contains($0.key) }
        metadataCache = metadataCache.filter { currentIDs.contains($0.key) }

        packs = mlnPacks.map { mlnPack in
            let packID = ObjectIdentifier(mlnPack)
            let previousFraction = highWaterMarks[packID] ?? 0
            let currentBytes = mlnPack.progress.countOfBytesCompleted

            if let previous = byteSnapshots[packID] {
                let elapsed = now - previous.time
                let seconds = elapsed / .seconds(1)
                if seconds > 0.5, currentBytes > previous.bytes {
                    downloadSpeeds[packID] = Int64(Double(currentBytes - previous.bytes) / seconds)
                } else if currentBytes == previous.bytes {
                    downloadSpeeds[packID] = 0
                }
            }
            byteSnapshots[packID] = (bytes: currentBytes, time: now)

            let speed = downloadSpeeds[packID]
            if metadataCache[packID] == nil {
                metadataCache[packID] = try? JSONDecoder().decode(OfflinePackMetadata.self, from: mlnPack.context)
            }
            let pack = OfflinePack(pack: mlnPack, metadata: metadataCache[packID] ?? nil, previousFraction: previousFraction, downloadSpeed: speed)
            highWaterMarks[packID] = pack.completedFraction
            return pack
        }

        for mlnPack in mlnPacks where mlnPack.state == .unknown {
            mlnPack.requestProgress()
        }
    }

    private func updateDatabaseSize() {
        let url = MLNOfflineStorage.shared.databaseURL
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        databaseSize = Int64(size)
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

    // Note: active offline downloads share MapLibre's internal FIFO request queue
    // with the interactive map renderer. Large downloads may degrade live map tile
    // loading. Consider suspending packs during active map interaction if needed.
    func downloadRegion(
        name: String,
        bounds: MLNCoordinateBounds,
        layers: Set<OfflineMapLayer>,
        minZoom: Double = 10
    ) async throws {
        let values = try URL.documentsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < Self.minimumDiskSpaceBytes {
            throw OfflineMapError.insufficientDiskSpace
        }

        let encoder = JSONEncoder()
        let now = Date.now

        for layer in layers {
            guard let styleURL = layer.styleURL else {
                Self.logger.error("Missing style URL for layer: \(layer.rawValue)")
                continue
            }

            let region = MLNTilePyramidOfflineRegion(
                styleURL: styleURL,
                bounds: bounds,
                fromZoomLevel: minZoom,
                toZoomLevel: layer.maxDownloadZoom
            )

            let metadata = OfflinePackMetadata(name: name, createdAt: now, layer: layer)
            let context = try encoder.encode(metadata)

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
        }
        loadPacks()
        updateDatabaseSize()
    }

    func deletePack(_ pack: OfflinePack) async {
        guard deletingPackIDs.insert(pack.id).inserted else { return }
        defer { deletingPackIDs.remove(pack.id) }

        await withCheckedContinuation { continuation in
            MLNOfflineStorage.shared.removePack(pack.mlnPack) { error in
                if let error {
                    Self.logger.error("Failed to delete offline pack: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
        highWaterMarks.removeValue(forKey: pack.id)
        byteSnapshots.removeValue(forKey: pack.id)
        downloadSpeeds.removeValue(forKey: pack.id)
        loadPacks()
        updateDatabaseSize()
    }

    func pausePack(_ pack: OfflinePack) {
        pack.mlnPack.suspend()
        loadPacks()
    }

    func resumePack(_ pack: OfflinePack) {
        pack.mlnPack.resume()
        loadPacks()
    }

    func resumeAllPacks() {
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            if pack.state == .inactive {
                pack.resume()
            }
        }
        loadPacks()
    }

    func clearLastPackError() {
        lastPackError = nil
    }

    /// Estimated download size using per-zoom average byte sizes.
    nonisolated static func estimatedDownloadSize(
        bounds: MLNCoordinateBounds,
        minZoom: Int,
        maxZoom: Int,
        layer: OfflineMapLayer = .base
    ) -> Int64 {
        let bytesPerTile: [Int: Int64]
        switch layer {
        case .base:
            // Average compressed vector tile sizes for OpenFreeMap (OpenMapTiles schema, max z14).
            bytesPerTile = [
                10: 2_000, 11: 3_000, 12: 5_000,
                13: 8_000, 14: 12_000,
            ]
        case .topo:
            // OpenTopoMap PNG raster tiles (256px, max z17).
            bytesPerTile = [
                10: 15_000, 11: 18_000, 12: 22_000,
                13: 25_000, 14: 30_000, 15: 35_000,
                16: 40_000, 17: 45_000,
            ]
        }

        var total: Int64 = 0
        for z in minZoom...maxZoom {
            let n = Double(1 << z)
            let xMin = Int(floor((bounds.sw.longitude + 180) / 360 * n))
            let xMax = Int(floor((bounds.ne.longitude + 180) / 360 * n))

            let latRadNE = bounds.ne.latitude * .pi / 180
            let latRadSW = bounds.sw.latitude * .pi / 180
            let yMin = Int(floor((1 - log(tan(latRadNE) + 1 / cos(latRadNE)) / .pi) / 2 * n))
            let yMax = Int(floor((1 - log(tan(latRadSW) + 1 / cos(latRadSW)) / .pi) / 2 * n))

            let tileCount = (abs(xMax - xMin) + 1) * (abs(yMax - yMin) + 1)
            total += Int64(tileCount) * (bytesPerTile[z] ?? 10_000)
        }
        return total
    }

    private func excludeDatabaseFromBackup() {
        var url = MLNOfflineStorage.shared.databaseURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            Self.logger.error("Failed to exclude offline database from backup: \(error.localizedDescription)")
        }
    }
}

struct OfflinePack: Identifiable {
    let id: ObjectIdentifier
    fileprivate let mlnPack: MLNOfflinePack
    let name: String
    let createdAt: Date?
    let layer: OfflineMapLayer
    let completedFraction: Double
    let downloadSpeed: Int64?

    private let progress: MLNOfflinePackProgress
    private let state: MLNOfflinePackState

    var completedBytes: UInt64 { progress.countOfBytesCompleted }
    var isComplete: Bool { state == .complete }
    var isPaused: Bool { state == .inactive }

    init(pack: MLNOfflinePack, metadata: OfflinePackMetadata?, previousFraction: Double = 0, downloadSpeed: Int64? = nil) {
        self.id = ObjectIdentifier(pack)
        self.mlnPack = pack
        self.progress = pack.progress
        self.state = pack.state

        let rawFraction: Double
        if state == .complete {
            rawFraction = 1
        } else if progress.countOfResourcesExpected > 0 {
            rawFraction = Double(progress.countOfResourcesCompleted) / Double(progress.countOfResourcesExpected)
        } else {
            rawFraction = 0
        }
        self.completedFraction = max(rawFraction, previousFraction)
        self.downloadSpeed = state == .active ? downloadSpeed : nil

        if let metadata {
            self.name = metadata.name
            self.createdAt = metadata.createdAt
            self.layer = metadata.layer
        } else {
            self.name = L10n.Settings.OfflineMaps.unknownRegion
            self.createdAt = nil
            self.layer = .base
        }
    }
}
