import CoreLocation
import Foundation
import PocketMeshServices

/// Resolves repeater collisions by proximity and recency.
enum RepeaterResolver {
    /// Match using a PathHop: exact public key match first, then hash bytes fallback.
    static func bestMatch<T: RepeaterResolvable>(
        for hop: PathHop,
        in nodes: [T],
        userLocation: CLLocation?
    ) -> T? {
        if let key = hop.publicKey,
           let exact = nodes.first(where: { $0.publicKey == key }) {
            return exact
        }
        return bestMatch(for: hop.hashBytes, in: nodes, userLocation: userLocation)
    }

    /// Match using hash bytes (1-3 byte prefix)
    static func bestMatch<T: RepeaterResolvable>(
        for hashBytes: Data,
        in nodes: [T],
        userLocation: CLLocation?
    ) -> T? {
        let prefixLen = hashBytes.count
        let candidates = nodes.compactMap { node -> (T, Double?)? in
            guard node.publicKey.prefix(prefixLen) == hashBytes else { return nil }

            let distance: Double?
            if let userLocation, node.hasLocation {
                let nodeLocation = CLLocation(latitude: node.latitude, longitude: node.longitude)
                distance = userLocation.distance(from: nodeLocation)
            } else {
                distance = nil
            }

            return (node, distance)
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

            if lhs.0.recencyDate != rhs.0.recencyDate {
                return lhs.0.recencyDate > rhs.0.recencyDate
            }

            return lhs.0.resolvableName.localizedStandardCompare(rhs.0.resolvableName) == .orderedAscending
        }

        return sorted.first?.0
    }
}
