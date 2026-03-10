import MapKit
import PocketMeshServices

/// MKAnnotation wrapper for ContactDTO to display on MKMapView
final class ContactAnnotation: NSObject, MKAnnotation {
    let contact: ContactDTO

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: contact.latitude, longitude: contact.longitude)
    }

    var title: String? { contact.displayName }

    var subtitle: String? {
        switch contact.type {
        case .chat:
            contact.isFavorite ? L10n.Map.Map.Annotation.favorite : nil
        case .repeater:
            L10n.Map.Map.Annotation.repeater
        case .room:
            L10n.Map.Map.Annotation.room
        }
    }

    init(contact: ContactDTO) {
        self.contact = contact
        super.init()
    }
}

extension ContactAnnotation {
    /// Unique identifier for comparing annotations
    override var hash: Int {
        contact.id.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ContactAnnotation else { return false }
        return contact.id == other.contact.id
    }
}
