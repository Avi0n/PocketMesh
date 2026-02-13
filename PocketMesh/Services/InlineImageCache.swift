import Foundation
import ImageIO
import OSLog

/// Result of an inline image fetch
enum InlineImageResult: Sendable {
    case loaded(Data)
    case loading
    case failed
}

/// Actor-based cache for fetching and caching inline image data.
/// Uses NSCache for memory management and AsyncSemaphore for concurrency limiting.
actor InlineImageCache {
    static let shared = InlineImageCache()

    private let logger = Logger(subsystem: "com.pocketmesh", category: "InlineImageCache")

    private let memoryCache = NSCache<NSString, CachedImageData>()
    private let fetchSemaphore = AsyncSemaphore(value: 3)
    private var failedURLs: Set<String> = []
    private var inFlightURLs: Set<String> = []

    private static let maxEntryCount = 50
    private static let maxTotalCostBytes = 50 * 1024 * 1024 // 50MB
    private static let maxDownloadBytes = 10 * 1024 * 1024  // 10MB per image

    init() {
        memoryCache.countLimit = Self.maxEntryCount
        memoryCache.totalCostLimit = Self.maxTotalCostBytes
    }

    /// Fetches image data for the given URL, returning cached data when available.
    func fetchImageData(for url: URL) async -> InlineImageResult {
        let key = url.absoluteString

        // Check negative cache
        if failedURLs.contains(key) {
            return .failed
        }

        // Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return .loaded(cached.data)
        }

        // Prevent duplicate in-flight fetches
        guard !inFlightURLs.contains(key) else {
            return .loading
        }

        inFlightURLs.insert(key)
        await fetchSemaphore.wait()

        // Single exit path after semaphore acquisition
        let result: InlineImageResult
        if let cached = memoryCache.object(forKey: key as NSString) {
            result = .loaded(cached.data)
        } else if Task.isCancelled {
            result = .failed
        } else {
            result = await performFetch(for: url, key: key)
        }

        await fetchSemaphore.signal()
        inFlightURLs.remove(key)
        return result
    }

    /// Performs the HTTP fetch, validates the response, and caches the result.
    private func performFetch(for url: URL, key: String) async -> InlineImageResult {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.debug("Non-success HTTP status for image: \(url.absoluteString)")
                failedURLs.insert(key)
                return .failed
            }

            guard data.count <= Self.maxDownloadBytes else {
                logger.debug("Image too large (\(data.count) bytes): \(url.absoluteString)")
                failedURLs.insert(key)
                return .failed
            }

            // Lightweight validation: check that ImageIO recognizes the data as an image
            guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                logger.debug("Data is not a valid image: \(url.absoluteString)")
                failedURLs.insert(key)
                return .failed
            }

            memoryCache.setObject(CachedImageData(data), forKey: key as NSString, cost: data.count)
            return .loaded(data)

        } catch {
            if !Task.isCancelled {
                logger.debug("Failed to fetch image: \(error.localizedDescription)")
                failedURLs.insert(key)
            }
            return .failed
        }
    }

}

/// Wrapper class for NSCache (requires reference type)
private final class CachedImageData: @unchecked Sendable {
    let data: Data
    init(_ data: Data) { self.data = data }
}
