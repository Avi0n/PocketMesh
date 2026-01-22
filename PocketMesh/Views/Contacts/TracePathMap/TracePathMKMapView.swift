import MapKit
import SwiftUI
import PocketMeshServices
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "TracePathMKMapView")

/// UIViewRepresentable for trace path map with custom overlays and interactions
struct TracePathMKMapView: UIViewRepresentable {
    let repeaters: [ContactDTO]
    let lineOverlays: [PathLineOverlay]
    let badgeAnnotations: [StatsBadgeAnnotation]
    let mapType: MKMapType
    let showLabels: Bool

    @Binding var cameraRegion: MKCoordinateRegion?

    // Callbacks for repeater state
    let isRepeaterInPath: (ContactDTO) -> Bool
    let hopIndex: (ContactDTO) -> Int?
    let isLastHop: (ContactDTO) -> Bool
    let onRepeaterTap: (ContactDTO) -> Void
    let onCenterOnUser: () -> Void

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
            StatsBadgeView.self,
            forAnnotationViewWithReuseIdentifier: StatsBadgeView.reuseIdentifier
        )

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Update callbacks
        coordinator.isRepeaterInPath = isRepeaterInPath
        coordinator.hopIndex = hopIndex
        coordinator.isLastHop = isLastHop
        coordinator.onRepeaterTap = onRepeaterTap
        coordinator.showLabels = showLabels

        // Update map type
        mapView.mapType = mapType

        // Update repeater annotations
        updateRepeaterAnnotations(in: mapView, coordinator: coordinator)

        // Update overlays
        updateOverlays(in: mapView, coordinator: coordinator)

        // Update badge annotations
        updateBadgeAnnotations(in: mapView, coordinator: coordinator)

        // Update region
        if let region = cameraRegion, !coordinator.hasPendingUserGesture {
            let shouldUpdate = coordinator.lastAppliedRegion == nil ||
                !coordinator.lastAppliedRegion!.isApproximatelyEqual(to: region)

            if shouldUpdate {
                coordinator.hasPendingProgrammaticRegion = true
                mapView.setRegion(region, animated: coordinator.lastAppliedRegion != nil)
                coordinator.lastAppliedRegion = region
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(setCameraRegion: { cameraRegion = $0 })
    }

    // MARK: - Annotation Updates

    private func updateRepeaterAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
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

        // Update all pin views for selection state
        for annotation in mapView.annotations.compactMap({ $0 as? RepeaterAnnotation }) {
            if let view = mapView.view(for: annotation) as? TracePathRepeaterPinView {
                let inPath = isRepeaterInPath(annotation.repeater)
                let index = hopIndex(annotation.repeater)
                let isLast = isLastHop(annotation.repeater)
                view.configure(
                    for: annotation.repeater,
                    inPath: inPath,
                    hopIndex: index,
                    isLastHop: isLast,
                    showLabel: showLabels
                )
            }
        }
    }

    private func updateOverlays(in mapView: MKMapView, coordinator: Coordinator) {
        // Remove existing path overlays
        let existingPathOverlays = mapView.overlays.compactMap { $0 as? PathLineOverlay }
        mapView.removeOverlays(existingPathOverlays)

        // Add current overlays
        mapView.addOverlays(lineOverlays)
    }

    private func updateBadgeAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
        // Remove existing badge annotations
        let existingBadges = mapView.annotations.compactMap { $0 as? StatsBadgeAnnotation }
        mapView.removeAnnotations(existingBadges)

        // Add current badges
        mapView.addAnnotations(badgeAnnotations)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate {
        var setCameraRegion: (MKCoordinateRegion?) -> Void

        var isRepeaterInPath: ((ContactDTO) -> Bool)?
        var hopIndex: ((ContactDTO) -> Int?)?
        var isLastHop: ((ContactDTO) -> Bool)?
        var onRepeaterTap: ((ContactDTO) -> Void)?
        var showLabels: Bool = true

        var isUpdatingFromSwiftUI = false
        var lastAppliedRegion: MKCoordinateRegion?
        var hasPendingProgrammaticRegion = false
        var hasPendingUserGesture = false

        /// Pending region update task for cancellation
        private var pendingRegionTask: Task<Void, Never>?

        lazy var mapView: MKMapView = {
            let map = MKMapView()
            return map
        }()

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

            if let repeaterAnnotation = annotation as? RepeaterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: TracePathRepeaterPinView.reuseIdentifier,
                    for: annotation
                ) as? TracePathRepeaterPinView ?? TracePathRepeaterPinView(
                    annotation: annotation,
                    reuseIdentifier: TracePathRepeaterPinView.reuseIdentifier
                )

                let inPath = isRepeaterInPath?(repeaterAnnotation.repeater) ?? false
                let index = hopIndex?(repeaterAnnotation.repeater)
                let isLast = isLastHop?(repeaterAnnotation.repeater) ?? false

                view.configure(
                    for: repeaterAnnotation.repeater,
                    inPath: inPath,
                    hopIndex: index,
                    isLastHop: isLast,
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isUpdatingFromSwiftUI else { return }

            if hasPendingProgrammaticRegion {
                hasPendingProgrammaticRegion = false
                lastAppliedRegion = mapView.region
                return
            }

            lastAppliedRegion = mapView.region
            hasPendingUserGesture = true

            // Cancel any pending region task before starting new one
            pendingRegionTask?.cancel()
            pendingRegionTask = Task { @MainActor in
                // Check cancellation before any state mutations
                guard !Task.isCancelled else { return }
                self.setCameraRegion(mapView.region)
                // Brief delay then clear gesture flag
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self.hasPendingUserGesture = false
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
