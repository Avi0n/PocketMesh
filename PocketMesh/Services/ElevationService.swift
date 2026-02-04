import CoreLocation
import Foundation
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "ElevationService")

// MARK: - Errors

/// Errors from elevation service
enum ElevationServiceError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return L10n.Localizable.Common.Error.networkError(error.localizedDescription)
        case .invalidResponse:
            return L10n.Localizable.Common.Error.invalidResponse
        case .apiError(let message):
            return L10n.Localizable.Common.Error.apiError(message)
        case .noData:
            return L10n.Localizable.Common.Error.noElevationData
        }
    }
}

// MARK: - Protocol

/// Protocol for elevation data fetching (for testability)
protocol ElevationServiceProtocol: Sendable {
    func fetchElevation(at coordinate: CLLocationCoordinate2D) async throws -> Double
    func fetchElevations(along path: [CLLocationCoordinate2D]) async throws -> [ElevationSample]
}

// MARK: - Service

/// Service for fetching elevation data from Open-Meteo API
actor ElevationService: ElevationServiceProtocol {

    // MARK: - Constants

    private static let apiEndpoint = "https://api.open-meteo.com/v1/elevation"
    private static let maxPointsPerRequest = 100

    // MARK: - Sample Count Thresholds

    private static let thresholdUnder1km = 1_000.0
    private static let threshold1to5km = 5_000.0
    private static let threshold5to20km = 20_000.0

    private static let sampleCountUnder1km = 20
    private static let sampleCount1to5km = 50
    private static let sampleCount5to20km = 80
    private static let sampleCountOver20km = 100

    // MARK: - Dependencies

    private let session: URLSession

    // MARK: - Initialization

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Methods

    /// Fetch elevation for a single coordinate
    /// - Parameter coordinate: The coordinate to get elevation for
    /// - Returns: Elevation in meters above sea level
    func fetchElevation(at coordinate: CLLocationCoordinate2D) async throws -> Double {
        let samples = try await fetchElevations(along: [coordinate])
        guard let first = samples.first else {
            throw ElevationServiceError.noData
        }
        return first.elevation
    }

    /// Fetch elevations for multiple coordinates along a path
    /// - Parameter path: Array of coordinates to get elevations for
    /// - Returns: Array of elevation samples with distances calculated from first point
    func fetchElevations(along path: [CLLocationCoordinate2D]) async throws -> [ElevationSample] {
        guard !path.isEmpty else {
            throw ElevationServiceError.noData
        }

        var coordinatesToFetch = path

        // Subsample if exceeding max points, ensuring endpoints are preserved
        if coordinatesToFetch.count > Self.maxPointsPerRequest {
            logger.warning(
                "Requested \(path.count) elevation points, subsampling to \(Self.maxPointsPerRequest)"
            )
            coordinatesToFetch = subsample(path, targetCount: Self.maxPointsPerRequest)
        }

        // Build URL with query parameters (using POSIX locale to ensure dot decimal separator)
        let coordinateFormat = FloatingPointFormatStyle<Double>
            .number
            .locale(Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(6))
        let latitudes = coordinatesToFetch.map { $0.latitude.formatted(coordinateFormat) }.joined(separator: ",")
        let longitudes = coordinatesToFetch.map { $0.longitude.formatted(coordinateFormat) }.joined(separator: ",")

        guard var components = URLComponents(string: Self.apiEndpoint) else {
            throw ElevationServiceError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitudes),
            URLQueryItem(name: "longitude", value: longitudes)
        ]

        guard let url = components.url else {
            throw ElevationServiceError.invalidResponse
        }

        // Make request
        let data: Data
        do {
            let (responseData, response) = try await session.data(from: url)
            data = responseData

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ElevationServiceError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw ElevationServiceError.apiError("HTTP \(httpResponse.statusCode)")
            }
        } catch let error as ElevationServiceError {
            throw error
        } catch {
            throw ElevationServiceError.networkError(error)
        }

        // Parse response
        let elevations = try parseElevationResponse(data)

        guard elevations.count == coordinatesToFetch.count else {
            throw ElevationServiceError.invalidResponse
        }

        // Build elevation samples with distance from first point
        var samples: [ElevationSample] = []
        let startCoordinate = coordinatesToFetch[0]

        for (index, coordinate) in coordinatesToFetch.enumerated() {
            let distanceFromA = RFCalculator.distance(from: startCoordinate, to: coordinate)
            let sample = ElevationSample(
                coordinate: coordinate,
                elevation: elevations[index],
                distanceFromAMeters: distanceFromA
            )
            samples.append(sample)
        }

        return samples
    }

    // MARK: - Static Methods

    /// Generate evenly spaced coordinates between two points
    /// - Parameters:
    ///   - from: Starting coordinate (will be first in result)
    ///   - to: Ending coordinate (will be last in result)
    ///   - sampleCount: Number of samples to generate (minimum 2)
    /// - Returns: Array of evenly spaced coordinates including endpoints
    static func sampleCoordinates(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        sampleCount: Int
    ) -> [CLLocationCoordinate2D] {
        let count = max(2, min(sampleCount, maxPointsPerRequest))

        guard count >= 2 else {
            return [from, to]
        }

        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(count)

        for i in 0..<count {
            let fraction = Double(i) / Double(count - 1)
            let latitude = from.latitude + fraction * (to.latitude - from.latitude)
            let longitude = from.longitude + fraction * (to.longitude - from.longitude)
            coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }

        return coordinates
    }

    /// Calculate optimal sample count based on distance
    /// - Parameter distanceMeters: Distance between points in meters
    /// - Returns: Recommended number of samples
    static func optimalSampleCount(distanceMeters: Double) -> Int {
        switch distanceMeters {
        case ..<thresholdUnder1km:
            return sampleCountUnder1km
        case thresholdUnder1km..<threshold1to5km:
            return sampleCount1to5km
        case threshold1to5km..<threshold5to20km:
            return sampleCount5to20km
        default:
            return sampleCountOver20km
        }
    }

    // MARK: - Private Methods

    private func parseElevationResponse(_ data: Data) throws -> [Double] {
        struct ElevationResponse: Decodable {
            let elevation: [Double]
        }

        do {
            let response = try JSONDecoder().decode(ElevationResponse.self, from: data)
            return response.elevation
        } catch {
            throw ElevationServiceError.invalidResponse
        }
    }

    /// Subsample an array to a target count, preserving first and last elements
    private func subsample<T>(_ array: [T], targetCount: Int) -> [T] {
        guard array.count > targetCount, targetCount >= 2 else {
            return array
        }

        var result: [T] = []
        result.reserveCapacity(targetCount)

        // Always include first element
        result.append(array[0])

        // Calculate step for middle elements (targetCount - 2 middle samples)
        let middleCount = targetCount - 2
        if middleCount > 0 {
            let step = Double(array.count - 2) / Double(middleCount + 1)
            for i in 1...middleCount {
                let index = Int(Double(i) * step)
                result.append(array[index])
            }
        }

        // Always include last element
        result.append(array[array.count - 1])

        return result
    }
}
