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
            return String(format: "%.1f mi", miles)
        } else {
            return String(format: "%.0f m", distanceMeters)
        }
    }

    /// Formatted SNR string (e.g., "8 dB")
    var snrString: String {
        String(format: "%.0f dB", snrDB)
    }

    /// Combined display string
    var displayString: String {
        "\(distanceString) • \(snrString)"
    }
}
