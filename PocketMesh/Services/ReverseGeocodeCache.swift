import CoreLocation
import Foundation

actor ReverseGeocodeCache {
    static let shared = ReverseGeocodeCache()

    private var cache: [String: String] = [:]
    private var pendingKeys: Set<String> = []
    private var queue: [(key: String, location: CLLocation, continuation: CheckedContinuation<String?, Never>)] = []
    private var isProcessing = false

    private static var cacheFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reverse_geocode_cache.json")
    }

    private init() {
        cache = Self.loadFromDisk()
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "geocodingEnabled") as? Bool ?? true
    }

    func locality(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = cacheKey(for: coordinate)

        if let cached = cache[key] {
            return cached
        }

        guard Self.isEnabled else { return nil }
        guard !pendingKeys.contains(key) else { return nil }
        pendingKeys.insert(key)

        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        return await withCheckedContinuation { continuation in
            queue.append((key: key, location: location, continuation: continuation))
            processQueue()
        }
    }

    private func processQueue() {
        guard !isProcessing, let next = queue.first else { return }
        isProcessing = true
        queue.removeFirst()

        Task {
            let result = await geocode(key: next.key, location: next.location)
            next.continuation.resume(returning: result)
            isProcessing = false
            pendingKeys.remove(next.key)
            processQueue()
        }
    }

    private func geocode(key: String, location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let result = formatLocality(from: placemark)
                if let result {
                    cache[key] = result
                    saveToDisk()
                }
                return result
            }
        } catch {}
        return nil
    }

    private func formatLocality(from placemark: CLPlacemark) -> String? {
        let city = placemark.locality
        let state = placemark.administrativeArea

        switch (city, state) {
        case let (city?, state?):
            return "\(city), \(state)"
        case let (city?, nil):
            return city
        case let (nil, state?):
            return state
        default:
            return nil
        }
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lon = (coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }

    // MARK: - Disk Persistence

    private static func loadFromDisk() -> [String: String] {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
    }
}
