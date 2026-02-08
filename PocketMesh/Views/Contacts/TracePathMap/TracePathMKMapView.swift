import MapKit
import SwiftUI
import PocketMeshServices

/// UIViewRepresentable for trace path map with custom overlays and interactions
struct TracePathMKMapView: UIViewRepresentable {
    let repeaters: [ContactDTO]
    let lineOverlays: [PathLineOverlay]
    let badgeAnnotations: [StatsBadgeAnnotation]
    let mapType: MKMapType
    let showLabels: Bool

    @Binding var cameraRegion: MKCoordinateRegion?
    let cameraRegionVersion: Int

    // Pre-computed path membership for all repeaters (closure to defer computation to updateUIView)
    let pathState: () -> [UUID: TracePathMapViewModel.RepeaterPathInfo]
    let onRepeaterTap: (ContactDTO) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = context.coordinator.mapView
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Register annotation views
        mapView.register(
            TracePathRepeaterPinView.self,
            forAnnotationViewWithReuseIdentifier: TracePathRepeaterPinView.reuseIdentifier
        )
        mapView.register(
            TracePathClusterView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        mapView.register(
            StatsBadgeView.self,
            forAnnotationViewWithReuseIdentifier: StatsBadgeView.reuseIdentifier
        )

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Update callbacks and state
        let pathState = pathState()
        coordinator.pathState = pathState
        coordinator.onRepeaterTap = onRepeaterTap
        coordinator.showLabels = showLabels

        // Update map type
        mapView.mapType = mapType

        // Update repeater annotations
        updateRepeaterAnnotations(in: mapView, coordinator: coordinator, pathState: pathState)

        // Update overlays (with change detection)
        updateOverlays(in: mapView, coordinator: coordinator)

        // Update badge annotations (with change detection)
        updateBadgeAnnotations(in: mapView, coordinator: coordinator)

        // Update region only when explicitly requested (version changed)
        if cameraRegionVersion != coordinator.lastAppliedRegionVersion,
           let region = cameraRegion {
            coordinator.lastAppliedRegionVersion = cameraRegionVersion
            coordinator.hasPendingProgrammaticRegion = true
            mapView.setRegion(region, animated: coordinator.lastAppliedRegion != nil)
            coordinator.lastAppliedRegion = region
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(setCameraRegion: { cameraRegion = $0 })
    }

    // MARK: - Annotation Updates

    private func updateRepeaterAnnotations(
        in mapView: MKMapView,
        coordinator: Coordinator,
        pathState: [UUID: TracePathMapViewModel.RepeaterPathInfo]
    ) {
        let currentAnnotations = mapView.annotations.compactMap { $0 as? RepeaterAnnotation }
        let currentIDs = Set(currentAnnotations.map { $0.repeater.id })
        let newIDs = Set(repeaters.map { $0.id })

        // Remove old
        let toRemove = currentAnnotations.filter { !newIDs.contains($0.repeater.id) }
        mapView.removeAnnotations(toRemove)

        // Add new
        let existingIDs = currentIDs.subtracting(Set(toRemove.map { $0.repeater.id }))
        let toAdd = repeaters.filter { !existingIDs.contains($0.id) }
            .map { RepeaterAnnotation(repeater: $0) }
        mapView.addAnnotations(toAdd)

        // Determine which annotations changed path membership and need re-adding
        // (MapKit doesn't pick up clusteringIdentifier changes on existing views)
        let currentInPathIDs = Set(pathState.filter { $0.value.inPath }.map { $0.key })
        let previousInPathIDs = coordinator.previousInPathIDs
        let changedIDs = currentInPathIDs.symmetricDifference(previousInPathIDs)
        coordinator.previousInPathIDs = currentInPathIDs

        if !changedIDs.isEmpty {
            let toReAdd = mapView.annotations
                .compactMap { $0 as? RepeaterAnnotation }
                .filter { changedIDs.contains($0.repeater.id) }
            mapView.removeAnnotations(toReAdd)
            mapView.addAnnotations(toReAdd)
        }

        // Update visible pin views using pre-computed state
        for annotation in mapView.annotations.compactMap({ $0 as? RepeaterAnnotation }) {
            guard let view = mapView.view(for: annotation) as? TracePathRepeaterPinView else {
                continue
            }
            let info = pathState[annotation.repeater.id] ?? TracePathMapViewModel.RepeaterPathInfo(
                inPath: false, hopIndex: nil, isLastHop: false
            )
            view.configure(
                for: annotation.repeater,
                inPath: info.inPath,
                hopIndex: info.hopIndex,
                isLastHop: info.isLastHop,
                showLabel: showLabels
            )
        }
    }

    private func updateOverlays(in mapView: MKMapView, coordinator: Coordinator) {
        let newIdentities = Set(lineOverlays.map { ObjectIdentifier($0) })

        guard newIdentities != coordinator.lastOverlayIdentities else { return }
        coordinator.lastOverlayIdentities = newIdentities

        let existingPathOverlays = mapView.overlays.compactMap { $0 as? PathLineOverlay }
        mapView.removeOverlays(existingPathOverlays)
        mapView.addOverlays(lineOverlays)
    }

    private func updateBadgeAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
        let newIdentities = Set(badgeAnnotations.map { ObjectIdentifier($0) })

        guard newIdentities != coordinator.lastBadgeIdentities else { return }
        coordinator.lastBadgeIdentities = newIdentities

        let existingBadges = mapView.annotations.compactMap { $0 as? StatsBadgeAnnotation }
        mapView.removeAnnotations(existingBadges)
        mapView.addAnnotations(badgeAnnotations)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate {
        var setCameraRegion: (MKCoordinateRegion?) -> Void

        var pathState: [UUID: TracePathMapViewModel.RepeaterPathInfo] = [:]
        var onRepeaterTap: ((ContactDTO) -> Void)?
        var showLabels: Bool = true

        var isUpdatingFromSwiftUI = false
        var lastAppliedRegion: MKCoordinateRegion?
        var lastAppliedRegionVersion = -1
        var hasPendingProgrammaticRegion = false

        // Change detection state
        var previousInPathIDs: Set<UUID> = []
        var lastOverlayIdentities: Set<ObjectIdentifier> = []
        var lastBadgeIdentities: Set<ObjectIdentifier> = []

        /// Tracks whether the initial MKMapView region change has been received.
        /// The first region change is from MKMapView initialization, not a user gesture.
        private var hasReceivedInitialRegion = false

        /// Pending region update task for cancellation
        private var pendingRegionTask: Task<Void, Never>?

        lazy var mapView: MKMapView = NoDoubleTapMapView()

        init(setCameraRegion: @escaping (MKCoordinateRegion?) -> Void) {
            self.setCameraRegion = setCameraRegion
        }

        deinit {
            pendingRegionTask?.cancel()
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

            if let repeaterAnnotation = annotation as? RepeaterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: TracePathRepeaterPinView.reuseIdentifier,
                    for: annotation
                ) as? TracePathRepeaterPinView ?? TracePathRepeaterPinView(
                    annotation: annotation,
                    reuseIdentifier: TracePathRepeaterPinView.reuseIdentifier
                )

                let info = pathState[repeaterAnnotation.repeater.id]
                    ?? TracePathMapViewModel.RepeaterPathInfo(inPath: false, hopIndex: nil, isLastHop: false)

                view.configure(
                    for: repeaterAnnotation.repeater,
                    inPath: info.inPath,
                    hopIndex: info.hopIndex,
                    isLastHop: info.isLastHop,
                    showLabel: showLabels
                )

                view.onTap = { [weak self] in
                    self?.onRepeaterTap?(repeaterAnnotation.repeater)
                }

                return view
            }

            if let badgeAnnotation = annotation as? StatsBadgeAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: StatsBadgeView.reuseIdentifier,
                    for: annotation
                ) as? StatsBadgeView ?? StatsBadgeView(
                    annotation: annotation,
                    reuseIdentifier: StatsBadgeView.reuseIdentifier
                )
                view.configure(with: badgeAnnotation)
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let pathOverlay = overlay as? PathLineOverlay {
                return PathLineRenderer(overlay: pathOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)

            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            }
            // Repeater taps are handled by UITapGestureRecognizer on the pin view
            // to bypass MapKit's ~300ms selection delay
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isUpdatingFromSwiftUI else { return }

            if hasPendingProgrammaticRegion {
                hasPendingProgrammaticRegion = false
                hasReceivedInitialRegion = true
                lastAppliedRegion = mapView.region
                return
            }

            // The first region change is from MKMapView initialization, not a user gesture.
            // Don't block programmatic updates during this initial phase.
            if !hasReceivedInitialRegion {
                hasReceivedInitialRegion = true
                lastAppliedRegion = mapView.region
                return
            }

            lastAppliedRegion = mapView.region

            // Debounce region sync back to SwiftUI to avoid update cascade during panning
            pendingRegionTask?.cancel()
            pendingRegionTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                self.setCameraRegion(mapView.region)
            }
        }
    }
}

// MARK: - Repeater Annotation

final class RepeaterAnnotation: NSObject, MKAnnotation {
    let repeater: ContactDTO

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: repeater.latitude, longitude: repeater.longitude)
    }

    var title: String? { repeater.displayName }

    init(repeater: ContactDTO) {
        self.repeater = repeater
        super.init()
    }
}
