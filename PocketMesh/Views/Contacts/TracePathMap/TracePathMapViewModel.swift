import CoreLocation
import MapKit
import SwiftUI
import PocketMeshServices
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "TracePathMap")

/// View model for map-specific state in trace path map view
@MainActor @Observable
final class TracePathMapViewModel {

    // MARK: - Map State

    var cameraRegion: MKCoordinateRegion?
    var mapStyleSelection: MapStyleSelection = .standard
    var showLabels: Bool = true
    var showingLayersMenu: Bool = false

    /// MKMapType for UIKit map view
    var mapType: MKMapType {
        switch mapStyleSelection {
        case .standard: .standard
        case .satellite: .satellite
        case .hybrid: .hybrid
        }
    }

    // MARK: - Path Overlays

    private(set) var lineOverlays: [PathLineOverlay] = []
    private(set) var badgeAnnotations: [StatsBadgeAnnotation] = []

    // MARK: - Dependencies

    private weak var traceViewModel: TracePathViewModel?
    private var userLocation: CLLocation?

    // MARK: - Computed Properties

    /// Repeaters that have valid location data
    var repeatersWithLocation: [ContactDTO] {
        traceViewModel?.availableRepeaters.filter { $0.hasLocation } ?? []
    }

    /// Whether a path has been built (at least one hop)
    var hasPath: Bool {
        !(traceViewModel?.outboundPath.isEmpty ?? true)
    }

    /// Whether trace can be run
    var canRunTrace: Bool {
        traceViewModel?.canRunTrace ?? false
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

    /// Check if a repeater is currently in the path
    func isRepeaterInPath(_ repeater: ContactDTO) -> Bool {
        guard let path = traceViewModel?.outboundPath else { return false }
        let hashByte = repeater.publicKey[0]
        return path.contains { $0.hashByte == hashByte }
    }

    /// Get the hop index for a repeater in the path (1-based for display)
    func hopIndex(for repeater: ContactDTO) -> Int? {
        guard let path = traceViewModel?.outboundPath else { return nil }
        let hashByte = repeater.publicKey[0]
        if let index = path.firstIndex(where: { $0.hashByte == hashByte }) {
            return index + 1
        }
        return nil
    }

    /// Check if repeater is the last hop (can be removed)
    func isLastHop(_ repeater: ContactDTO) -> Bool {
        guard let path = traceViewModel?.outboundPath, !path.isEmpty else { return false }
        let hashByte = repeater.publicKey[0]
        return path.last?.hashByte == hashByte
    }

    /// Handle tap on a repeater
    func handleRepeaterTap(_ repeater: ContactDTO) {
        guard let traceViewModel else { return }

        if isLastHop(repeater) {
            // Remove last hop
            if let lastIndex = traceViewModel.outboundPath.indices.last {
                traceViewModel.removeRepeater(at: lastIndex)
            }
        } else if !isRepeaterInPath(repeater) {
            // Add to path
            traceViewModel.addRepeater(repeater)
        }
        // Tapping middle hop does nothing

        rebuildOverlays()
    }

    /// Clear the path
    func clearPath() {
        traceViewModel?.clearPath()
        clearOverlays()
    }

    // MARK: - Trace Execution

    func runTrace() async {
        await traceViewModel?.runTrace()
    }

    func savePath(name: String) async -> Bool {
        await traceViewModel?.savePath(name: name) ?? false
    }

    func generatePathName() -> String {
        traceViewModel?.generatePathName() ?? "Path"
    }

    // MARK: - Overlay Management

    /// Rebuild line overlays and badge annotations based on current path
    func rebuildOverlays() {
        clearOverlays()

        guard let traceViewModel,
              !traceViewModel.outboundPath.isEmpty else { return }

        // Start from user location or default
        var previousCoordinate: CLLocationCoordinate2D?
        if let userLocation {
            previousCoordinate = userLocation.coordinate
        }

        // Build overlays for each hop
        for (index, hop) in traceViewModel.outboundPath.enumerated() {
            // Find repeater location
            guard let repeater = traceViewModel.availableRepeaters.first(where: {
                $0.publicKey[0] == hop.hashByte
            }), repeater.hasLocation else {
                logger.warning("Hop \(index) has no location data, skipping line segment")
                continue
            }

            let hopCoordinate = CLLocationCoordinate2D(
                latitude: repeater.latitude,
                longitude: repeater.longitude
            )

            // Validate coordinate
            guard CLLocationCoordinate2DIsValid(hopCoordinate) else {
                logger.warning("Invalid coordinate for hop \(index): (\(repeater.latitude), \(repeater.longitude))")
                continue
            }

            // Create line from previous point
            if let prevCoord = previousCoordinate, CLLocationCoordinate2DIsValid(prevCoord) {
                let overlay = PathLineOverlay.line(
                    from: prevCoord,
                    to: hopCoordinate,
                    segmentIndex: index
                )
                lineOverlays.append(overlay)
            }

            previousCoordinate = hopCoordinate
        }

        logger.debug("Rebuilt \(self.lineOverlays.count) line overlays")
    }

    /// Update overlays with trace results (creates new overlays since they're immutable)
    func updateOverlaysWithResults() {
        guard let result = traceViewModel?.result, result.success else { return }

        // Clear existing badges
        badgeAnnotations.removeAll()

        // Create new overlays with signal quality (immutable pattern)
        var updatedOverlays: [PathLineOverlay] = []
        for (index, overlay) in lineOverlays.enumerated() {
            // Find corresponding hop SNR (index + 1 because 0 is start node)
            let hopIndex = index + 1
            if hopIndex < result.hops.count {
                let hop = result.hops[hopIndex]
                let quality = PathLineOverlay.SignalQuality(snr: hop.snr)

                // Create new overlay with signal quality
                let updatedOverlay = overlay.withSignalQuality(quality, snrDB: hop.snr)
                updatedOverlays.append(updatedOverlay)

                // Add badge annotation at midpoint
                let badge = StatsBadgeAnnotation(
                    coordinate: updatedOverlay.midpoint,
                    distanceMeters: updatedOverlay.distanceMeters,
                    snrDB: hop.snr,
                    segmentIndex: index
                )
                badgeAnnotations.append(badge)
            } else {
                updatedOverlays.append(overlay)
            }
        }

        lineOverlays = updatedOverlays
        logger.debug("Updated overlays with results, added \(self.badgeAnnotations.count) badges")
    }

    /// Clear all overlays
    func clearOverlays() {
        lineOverlays.removeAll()
        badgeAnnotations.removeAll()
    }

    // MARK: - Camera

    /// Center map on all path points
    func centerOnPath() {
        var coordinates: [CLLocationCoordinate2D] = []

        if let userLocation {
            coordinates.append(userLocation.coordinate)
        }

        for overlay in lineOverlays {
            let points = overlay.points()
            for i in 0..<overlay.pointCount {
                coordinates.append(points[i].coordinate)
            }
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

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
        )

        cameraRegion = MKCoordinateRegion(center: center, span: span)
    }
}
