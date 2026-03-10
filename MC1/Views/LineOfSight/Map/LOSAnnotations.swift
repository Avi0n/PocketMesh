import CoreLocation
import MapKit
import PocketMeshServices

// MARK: - Repeater Annotation

/// MKAnnotation wrapper for repeater contacts on the line of sight map
final class LOSRepeaterAnnotation: NSObject, MKAnnotation {
    let repeater: ContactDTO

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: repeater.latitude, longitude: repeater.longitude)
    }

    var title: String? { repeater.displayName }

    init(repeater: ContactDTO) {
        self.repeater = repeater
        super.init()
    }
}

// MARK: - Point Annotation

/// MKAnnotation for dropped-pin A/B markers
final class LOSPointAnnotation: NSObject, MKAnnotation {
    let pointID: PointID
    let label: String

    dynamic var coordinate: CLLocationCoordinate2D

    init(pointID: PointID, label: String, coordinate: CLLocationCoordinate2D) {
        self.pointID = pointID
        self.label = label
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Repeater Target Annotation

/// MKAnnotation for the crosshairs repeater target marker
final class LOSRepeaterTargetAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
