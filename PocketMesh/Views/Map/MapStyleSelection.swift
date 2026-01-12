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
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
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
