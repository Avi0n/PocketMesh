import CoreLocation
import Foundation
import PocketMeshServices

/// Resolves repeater collisions by proximity and recency.
enum RepeaterResolver {
    static func bestMatch(
        for hopByte: UInt8,
        in repeaters: [ContactDTO],
        userLocation: CLLocation?
    ) -> ContactDTO? {
        let candidates = repeaters.compactMap { contact -> (ContactDTO, Double?)? in
            guard contact.publicKey.first == hopByte else { return nil }

            let distance: Double?
            if let userLocation, contact.hasLocation {
                let repeaterLocation = CLLocation(latitude: contact.latitude, longitude: contact.longitude)
                distance = userLocation.distance(from: repeaterLocation)
            } else {
                distance = nil
            }

            return (contact, distance)
        }

        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { lhs, rhs in
            switch (lhs.1, rhs.1) {
            case let (left?, right?):
                if left != right { return left < right }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            if lhs.0.lastAdvertTimestamp != rhs.0.lastAdvertTimestamp {
                return lhs.0.lastAdvertTimestamp > rhs.0.lastAdvertTimestamp
            }

            if lhs.0.lastModified != rhs.0.lastModified {
                return lhs.0.lastModified > rhs.0.lastModified
            }

            return lhs.0.displayName.localizedStandardCompare(rhs.0.displayName) == .orderedAscending
        }

        return sorted.first?.0
    }
}
