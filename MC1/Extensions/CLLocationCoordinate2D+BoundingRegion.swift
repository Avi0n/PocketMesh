import CoreLocation
import MapKit
import MapLibre

extension Array where Element == CLLocationCoordinate2D {
    /// Computes a bounding `MKCoordinateRegion` that fits all coordinates with padding.
    func boundingRegion(paddingMultiplier: Double = 1.5) -> MKCoordinateRegion? {
        guard let first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude

        for coord in dropFirst() {
            minLat = Swift.min(minLat, coord.latitude)
            maxLat = Swift.max(maxLat, coord.latitude)
            minLon = Swift.min(minLon, coord.longitude)
            maxLon = Swift.max(maxLon, coord.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: Swift.min(180, Swift.max(0.01, (maxLat - minLat) * paddingMultiplier)),
                longitudeDelta: Swift.min(360, Swift.max(0.01, (maxLon - minLon) * paddingMultiplier))
            )
        )
    }
}

extension MKCoordinateRegion {
    func toMLNCoordinateBounds() -> MLNCoordinateBounds {
        MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(
                latitude: center.latitude - span.latitudeDelta / 2,
                longitude: center.longitude - span.longitudeDelta / 2
            ),
            ne: CLLocationCoordinate2D(
                latitude: center.latitude + span.latitudeDelta / 2,
                longitude: center.longitude + span.longitudeDelta / 2
            )
        )
    }
}
