import MapKit

/// MKMapView subclass that disables double-tap-to-zoom and one-handed zoom gestures.
/// Directly disables VariableDelayTap and OneHandedZoom gesture recognizers on MapKit's
/// content view rather than using `require(toFail:)` blockers, which avoids a ~1s cascading
/// gesture timeout after tapping annotation pins.
final class NoDoubleTapMapView: MKMapView {
    override func layoutSubviews() {
        super.layoutSubviews()
        disableDoubleTapGestures()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        disableDoubleTapGestures()
        return super.hitTest(point, with: event)
    }

    private func disableDoubleTapGestures() {
        guard let contentView = subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("MapContentView")
        }) else { return }

        for gesture in contentView.gestureRecognizers ?? [] {
            guard gesture.isEnabled else { continue }
            let className = NSStringFromClass(type(of: gesture))
            if className.contains("VariableDelayTap") || className.contains("OneHandedZoom") {
                gesture.isEnabled = false
            }
        }
    }
}
