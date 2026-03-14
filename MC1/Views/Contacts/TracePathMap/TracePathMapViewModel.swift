import CoreLocation
import MapKit
import SwiftUI
import MC1Services
import os.log

private let logger = Logger(subsystem: "com.mc1", category: "TracePathMap")

/// View model for map-specific state in trace path map view
@MainActor @Observable
final class TracePathMapViewModel {

    // MARK: - Map State

    var cameraRegion: MKCoordinateRegion?
    /// Incremented when code intentionally moves the camera (not from user gesture sync)
    var cameraRegionVersion = 0
    var mapStyleSelection: MapStyleSelection = .standard
    var showLabels: Bool = true
    var showingLayersMenu: Bool = false

    /// Tracks whether initial centering on repeaters has been performed
    private(set) var hasInitiallyCenteredOnRepeaters = false

    // MARK: - Path Overlays

    private(set) var mapLines: [MapLine] = []
    private(set) var badgePoints: [MapPoint] = []

    // MARK: - Dependencies

    private weak var traceViewModel: TracePathViewModel?
    private var userLocation: CLLocation?

    // MARK: - Path State

    struct RepeaterPathInfo {
        let inPath: Bool
        let hopIndex: Int?
        let isLastHop: Bool
    }

    /// Pre-computed path membership for all repeaters, keyed by repeater ID.
    /// Iterates the path once (O(M) resolutions) then does O(N) dictionary lookups,
    /// instead of O(N × M × N) per-repeater closure calls.
    var pathState: [UUID: RepeaterPathInfo] {
        let repeaters = repeatersWithLocation

        // Build path lookup: resolve each hop to a repeater UUID
        var pathLookup: [UUID: (index: Int, isLast: Bool)] = [:]
        if let path = traceViewModel?.outboundPath {
            for (index, hop) in path.enumerated() {
                if let repeater = findRepeater(for: hop) {
                    pathLookup[repeater.id] = (index: index + 1, isLast: index == path.count - 1)
                }
            }
        }

        // Build state for all repeaters with O(1) lookups
        var state: [UUID: RepeaterPathInfo] = [:]
        state.reserveCapacity(repeaters.count)
        for repeater in repeaters {
            if let info = pathLookup[repeater.id] {
                state[repeater.id] = RepeaterPathInfo(inPath: true, hopIndex: info.index, isLastHop: info.isLast)
            } else {
                state[repeater.id] = RepeaterPathInfo(inPath: false, hopIndex: nil, isLastHop: false)
            }
        }
        return state
    }

    // MARK: - Computed Properties

    /// Repeaters and rooms to display on map
    var repeatersWithLocation: [ContactDTO] {
        traceViewModel?.availableNodes.filter { $0.hasLocation } ?? []
    }

    /// Whether a path has been built (at least one hop)
    var hasPath: Bool {
        !(traceViewModel?.outboundPath.isEmpty ?? true)
    }

    /// Whether trace can be run (when connected)
    var canRunTrace: Bool {
        traceViewModel?.canRunTraceWhenConnected ?? false
    }

    /// Whether trace is currently running
    var isRunning: Bool {
        traceViewModel?.isRunning ?? false
    }

    /// Whether a successful result exists that can be saved
    var canSave: Bool {
        traceViewModel?.canSavePath ?? false
    }

    /// Current trace result
    var result: TraceResult? {
        traceViewModel?.result
    }

    // MARK: - Configuration

    func configure(traceViewModel: TracePathViewModel, userLocation: CLLocation?) {
        self.traceViewModel = traceViewModel
        self.userLocation = userLocation
    }

    func updateUserLocation(_ location: CLLocation?) {
        self.userLocation = location
        rebuildOverlays()
    }

    // MARK: - Path Building

    /// Find the repeater or room for a hop using full public key or RepeaterResolver fallback.
    private func findRepeater(for hop: PathHop) -> ContactDTO? {
        RepeaterResolver.bestMatch(for: hop, in: traceViewModel?.availableNodes ?? [], userLocation: userLocation)
    }

    /// Whether a hop matches a specific repeater.
    private func hopMatches(_ hop: PathHop, repeater: ContactDTO) -> Bool {
        findRepeater(for: hop)?.publicKey == repeater.publicKey
    }

    /// Check if a repeater is currently in the path
    func isRepeaterInPath(_ repeater: ContactDTO) -> Bool {
        guard let path = traceViewModel?.outboundPath else { return false }
        return path.contains { hopMatches($0, repeater: repeater) }
    }

    /// Check if repeater is the last hop (can be removed)
    func isLastHop(_ repeater: ContactDTO) -> Bool {
        guard let path = traceViewModel?.outboundPath,
              let lastHop = path.last else { return false }
        return hopMatches(lastHop, repeater: repeater)
    }

    enum RepeaterTapResult {
        case added
        case removed
        case rejectedMiddleHop
        case ignored
    }

    /// Handle tap on a repeater, returns the result of the tap action
    @discardableResult
    func handleRepeaterTap(_ repeater: ContactDTO) -> RepeaterTapResult {
        guard let traceViewModel else { return .ignored }

        let result: RepeaterTapResult
        if isLastHop(repeater) {
            // Remove last hop
            if let lastIndex = traceViewModel.outboundPath.indices.last {
                traceViewModel.removeRepeater(at: lastIndex)
            }
            result = .removed
        } else if !isRepeaterInPath(repeater) {
            // Add to path
            traceViewModel.addNode(repeater)
            result = .added
        } else {
            // Tapping middle hop - provide feedback that this action is not allowed
            result = .rejectedMiddleHop
        }

        rebuildOverlays()
        return result
    }

    /// Clear the path
    func clearPath() {
        traceViewModel?.clearPath()
        clearOverlays()
    }

    // MARK: - Trace Execution

    func runTrace() async {
        centerOnPath()
        traceViewModel?.batchEnabled = false
        await traceViewModel?.runTrace()
    }

    func savePath(name: String) async -> Bool {
        await traceViewModel?.savePath(name: name) ?? false
    }

    func generatePathName() -> String {
        traceViewModel?.generatePathName() ?? "Path"
    }

    // MARK: - Overlay Management

    /// Rebuild map lines based on current path
    func rebuildOverlays() {
        clearOverlays()

        guard let traceViewModel,
              !traceViewModel.outboundPath.isEmpty else { return }

        var previousCoordinate: CLLocationCoordinate2D?
        if let userLocation {
            previousCoordinate = userLocation.coordinate
        }

        for (index, hop) in traceViewModel.outboundPath.enumerated() {
            guard let repeater = findRepeater(for: hop),
                  repeater.hasLocation else { continue }

            let hopCoordinate = CLLocationCoordinate2D(
                latitude: repeater.latitude,
                longitude: repeater.longitude
            )

            guard CLLocationCoordinate2DIsValid(hopCoordinate) else { continue }

            if let prevCoord = previousCoordinate, CLLocationCoordinate2DIsValid(prevCoord) {
                mapLines.append(MapLine(
                    id: "trace-\(index)",
                    coordinates: [prevCoord, hopCoordinate],
                    style: .traceUntraced,
                    opacity: 1.0
                ))
            }

            previousCoordinate = hopCoordinate
        }
    }

    /// Update lines with trace results and add badge points at segment midpoints
    func updateOverlaysWithResults() {
        guard let result = traceViewModel?.result, result.success else { return }

        badgePoints.removeAll()

        var updatedLines: [MapLine] = []
        for (index, line) in mapLines.enumerated() {
            let hopIndex = index + 1
            if hopIndex < result.hops.count {
                let hop = result.hops[hopIndex]
                let quality = signalQuality(snr: hop.snr)
                let style = lineStyle(for: quality)

                updatedLines.append(MapLine(
                    id: line.id,
                    coordinates: line.coordinates,
                    style: style,
                    opacity: 1.0
                ))

                // Badge at midpoint
                if line.coordinates.count >= 2 {
                    let mid = CLLocationCoordinate2D(
                        latitude: (line.coordinates[0].latitude + line.coordinates[1].latitude) / 2,
                        longitude: (line.coordinates[0].longitude + line.coordinates[1].longitude) / 2
                    )
                    let distance = CLLocation(latitude: line.coordinates[0].latitude, longitude: line.coordinates[0].longitude)
                        .distance(from: CLLocation(latitude: line.coordinates[1].latitude, longitude: line.coordinates[1].longitude))
                    let miles = distance / 1609.34
                    let snrFormatted = hop.snr.formatted(.number.precision(.fractionLength(1)))
                    let distFormatted = miles.formatted(.number.precision(.fractionLength(1)))

                    // swiftlint:disable:next force_unwrapping
                    badgePoints.append(MapPoint(
                        id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))")!,
                        coordinate: mid,
                        pinStyle: .badge,
                        label: nil,
                        isClusterable: false,
                        hopIndex: nil,
                        badgeText: "\(distFormatted) mi · \(snrFormatted) dB"
                    ))
                }
            } else {
                updatedLines.append(line)
            }
        }

        mapLines = updatedLines
    }

    // MARK: - Signal Quality

    private enum SignalQuality {
        case untraced, weak, medium, good
    }

    private func signalQuality(snr: Double) -> SignalQuality {
        if snr <= 0 { return .weak }
        if snr < 5 { return .medium }
        return .good
    }

    private func lineStyle(for quality: SignalQuality) -> MapLine.LineStyle {
        switch quality {
        case .untraced: .traceUntraced
        case .weak: .traceWeak
        case .medium: .traceMedium
        case .good: .traceGood
        }
    }

    /// Clear all overlays
    func clearOverlays() {
        mapLines.removeAll()
        badgePoints.removeAll()
    }

    // MARK: - Camera

    /// Center map on all path points
    func centerOnPath() {
        var coordinates: [CLLocationCoordinate2D] = []

        if let userLocation {
            coordinates.append(userLocation.coordinate)
        }

        for line in mapLines {
            coordinates.append(contentsOf: line.coordinates)
        }

        guard !coordinates.isEmpty else { return }

        // Calculate bounding region
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Clamp spans to valid MKCoordinateSpan bounds (lat: 0-180, lon: 0-360)
        let span = MKCoordinateSpan(
            latitudeDelta: min(180, (maxLat - minLat) * 1.5 + 0.01),
            longitudeDelta: min(360, (maxLon - minLon) * 1.5 + 0.01)
        )

        cameraRegion = MKCoordinateRegion(center: center, span: span)
        cameraRegionVersion += 1
    }

    /// Center map to show all repeaters
    func centerOnAllRepeaters() {
        let repeaters = repeatersWithLocation
        guard !repeaters.isEmpty else {
            cameraRegion = nil
            return
        }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for repeater in repeaters {
            minLat = min(minLat, repeater.latitude)
            maxLat = max(maxLat, repeater.latitude)
            minLon = min(minLon, repeater.longitude)
            maxLon = max(maxLon, repeater.longitude)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        // Clamp spans to valid MKCoordinateSpan bounds (lat: 0-180, lon: 0-360)
        let latDelta = min(180, max(0.01, (maxLat - minLat) * 1.5))
        let lonDelta = min(360, max(0.01, (maxLon - minLon) * 1.5))

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)

        cameraRegion = MKCoordinateRegion(center: center, span: span)
        cameraRegionVersion += 1
        hasInitiallyCenteredOnRepeaters = true
    }

    /// Perform initial centering based on current state
    /// Centers on path if one exists, otherwise centers on all repeaters
    func performInitialCentering() {
        if hasPath {
            centerOnPathRepeaters()
        } else {
            centerOnAllRepeaters()
        }
    }

    /// Center map on path repeaters directly (doesn't depend on overlays)
    private func centerOnPathRepeaters() {
        guard let traceViewModel else {
            centerOnAllRepeaters()
            return
        }

        var coordinates: [CLLocationCoordinate2D] = []

        // Include user location if available
        if let userLocation {
            coordinates.append(userLocation.coordinate)
        }

        // Get coordinates from path repeaters
        for hop in traceViewModel.outboundPath {
            guard let repeater = findRepeater(for: hop),
                  repeater.hasLocation else {
                continue
            }

            let coord = CLLocationCoordinate2D(
                latitude: repeater.latitude,
                longitude: repeater.longitude
            )
            if CLLocationCoordinate2DIsValid(coord) {
                coordinates.append(coord)
            }
        }

        guard !coordinates.isEmpty else {
            centerOnAllRepeaters()
            return
        }

        // Calculate bounding region
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: min(180, (maxLat - minLat) * 1.5 + 0.01),
            longitudeDelta: min(360, (maxLon - minLon) * 1.5 + 0.01)
        )

        cameraRegion = MKCoordinateRegion(center: center, span: span)
        cameraRegionVersion += 1
        hasInitiallyCenteredOnRepeaters = true
    }
}
