import MapKit

/// MKPolyline overlay for path lines between points A, R, and B
final class LOSPathOverlay: MKPolyline {
    /// Which point this line connects to (used for opacity calculation during relocation)
    var connectsTo: PointID = .pointA
}

/// Renderer for LOS path overlays - blue dashed lines
final class LOSPathRenderer: MKPolylineRenderer {
    init(overlay: LOSPathOverlay, opacity: CGFloat) {
        super.init(overlay: overlay)
        strokeColor = .systemBlue
        lineWidth = 3
        lineDashPattern = [8, 4]
        alpha = opacity
    }
}
