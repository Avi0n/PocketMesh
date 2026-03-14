import SwiftUI

/// Map style options for the Map tab
enum MapStyleSelection: String, CaseIterable, Hashable {
    case standard
    case satellite
    case topo

    var label: String {
        switch self {
        case .standard: L10n.Map.Map.Style.standard
        case .satellite: L10n.Map.Map.Style.satellite
        case .topo: L10n.Map.Map.Style.topo
        }
    }

    var requiresNetwork: Bool {
        switch self {
        case .standard: false
        case .satellite: true
        case .topo: false
        }
    }

    func styleURL(isDarkMode: Bool) -> URL {
        switch self {
        case .standard:
            let url = isDarkMode ? MapTileURLs.openFreeMapDark : MapTileURLs.openFreeMapLiberty
            return URL(string: url)!
        case .satellite, .topo:
            // Satellite/topo use raster overlays on top of the base vector style.
            // The base style URL is still needed; raster sources are added later.
            let url = isDarkMode ? MapTileURLs.openFreeMapDark : MapTileURLs.openFreeMapLiberty
            return URL(string: url)!
        }
    }
}
