import MapKit
import UIKit

/// Renderer for PathLineOverlay that draws dashed or solid colored lines
/// Note: Since PathLineOverlay is immutable, create new overlays when signal quality changes
/// rather than calling updateAppearance on existing renderers
final class PathLineRenderer: MKPolylineRenderer {

    override init(overlay: any MKOverlay) {
        super.init(overlay: overlay)
        configureAppearance()
    }

    private func configureAppearance() {
        guard let pathOverlay = overlay as? PathLineOverlay else { return }

        guard let quality = pathOverlay.signalQuality else {
            // Untraced — dashed gray
            strokeColor = UIColor.systemGray
            lineWidth = 2
            lineDashPattern = [8, 6]
            return
        }

        strokeColor = quality.uiColor

        switch quality {
        case .excellent, .good:
            lineWidth = 4
            lineDashPattern = nil
        case .fair:
            lineWidth = 3
            lineDashPattern = [12, 4]
        case .poor:
            lineWidth = 3
            lineDashPattern = [4, 4]
        case .unknown:
            lineWidth = 2
            lineDashPattern = [8, 6]
        }
    }
}
