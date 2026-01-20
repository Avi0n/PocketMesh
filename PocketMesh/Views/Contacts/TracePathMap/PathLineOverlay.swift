import MapKit

/// Custom polyline overlay that carries signal quality data for styling
/// Note: All properties are immutable - create new overlay instances when signal quality changes
final class PathLineOverlay: MKPolyline {

    /// Signal quality determines line color after trace
    enum SignalQuality {
        case untraced  // Dashed gray (before trace)
        case good      // Solid green (SNR >= 5)
        case medium    // Solid yellow (SNR -5 to 5)
        case weak      // Solid red (SNR < -5)

        init(snr: Double) {
            if snr >= 5 {
                self = .good
            } else if snr >= -5 {
                self = .medium
            } else {
                self = .weak
            }
        }
    }

    /// Signal quality - immutable after creation
    private(set) var signalQuality: SignalQuality = .untraced

    /// Distance in meters between the two endpoints - immutable after creation
    private(set) var distanceMeters: Double = 0

    /// SNR value in dB - immutable after creation
    private(set) var snrDB: Double = 0

    /// Index of this segment in the path (0 = user to first hop) - immutable after creation
    private(set) var segmentIndex: Int = 0

    /// Start coordinate for this segment
    private(set) var startCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()

    /// End coordinate for this segment
    private(set) var endCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()

    /// Create overlay between two coordinates
    static func line(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segmentIndex: Int,
        signalQuality: SignalQuality = .untraced,
        snrDB: Double = 0
    ) -> PathLineOverlay {
        var coords = [start, end]
        let overlay = PathLineOverlay(coordinates: &coords, count: 2)
        overlay.segmentIndex = segmentIndex
        overlay.signalQuality = signalQuality
        overlay.snrDB = snrDB
        overlay.startCoordinate = start
        overlay.endCoordinate = end

        // Calculate distance
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        overlay.distanceMeters = startLocation.distance(from: endLocation)

        return overlay
    }

    /// Create a new overlay with updated signal quality (immutable pattern)
    func withSignalQuality(_ quality: SignalQuality, snrDB: Double) -> PathLineOverlay {
        PathLineOverlay.line(
            from: startCoordinate,
            to: endCoordinate,
            segmentIndex: segmentIndex,
            signalQuality: quality,
            snrDB: snrDB
        )
    }

    /// Midpoint coordinate for placing stats badge
    var midpoint: CLLocationCoordinate2D {
        guard pointCount >= 2 else { return coordinate }
        let points = self.points()
        let start = points[0]
        let end = points[1]
        return CLLocationCoordinate2D(
            latitude: (start.coordinate.latitude + end.coordinate.latitude) / 2,
            longitude: (start.coordinate.longitude + end.coordinate.longitude) / 2
        )
    }
}
