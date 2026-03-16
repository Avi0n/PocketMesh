import MapLibre
import MapKit
import ObjectiveC
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mc1", category: "MapPins")

// MARK: - MapLibre Metal scale fix

/// Workaround for a MapLibre bug where `MLNEffectiveScaleFactorForView`
/// computes `nativeBounds.width / bounds.width` — a ratio that breaks in
/// landscape because `nativeBounds` is fixed while `bounds` rotates.
/// We intercept `setDrawableSize:` on the internal Metal **UIView** (not
/// the CAMetalLayer) so that `layoutChanged()`'s read-back of
/// `resource.mtlView.drawableSize` also returns the corrected value.
/// Upstream issue: https://github.com/maplibre/maplibre-native/issues/3214
private enum MetalLayerScaleFix {

    static func apply(to mapView: MLNMapView) {
        guard let metalView = findMetalView(in: mapView) else { return }

        let selector = NSSelectorFromString("setDrawableSize:")
        guard metalView.responds(to: selector) else { return }

        let originalClass: AnyClass = object_getClass(metalView)!
        let name = "_MC1FixedScale_\(NSStringFromClass(originalClass))"

        let fixedClass: AnyClass
        if let existing = objc_getClass(name) as? AnyClass {
            fixedClass = existing
        } else {
            guard let subclass = objc_allocateClassPair(originalClass, name, 0) else { return }
            addDrawableSizeOverride(to: subclass, originalClass: originalClass)
            objc_registerClassPair(subclass)
            fixedClass = subclass
        }

        object_setClass(metalView, fixedClass)
    }

    // MARK: - Private

    private static func findMetalView(in view: UIView) -> UIView? {
        for subview in view.subviews where subview.layer is CAMetalLayer {
            return subview
        }
        return nil
    }

    private static func addDrawableSizeOverride(
        to subclass: AnyClass,
        originalClass: AnyClass
    ) {
        let selector = NSSelectorFromString("setDrawableSize:")
        guard let original = class_getInstanceMethod(originalClass, selector) else { return }
        let originalIMP = method_getImplementation(original)
        typealias SetDrawableSizeFn = @convention(c) (AnyObject, Selector, CGSize) -> Void
        let callOriginal = unsafeBitCast(originalIMP, to: SetDrawableSizeFn.self)

        let block: @convention(block) (UIView, CGSize) -> Void = { metalView, proposedSize in
            var parent: UIView? = metalView.superview
            while let v = parent, !(v is MLNMapView) { parent = v.superview }

            guard let mapView = parent,
                  mapView.bounds.size.width > 0,
                  mapView.bounds.size.height > 0,
                  let screen = mapView.window?.screen else {
                callOriginal(metalView, selector, proposedSize)
                return
            }

            let correctScale = screen.nativeScale
            let correctSize = CGSize(
                width: mapView.bounds.width * correctScale,
                height: mapView.bounds.height * correctScale
            )

            // Avoid redundant drawable reallocation and layout loops.
            if let layer = metalView.layer as? CAMetalLayer,
               layer.drawableSize == correctSize {
                return
            }

            callOriginal(metalView, selector, correctSize)
        }

        let imp = imp_implementationWithBlock(block)
        class_addMethod(subclass, selector, imp, method_getTypeEncoding(original))
    }
}

/// Applies the Metal layer scale fix once the view is attached to a window.
private final class ScaledMLNMapView: MLNMapView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        MetalLayerScaleFix.apply(to: self)
    }
}

struct MC1MapView: UIViewRepresentable {
    // Data
    let points: [MapPoint]
    let lines: [MapLine]
    let mapStyle: MapStyleSelection
    let isDarkMode: Bool

    // Configuration
    let showLabels: Bool
    let showsUserLocation: Bool
    let isInteractive: Bool
    let showsScale: Bool

    // Camera
    @Binding var cameraRegion: MKCoordinateRegion?
    let cameraRegionVersion: Int
    var cameraEdgePadding: UIEdgeInsets = .zero
    var cameraBottomSheetFraction: CGFloat?

    // Output callbacks
    let onPointTap: ((MapPoint, CGPoint) -> Void)?
    let onMapTap: ((CLLocationCoordinate2D) -> Void)?
    let onCameraRegionChange: ((MKCoordinateRegion) -> Void)?

    // Optional features
    @Binding var isStyleLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = context.coordinator.mapView
        mapView.delegate = context.coordinator

        mapView.showsUserLocation = showsUserLocation
        mapView.compassViewPosition = .topRight
        mapView.compassViewMargins = CGPoint(x: 8, y: 8)
        mapView.attributionButtonPosition = .bottomLeft
        mapView.attributionButtonMargins = CGPoint(x: 4, y: 30)

        if showsScale {
            mapView.showsScale = true
        }

        if !isInteractive {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isRotateEnabled = false
            mapView.isPitchEnabled = false
            mapView.compassView.isHidden = true
        }

        // Tap gesture for feature queries
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.pendingRegionTask?.cancel()
        mapView.delegate = nil
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Refresh callbacks
        coordinator.onPointTap = onPointTap
        coordinator.onMapTap = onMapTap
        coordinator.onCameraRegionChange = onCameraRegionChange
        coordinator.setIsStyleLoaded = { isStyleLoaded = $0 }
        coordinator.showLabels = showLabels
        let pointsChanged = coordinator.currentPoints != points
        let linesChanged = coordinator.currentLines != lines
        coordinator.currentPoints = points
        coordinator.currentLines = lines

        // Style URL change
        let newStyleURL = mapStyle.styleURL(isDarkMode: isDarkMode)
        if mapView.styleURL != newStyleURL {
            coordinator.isStyleLoaded = false
            mapView.styleURL = newStyleURL
        }
        let mapStyleChanged = coordinator.currentMapStyle != mapStyle
        coordinator.currentMapStyle = mapStyle

        // User location
        mapView.showsUserLocation = showsUserLocation

        // Update data layers (only when style is loaded and data changed)
        if coordinator.isStyleLoaded {
            if mapStyleChanged {
                coordinator.updateRasterLayerVisibility(mapView: mapView)
            }
            if pointsChanged {
                coordinator.updatePointSource(mapView: mapView)
            }
            if linesChanged {
                coordinator.updateLineSource(mapView: mapView)
            }
            coordinator.updateLabelVisibility(mapView: mapView)
        }

        // Camera region (version-number pattern)
        updateCameraRegion(in: mapView, coordinator: coordinator)
    }

    private func updateCameraRegion(in mapView: MLNMapView, coordinator: Coordinator) {
        guard let region = cameraRegion else { return }
        guard cameraRegionVersion != coordinator.lastAppliedRegionVersion else { return }

        let isInflated = mapView.window.map { mapView.bounds.height > $0.bounds.height * 1.5 } ?? false
        let animated = coordinator.lastAppliedRegionVersion > 0 && !isInflated
        coordinator.lastAppliedRegionVersion = cameraRegionVersion

        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(
                latitude: region.center.latitude - region.span.latitudeDelta / 2,
                longitude: region.center.longitude - region.span.longitudeDelta / 2
            ),
            ne: CLLocationCoordinate2D(
                latitude: region.center.latitude + region.span.latitudeDelta / 2,
                longitude: region.center.longitude + region.span.longitudeDelta / 2
            )
        )
        var padding = cameraEdgePadding
        if let sheetFraction = cameraBottomSheetFraction {
            let insets = mapView.safeAreaInsets
            padding.top = max(padding.top, insets.top + 20)
            padding.left = max(padding.left, insets.left + 20)
            if sheetFraction > 0 {
                let stableHeight = mapView.window?.bounds.height ?? mapView.bounds.height
                padding.bottom = max(padding.bottom, stableHeight * sheetFraction)
            }
        }

        if let windowSize = mapView.window?.bounds.size,
           mapView.bounds.height > windowSize.height * 1.5 {
            let centerLat = (bounds.sw.latitude + bounds.ne.latitude) / 2
            let centerLon = (bounds.sw.longitude + bounds.ne.longitude) / 2
            let latSpanMeters = abs(bounds.ne.latitude - bounds.sw.latitude) * 111_000
            let lonSpanMeters = abs(bounds.ne.longitude - bounds.sw.longitude) * 111_000
                * cos(centerLat * .pi / 180)

            let usableWidth = max(1, Double(windowSize.width) - Double(padding.left + padding.right))
            let usableHeight = max(1, Double(windowSize.height) - Double(padding.top + padding.bottom))

            let mppForLat = latSpanMeters / usableHeight
            let mppForLon = lonSpanMeters / usableWidth
            let requiredMPP = max(mppForLat, mppForLon)

            let currentMPP = mapView.metersPerPoint(atLatitude: centerLat)
            let targetZoom = mapView.zoomLevel + log2(currentMPP / requiredMPP)

            let pixelOffset = (Double(padding.top) - Double(padding.bottom)) / 2
            let offsetDeg = pixelOffset * requiredMPP / 111_000
            let center = CLLocationCoordinate2D(
                latitude: centerLat + offsetDeg,
                longitude: centerLon
            )

            mapView.setCenter(center, zoomLevel: targetZoom, animated: false)
        } else {
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: padding, animated: animated)
        }
    }
}

// MARK: - Coordinator

extension MC1MapView {
    @MainActor
    class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate, UIGestureRecognizerDelegate {
        // Non-zero frame avoids MapLibre zero-size Metal init (issue #67).
        let mapView: MLNMapView = ScaledMLNMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

        // Callbacks
        var onPointTap: ((MapPoint, CGPoint) -> Void)?
        var onMapTap: ((CLLocationCoordinate2D) -> Void)?
        var onCameraRegionChange: ((MKCoordinateRegion) -> Void)?
        var setIsStyleLoaded: ((Bool) -> Void)?

        // State
        var isUpdatingFromSwiftUI = false
        var isStyleLoaded = false
        var lastAppliedRegionVersion = 0
        var pendingRegionTask: Task<Void, Never>?
        var showLabels = true
        var currentMapStyle: MapStyleSelection?
        var currentPoints: [MapPoint] = []
        var currentLines: [MapLine] = []
        var clusterSource: MLNShapeSource?
        var fixedSource: MLNShapeSource?

        // MARK: - Style loading

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            isStyleLoaded = true
            setIsStyleLoaded?(true)

            // Clear stale source references from the previous style.
            clusterSource = nil
            fixedSource = nil

            PinSpriteRenderer.renderAll(into: style)
            setupRasterSources(style: style, mapView: mapView)
            setupLineLayers(style: style)

            updatePointSource(mapView: mapView)
            updateLineSource(mapView: mapView)
        }

        func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            logger.error("didFailToLoadImage: \(imageName)")
            return nil
        }

        // MARK: - Region changes

        private static let userGestureReasons: MLNCameraChangeReason = [
            .gesturePan, .gestureZoomIn, .gestureZoomOut,
            .gestureRotate, .gestureTilt, .gestureOneFingerZoom
        ]

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            guard !isUpdatingFromSwiftUI else { return }

            let isUserGesture = !reason.isDisjoint(with: Self.userGestureReasons)
            guard isUserGesture else { return }

            // Debounce: cancel previous pending write-back
            pendingRegionTask?.cancel()
            pendingRegionTask = Task {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                let region = mapView.mlnRegion
                self.onCameraRegionChange?(region)
            }
        }

        // MARK: - Gesture recognizer delegate

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: - Tap handling

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard sender.state == .ended else { return }
            let point = sender.location(in: mapView)
            let clusterRect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            logger.debug("handleTap at \(point.x, privacy: .public), \(point.y, privacy: .public)")

            // 1. Check cluster layers
            let clusterFeatures = mapView.visibleFeatures(
                in: clusterRect,
                styleLayerIdentifiers: ["cluster-circles"]
            )
            if let cluster = clusterFeatures.first(where: { $0 is MLNPointFeatureCluster }) as? MLNPointFeatureCluster,
               let source = mapView.style?.source(withIdentifier: "points") as? MLNShapeSource {
                let zoom = source.zoomLevel(forExpanding: cluster)
                guard zoom >= 0 else { return }
                mapView.setCenter(cluster.coordinate, zoomLevel: zoom + 2.0, animated: true)
                return
            }

            // 2. Check point layers (both clustered and fixed)
            let pointFeatures = mapView.visibleFeatures(
                at: point,
                styleLayerIdentifiers: ["unclustered-icons", "fixed-icons"]
            )
            logger.debug("pointFeatures: \(pointFeatures.count, privacy: .public), clusterFeatures: \(clusterFeatures.count, privacy: .public)")
            if let feature = pointFeatures.first,
               let idString = feature.attribute(forKey: "pointId") as? String,
               let id = UUID(uuidString: idString),
               let mapPoint = currentPoints.first(where: { $0.id == id }) {
                logger.debug("Matched pin: \(mapPoint.label ?? "unnamed", privacy: .public)")
                let pinScreenPos = mapView.convert(mapPoint.coordinate, toPointTo: mapView)
                let calloutAnchor = CGPoint(x: pinScreenPos.x, y: pinScreenPos.y - PinSpriteRenderer.standardHeight)
                onPointTap?(mapPoint, calloutAnchor)
                return
            }

            // 3. Check badge text layers
            let badgeFeatures = mapView.visibleFeatures(
                at: point,
                styleLayerIdentifiers: ["badge-text", "fixed-badge-text"]
            )
            if badgeFeatures.first != nil {
                return // absorb tap on badges
            }

            // 4. Map background tap
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onMapTap?(coordinate)
        }
    }
}

// MARK: - MLNMapView region helper

extension MLNMapView {
    var mlnRegion: MKCoordinateRegion {
        let bounds = visibleCoordinateBounds
        let center = CLLocationCoordinate2D(
            latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
            longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: bounds.ne.latitude - bounds.sw.latitude,
            longitudeDelta: bounds.ne.longitude - bounds.sw.longitude
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
