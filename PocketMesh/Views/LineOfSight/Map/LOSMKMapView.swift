import MapKit
import PocketMeshServices
import SwiftUI

/// UIViewRepresentable for line of sight map with custom overlays and interactions
struct LOSMKMapView: UIViewRepresentable {
    let repeaters: [ContactDTO]
    let pointA: SelectedPoint?
    let pointB: SelectedPoint?
    let repeaterTarget: RepeaterPoint?
    let relocatingPoint: PointID?
    let mapType: MKMapType
    let showLabels: Bool

    @Binding var cameraRegion: MKCoordinateRegion?
    let cameraRegionVersion: Int

    /// Closure-wrapped to defer computation to updateUIView, avoiding SwiftUI observation overhead
    let selectionState: () -> [UUID: LOSRepeaterSelectionInfo]
    let onRepeaterTap: (ContactDTO) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = context.coordinator.mapView
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true

        let scaleView = MKScaleView(mapView: mapView)
        scaleView.translatesAutoresizingMaskIntoConstraints = false
        scaleView.scaleVisibility = .adaptive
        mapView.addSubview(scaleView)
        NSLayoutConstraint.activate([
            scaleView.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 16),
            scaleView.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        mapView.register(
            LOSRepeaterPinView.self,
            forAnnotationViewWithReuseIdentifier: LOSRepeaterPinView.reuseIdentifier
        )
        mapView.register(
            TracePathClusterView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        mapView.register(
            LOSPointPinView.self,
            forAnnotationViewWithReuseIdentifier: LOSPointPinView.reuseIdentifier
        )
        mapView.register(
            LOSRepeaterTargetPinView.self,
            forAnnotationViewWithReuseIdentifier: LOSRepeaterTargetPinView.reuseIdentifier
        )

        // Map tap gesture for drop pin / relocation
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Evaluate selection state once
        let selState = selectionState()
        coordinator.selectionState = selState
        coordinator.onRepeaterTap = onRepeaterTap
        coordinator.onMapTap = onMapTap
        coordinator.relocatingPoint = relocatingPoint
        coordinator.showLabels = showLabels

        // Update map type
        mapView.mapType = mapType

        // Update repeater annotations
        updateRepeaterAnnotations(in: mapView, coordinator: coordinator, selectionState: selState)

        // Update point A/B annotations
        updatePointAnnotations(in: mapView, coordinator: coordinator)

        // Update repeater target annotation
        updateRepeaterTargetAnnotation(in: mapView, coordinator: coordinator)

        // Update path overlays
        updatePathOverlays(in: mapView, coordinator: coordinator)

        // Update visible pin views with current state
        updateVisiblePinViews(in: mapView, coordinator: coordinator, selectionState: selState)

        // Update path overlay opacity when relocatingPoint changes
        if relocatingPoint != coordinator.lastRelocatingPoint {
            coordinator.lastRelocatingPoint = relocatingPoint
            for overlay in mapView.overlays {
                if let pathOverlay = overlay as? LOSPathOverlay,
                   let renderer = mapView.renderer(for: pathOverlay) as? LOSPathRenderer {
                    renderer.alpha = coordinator.lineOpacity(connectsTo: pathOverlay.connectsTo)
                    renderer.setNeedsDisplay()
                }
            }
        }

        // Update region only when version changes
        if cameraRegionVersion != coordinator.lastAppliedRegionVersion,
           let region = cameraRegion {
            coordinator.lastAppliedRegionVersion = cameraRegionVersion
            coordinator.hasPendingProgrammaticRegion = true
            let animated = coordinator.lastAppliedRegion != nil
            mapView.setRegion(region, animated: animated)

            coordinator.lastAppliedRegion = region
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(setCameraRegion: { cameraRegion = $0 })
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.pendingRegionTask?.cancel()
    }

    // MARK: - Repeater Annotation Updates

    private func updateRepeaterAnnotations(
        in mapView: MKMapView,
        coordinator: Coordinator,
        selectionState: [UUID: LOSRepeaterSelectionInfo]
    ) {
        let currentAnnotations = mapView.annotations.compactMap { $0 as? LOSRepeaterAnnotation }
        let currentIDs = Set(currentAnnotations.map { $0.repeater.id })
        let newIDs = Set(repeaters.map { $0.id })

        // Remove old
        let toRemove = currentAnnotations.filter { !newIDs.contains($0.repeater.id) }
        mapView.removeAnnotations(toRemove)

        // Add new
        let existingIDs = currentIDs.subtracting(Set(toRemove.map { $0.repeater.id }))
        let toAdd = repeaters.filter { !existingIDs.contains($0.id) }
            .map { LOSRepeaterAnnotation(repeater: $0) }
        mapView.addAnnotations(toAdd)

        // Re-add annotations whose selection state changed (MapKit doesn't pick up clusteringIdentifier changes)
        let currentSelectedIDs = Set(selectionState.filter { $0.value.selectedAs != nil }.map { $0.key })
        let previousSelectedIDs = coordinator.previousSelectedIDs
        let changedIDs = currentSelectedIDs.symmetricDifference(previousSelectedIDs)
        coordinator.previousSelectedIDs = currentSelectedIDs

        if !changedIDs.isEmpty {
            let toReAdd = mapView.annotations
                .compactMap { $0 as? LOSRepeaterAnnotation }
                .filter { changedIDs.contains($0.repeater.id) }
            mapView.removeAnnotations(toReAdd)
            mapView.addAnnotations(toReAdd)
        }
    }

    // MARK: - Point Annotation Updates

    private func updatePointAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
        let existingPoints = mapView.annotations.compactMap { $0 as? LOSPointAnnotation }

        // Point A (only if dropped pin, not contact)
        let existingA = existingPoints.first { $0.pointID == .pointA }
        if let pointA, pointA.contact == nil {
            if let existing = existingA {
                // Update coordinate if changed
                if existing.coordinate.latitude != pointA.coordinate.latitude ||
                    existing.coordinate.longitude != pointA.coordinate.longitude {
                    existing.coordinate = pointA.coordinate
                }
            } else {
                let annotation = LOSPointAnnotation(
                    pointID: .pointA,
                    label: "A",
                    coordinate: pointA.coordinate
                )
                mapView.addAnnotation(annotation)
            }
        } else if let existing = existingA {
            mapView.removeAnnotation(existing)
        }

        // Point B (only if dropped pin, not contact)
        let existingB = existingPoints.first { $0.pointID == .pointB }
        if let pointB, pointB.contact == nil {
            if let existing = existingB {
                if existing.coordinate.latitude != pointB.coordinate.latitude ||
                    existing.coordinate.longitude != pointB.coordinate.longitude {
                    existing.coordinate = pointB.coordinate
                }
            } else {
                let annotation = LOSPointAnnotation(
                    pointID: .pointB,
                    label: "B",
                    coordinate: pointB.coordinate
                )
                mapView.addAnnotation(annotation)
            }
        } else if let existing = existingB {
            mapView.removeAnnotation(existing)
        }
    }

    // MARK: - Repeater Target Annotation Updates

    private func updateRepeaterTargetAnnotation(in mapView: MKMapView, coordinator: Coordinator) {
        let existing = mapView.annotations.compactMap { $0 as? LOSRepeaterTargetAnnotation }.first

        if let repeaterTarget {
            if let existing {
                if existing.coordinate.latitude != repeaterTarget.coordinate.latitude ||
                    existing.coordinate.longitude != repeaterTarget.coordinate.longitude {
                    existing.coordinate = repeaterTarget.coordinate
                }
            } else {
                let annotation = LOSRepeaterTargetAnnotation(coordinate: repeaterTarget.coordinate)
                mapView.addAnnotation(annotation)
            }
        } else if let existing {
            mapView.removeAnnotation(existing)
        }
    }

    // MARK: - Path Overlay Updates

    private func updatePathOverlays(in mapView: MKMapView, coordinator: Coordinator) {
        // Build desired path segments
        var newOverlays: [LOSPathOverlay] = []

        if let pointA, let pointB {
            if let repeaterTarget {
                // A -> R
                let coordsAR = [pointA.coordinate, repeaterTarget.coordinate]
                let overlayAR = LOSPathOverlay(coordinates: coordsAR, count: coordsAR.count)
                overlayAR.connectsTo = .pointA
                newOverlays.append(overlayAR)

                // R -> B
                let coordsRB = [repeaterTarget.coordinate, pointB.coordinate]
                let overlayRB = LOSPathOverlay(coordinates: coordsRB, count: coordsRB.count)
                overlayRB.connectsTo = .pointB
                newOverlays.append(overlayRB)
            } else {
                // A -> B
                let coords = [pointA.coordinate, pointB.coordinate]
                let overlay = LOSPathOverlay(coordinates: coords, count: coords.count)
                overlay.connectsTo = .pointA
                newOverlays.append(overlay)
            }
        }

        // Check if overlays need updating
        let existingOverlays = mapView.overlays.compactMap { $0 as? LOSPathOverlay }
        let needsUpdate = existingOverlays.count != newOverlays.count ||
            !coordinatesEqual(coordinator.lastOverlayPointACoord, pointA?.coordinate) ||
            !coordinatesEqual(coordinator.lastOverlayPointBCoord, pointB?.coordinate) ||
            !coordinatesEqual(coordinator.lastOverlayRepeaterCoord, repeaterTarget?.coordinate)

        if needsUpdate {
            mapView.removeOverlays(existingOverlays)
            mapView.addOverlays(newOverlays)
            coordinator.lastOverlayPointACoord = pointA?.coordinate
            coordinator.lastOverlayPointBCoord = pointB?.coordinate
            coordinator.lastOverlayRepeaterCoord = repeaterTarget?.coordinate
        }
    }

    // MARK: - Update Visible Pin Views

    private func updateVisiblePinViews(in mapView: MKMapView, coordinator: Coordinator, selectionState: [UUID: LOSRepeaterSelectionInfo]) {
        for annotation in mapView.annotations {
            if let repeaterAnnotation = annotation as? LOSRepeaterAnnotation,
               let view = mapView.view(for: repeaterAnnotation) as? LOSRepeaterPinView {
                let info = selectionState[repeaterAnnotation.repeater.id]
                let selectedAs = info?.selectedAs
                let opacity = coordinator.markerOpacity(for: selectedAs)
                view.configure(selectedAs: selectedAs, opacity: opacity, showLabel: coordinator.showLabels)
            }

            if let pointAnnotation = annotation as? LOSPointAnnotation,
               let view = mapView.view(for: pointAnnotation) as? LOSPointPinView {
                let color: UIColor = pointAnnotation.pointID == .pointA ? .systemBlue : .systemGreen
                let opacity = coordinator.markerOpacity(for: pointAnnotation.pointID)
                view.configure(label: pointAnnotation.label, color: color, opacity: opacity)
            }

            if annotation is LOSRepeaterTargetAnnotation,
               let view = mapView.view(for: annotation) as? LOSRepeaterTargetPinView {
                let opacity = coordinator.markerOpacity(for: .repeater)
                view.configure(opacity: opacity)
            }
        }
    }

    // MARK: - Coordinate Comparison

    private func coordinatesEqual(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (l?, r?): return l.latitude == r.latitude && l.longitude == r.longitude
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var setCameraRegion: (MKCoordinateRegion?) -> Void

        var selectionState: [UUID: LOSRepeaterSelectionInfo] = [:]
        var onRepeaterTap: ((ContactDTO) -> Void)?
        var onMapTap: ((CLLocationCoordinate2D) -> Void)?
        var relocatingPoint: PointID?
        var showLabels = true

        var isUpdatingFromSwiftUI = false
        var lastAppliedRegion: MKCoordinateRegion?
        var lastAppliedRegionVersion = -1
        var hasPendingProgrammaticRegion = false

        // Change detection
        var previousSelectedIDs: Set<UUID> = []
        var lastOverlayPointACoord: CLLocationCoordinate2D?
        var lastOverlayPointBCoord: CLLocationCoordinate2D?
        var lastOverlayRepeaterCoord: CLLocationCoordinate2D?
        var lastRelocatingPoint: PointID?

        private var hasReceivedInitialRegion = false
        var pendingRegionTask: Task<Void, Never>?

        lazy var mapView: MKMapView = NoDoubleTapMapView()

        init(setCameraRegion: @escaping (MKCoordinateRegion?) -> Void) {
            self.setCameraRegion = setCameraRegion
        }

        // MARK: - Map Tap Handling

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onMapTap?(coordinate)
        }

        // Avoid intercepting annotation view taps
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            !(touch.view is MKAnnotationView)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let clusterAnnotation = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: annotation
                ) as? TracePathClusterView ?? TracePathClusterView(
                    annotation: annotation,
                    reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                )
                view.configure(with: clusterAnnotation)
                return view
            }

            if let repeaterAnnotation = annotation as? LOSRepeaterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: LOSRepeaterPinView.reuseIdentifier,
                    for: annotation
                ) as? LOSRepeaterPinView ?? LOSRepeaterPinView(
                    annotation: annotation,
                    reuseIdentifier: LOSRepeaterPinView.reuseIdentifier
                )

                let info = selectionState[repeaterAnnotation.repeater.id]
                let selectedAs = info?.selectedAs
                view.configure(selectedAs: selectedAs, opacity: markerOpacity(for: selectedAs), showLabel: showLabels)

                view.onTap = { [weak self] in
                    self?.onRepeaterTap?(repeaterAnnotation.repeater)
                }

                return view
            }

            if let pointAnnotation = annotation as? LOSPointAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: LOSPointPinView.reuseIdentifier,
                    for: annotation
                ) as? LOSPointPinView ?? LOSPointPinView(
                    annotation: annotation,
                    reuseIdentifier: LOSPointPinView.reuseIdentifier
                )

                let color: UIColor = pointAnnotation.pointID == .pointA ? .systemBlue : .systemGreen
                view.configure(label: pointAnnotation.label, color: color, opacity: markerOpacity(for: pointAnnotation.pointID))
                return view
            }

            if annotation is LOSRepeaterTargetAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: LOSRepeaterTargetPinView.reuseIdentifier,
                    for: annotation
                ) as? LOSRepeaterTargetPinView ?? LOSRepeaterTargetPinView(
                    annotation: annotation,
                    reuseIdentifier: LOSRepeaterTargetPinView.reuseIdentifier
                )

                view.configure(opacity: markerOpacity(for: .repeater))
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let pathOverlay = overlay as? LOSPathOverlay {
                let opacity = lineOpacity(connectsTo: pathOverlay.connectsTo)
                return LOSPathRenderer(overlay: pathOverlay, opacity: opacity)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)

            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isUpdatingFromSwiftUI else { return }

            if hasPendingProgrammaticRegion {
                hasPendingProgrammaticRegion = false
                hasReceivedInitialRegion = true
                lastAppliedRegion = mapView.region
                return
            }

            if !hasReceivedInitialRegion {
                hasReceivedInitialRegion = true
                lastAppliedRegion = mapView.region
                return
            }

            lastAppliedRegion = mapView.region

            pendingRegionTask?.cancel()
            pendingRegionTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                self.setCameraRegion(mapView.region)
            }
        }

        // MARK: - Opacity Helpers

        func markerOpacity(for pointID: PointID?) -> CGFloat {
            guard let relocating = relocatingPoint else { return 1.0 }
            guard let pointID else { return 1.0 }
            return relocating == pointID ? 0.4 : 1.0
        }

        func lineOpacity(connectsTo pointID: PointID) -> CGFloat {
            guard let relocating = relocatingPoint else { return 0.7 }

            if relocating == .repeater { return 0.3 }

            switch pointID {
            case .pointA:
                return relocating == .pointA ? 0.3 : 0.7
            case .pointB:
                return relocating == .pointB ? 0.3 : 0.7
            case .repeater:
                return 0.7
            }
        }
    }
}

