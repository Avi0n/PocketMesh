import Foundation
import OSLog
import PocketMeshServices

/// Two-tier cache for link previews with URL-based deduplication.
/// Uses actor isolation for thread safety without blocking the main thread.
/// Limits concurrent LPMetadataProvider instances to prevent WKWebView spawn bursts.
actor LinkPreviewCache: LinkPreviewCaching {
    private let logger = Logger(subsystem: "com.pocketmesh", category: "LinkPreviewCache")
    private let memoryCache = NSCache<NSString, CachedPreview>()
    private let service = LinkPreviewService()
    private nonisolated let preferences = LinkPreviewPreferences()

    /// URLs currently being fetched (prevents duplicate in-flight requests)
    private var inFlightFetches: Set<String> = []

    /// URLs that have been fetched but have no preview available
    private var noPreviewAvailable: Set<String> = []

    /// Semaphore to limit concurrent LPMetadataProvider instances (max 3)
    /// Each LPMetadataProvider spawns WKWebView on main thread
    private let fetchSemaphore = AsyncSemaphore(value: 3)

    init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func preview(
        for url: URL,
        using dataStore: any PersistenceStoreProtocol,
        isChannelMessage: Bool
    ) async -> LinkPreviewResult {
        let urlString = url.absoluteString

        // Check negative cache first
        if noPreviewAvailable.contains(urlString) {
            return .noPreviewAvailable
        }

        // Tier 1: Memory cache (instant)
        if let cached = memoryCache.object(forKey: urlString as NSString) {
            return .loaded(cached.dto)
        }

        // Tier 2: Database lookup
        do {
            if let persisted = try await dataStore.fetchLinkPreview(url: urlString) {
                let cost = (persisted.imageData?.count ?? 0) + (persisted.iconData?.count ?? 0)
                memoryCache.setObject(CachedPreview(persisted), forKey: urlString as NSString, cost: cost)
                return .loaded(persisted)
            }
        } catch {
            logger.error("Failed to fetch link preview from database: \(error.localizedDescription)")
        }

        // Check preferences before network fetch
        guard preferences.shouldAutoResolve(isChannelMessage: isChannelMessage) else {
            return .disabled
        }

        // Prevent duplicate fetches
        guard !inFlightFetches.contains(urlString) else {
            return .loading
        }

        // Tier 3: Network fetch with concurrency limiting
        return await fetchFromNetwork(url: url, urlString: urlString, dataStore: dataStore)
    }

    func manualFetch(
        for url: URL,
        using dataStore: any PersistenceStoreProtocol
    ) async -> LinkPreviewResult {
        let urlString = url.absoluteString

        // Check cache first (but allow retry for negative cache)
        if let cached = memoryCache.object(forKey: urlString as NSString) {
            return .loaded(cached.dto)
        }

        // Check database
        do {
            if let persisted = try await dataStore.fetchLinkPreview(url: urlString) {
                let cost = (persisted.imageData?.count ?? 0) + (persisted.iconData?.count ?? 0)
                memoryCache.setObject(CachedPreview(persisted), forKey: urlString as NSString, cost: cost)
                return .loaded(persisted)
            }
        } catch {
            logger.error("Failed to fetch link preview from database: \(error.localizedDescription)")
        }

        // Prevent duplicate fetches
        guard !inFlightFetches.contains(urlString) else {
            return .loading
        }

        // Clear from negative cache on manual retry
        noPreviewAvailable.remove(urlString)

        return await fetchFromNetwork(url: url, urlString: urlString, dataStore: dataStore)
    }

    private func fetchFromNetwork(
        url: URL,
        urlString: String,
        dataStore: any PersistenceStoreProtocol
    ) async -> LinkPreviewResult {
        inFlightFetches.insert(urlString)

        // Wait for semaphore to limit concurrent fetches
        await fetchSemaphore.wait()

        let metadata = await service.fetchMetadata(for: url)

        // Signal semaphore before cleanup
        fetchSemaphore.signal()
        inFlightFetches.remove(urlString)

        guard let metadata else {
            // Cache negative result to avoid repeated fetch attempts
            noPreviewAvailable.insert(urlString)
            return .noPreviewAvailable
        }

        let dto = LinkPreviewDataDTO(
            url: urlString,
            title: metadata.title,
            imageData: metadata.imageData,
            iconData: metadata.iconData
        )

        // Cache in memory with cost based on image sizes
        let cost = (dto.imageData?.count ?? 0) + (dto.iconData?.count ?? 0)
        memoryCache.setObject(CachedPreview(dto), forKey: urlString as NSString, cost: cost)

        // Persist to database
        do {
            try await dataStore.saveLinkPreview(dto)
        } catch {
            logger.error("Failed to save link preview to database: \(error.localizedDescription)")
        }

        return .loaded(dto)
    }

    func isFetching(_ url: URL) async -> Bool {
        inFlightFetches.contains(url.absoluteString)
    }

    func cachedPreview(for url: URL) async -> LinkPreviewDataDTO? {
        memoryCache.object(forKey: url.absoluteString as NSString)?.dto
    }
}

/// Wrapper class for NSCache (requires reference type)
private final class CachedPreview: @unchecked Sendable {
    let dto: LinkPreviewDataDTO
    init(_ dto: LinkPreviewDataDTO) { self.dto = dto }
}

/// Simple async semaphore for limiting concurrent operations
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.count = value
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    nonisolated func signal() {
        Task { await _signal() }
    }

    private func _signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}
