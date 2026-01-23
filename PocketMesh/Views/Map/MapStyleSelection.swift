import MapKit
import SwiftUI

/// Map style options for the Map tab
enum MapStyleSelection: String, CaseIterable, Hashable {
    case standard
    case satellite
    case hybrid

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .satellite: .imagery
        case .hybrid: .hybrid
        }
    }

    var label: String {
        switch self {
        case .standard: L10n.Map.Map.Style.standard
        case .satellite: L10n.Map.Map.Style.satellite
        case .hybrid: L10n.Map.Map.Style.hybrid
        }
    }

    /// MKMapType for UIKit MKMapView
    var mkMapType: MKMapType {
        switch self {
        case .standard: .standard
        case .satellite: .satellite
        case .hybrid: .hybrid
        }
    }
}
