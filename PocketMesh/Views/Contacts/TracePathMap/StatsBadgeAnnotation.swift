import MapKit

/// Annotation for displaying stats badge at path segment midpoint
final class StatsBadgeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let snrDB: Double
    let segmentIndex: Int

    init(coordinate: CLLocationCoordinate2D, distanceMeters: Double, snrDB: Double, segmentIndex: Int) {
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.snrDB = snrDB
        self.segmentIndex = segmentIndex
        super.init()
    }

    /// Formatted distance string (e.g., "1.2 mi" or "500 m")
    var distanceString: String {
        let miles = distanceMeters / 1609.34
        if miles >= 0.1 {
            return "\(miles.formatted(.number.precision(.fractionLength(1)))) mi"
        } else {
            return "\(distanceMeters.formatted(.number.precision(.fractionLength(0)))) m"
        }
    }

    /// Formatted SNR string (e.g., "8 dB")
    var snrString: String {
        "\(snrDB.formatted(.number.precision(.fractionLength(0)))) dB"
    }

    /// Combined display string
    var displayString: String {
        "\(distanceString) • \(snrString)"
    }
}
