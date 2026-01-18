import MapKit
import os
import SwiftUI
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "MapRepresentable")

/// UIViewRepresentable wrapper for MKMapView with custom contact annotations
struct MKMapViewRepresentable: UIViewRepresentable {
    let contacts: [ContactDTO]
    let mapType: MKMapType
    let showLabels: Bool
    let showsUserLocation: Bool

    @Binding var selectedContact: ContactDTO?
    @Binding var cameraRegion: MKCoordinateRegion?

    // Callbacks for callout actions
    let onDetailTap: (ContactDTO) -> Void
    let onMessageTap: (ContactDTO) -> Void
    /// Called once with a closure that returns snapshot parameters from the actual MKMapView (bypasses async binding)
    var onSnapshotParamsGetter: ((@escaping () -> (camera: MKMapCamera, size: CGSize)?) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = context.coordinator.mapView

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation

        // Register annotation views
        mapView.register(
            ContactPinView.self,
            forAnnotationViewWithReuseIdentifier: ContactPinView.reuseIdentifier
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        // Provide closure to get snapshot params directly from MKMapView (bypasses async binding lag)
        onSnapshotParamsGetter? { [weak mapView] in
            guard let mapView else { return nil }
            return (camera: mapView.camera.copy() as! MKMapCamera, size: mapView.bounds.size)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Update binding setters each render cycle
        coordinator.setSelectedContact = { selectedContact = $0 }
        coordinator.setCameraRegion = { cameraRegion = $0 }
        coordinator.onDetailTap = onDetailTap
        coordinator.onMessageTap = onMessageTap
        coordinator.showLabels = showLabels

        // Mark as programmatic update to prevent feedback loops
        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Update map type
        mapView.mapType = mapType

        // Update user location visibility
        mapView.showsUserLocation = showsUserLocation

        // Update annotations
        updateAnnotations(in: mapView, coordinator: coordinator)

        // Update selection state
        updateSelection(in: mapView, coordinator: coordinator)

        // Update region if changed programmatically
        if let region = cameraRegion {
            // Check if binding has caught up with pending user gesture
            if let pendingGesture = coordinator.pendingUserGestureRegion {
                if region.isApproximatelyEqual(to: pendingGesture) {
                    // Binding now reflects user gesture, clear pending state
                    logger.debug("Region: binding caught up, clearing pendingUserGestureRegion")
                    coordinator.pendingUserGestureRegion = nil
                } else {
                    // Binding is stale (hasn't caught up with user gesture), skip applying
                    logger.debug("Region: binding stale (span=\(region.span.latitudeDelta, format: .fixed(precision: 4))), pending span=\(pendingGesture.span.latitudeDelta, format: .fixed(precision: 4))), skipping")
                    return
                }
            }

            let shouldUpdate = coordinator.lastAppliedRegion == nil ||
                !coordinator.lastAppliedRegion!.isApproximatelyEqual(to: region)

            if shouldUpdate {
                logger.debug("Region: applying via setRegion (span=\(region.span.latitudeDelta, format: .fixed(precision: 4)))")
                coordinator.hasPendingProgrammaticRegion = true
                coordinator.hasAppliedInitialRegion = true
                mapView.setRegion(region, animated: coordinator.lastAppliedRegion != nil)
                coordinator.lastAppliedRegion = region
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Annotation Management

    private func updateAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
        let currentAnnotations = mapView.annotations.compactMap { $0 as? ContactAnnotation }
        let currentIDs = Set(currentAnnotations.map { $0.contact.id })
        let newIDs = Set(contacts.map { $0.id })

        // Remove annotations that are no longer in the list
        let toRemove = currentAnnotations.filter { !newIDs.contains($0.contact.id) }
        mapView.removeAnnotations(toRemove)

        // Add new annotations
        let existingIDs = currentIDs.subtracting(Set(toRemove.map { $0.contact.id }))
        let toAdd = contacts.filter { !existingIDs.contains($0.id) }
            .map { ContactAnnotation(contact: $0) }
        mapView.addAnnotations(toAdd)

        // Only update name labels if showLabels or selection actually changed
        // Iterating and calling view(for:) on every update interferes with MKMapView clustering
        let selectedID = selectedContact?.id
        let labelsChanged = showLabels != coordinator.lastShowLabels
        let selectionChanged = selectedID != coordinator.lastSelectedContactID

        if labelsChanged || selectionChanged {
            for annotation in mapView.annotations.compactMap({ $0 as? ContactAnnotation }) {
                if let view = mapView.view(for: annotation) as? ContactPinView {
                    view.showsNameLabel = showLabels && selectedID != annotation.contact.id
                }
            }
            coordinator.lastShowLabels = showLabels
            coordinator.lastSelectedContactID = selectedID
        }
    }

    private func updateSelection(in mapView: MKMapView, coordinator: Coordinator) {
        let currentlySelectedAnnotation = mapView.selectedAnnotations.first as? ContactAnnotation

        if let selectedContact {
            // Find the annotation for this contact
            guard let annotation = mapView.annotations
                .compactMap({ $0 as? ContactAnnotation })
                .first(where: { $0.contact.id == selectedContact.id }) else {
                return
            }

            // Only select if not already selected
            if currentlySelectedAnnotation?.contact.id != selectedContact.id {
                mapView.selectAnnotation(annotation, animated: true)
            }
        } else if let current = currentlySelectedAnnotation {
            // Deselect all
            mapView.deselectAnnotation(current, animated: true)
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate {
        // Binding setters for deferred updates
        var setSelectedContact: ((ContactDTO?) -> Void)?
        var setCameraRegion: ((MKCoordinateRegion?) -> Void)?

        // Callbacks
        var onDetailTap: ((ContactDTO) -> Void)?
        var onMessageTap: ((ContactDTO) -> Void)?

        // Configuration
        var showLabels: Bool = true

        // State management
        var isUpdatingFromSwiftUI = false
        var lastAppliedRegion: MKCoordinateRegion?
        var hasPendingProgrammaticRegion = false
        var hasAppliedInitialRegion = false

        /// Tracks pending user gesture region awaiting async binding sync.
        /// When set, the binding is considered stale until it matches this value.
        var pendingUserGestureRegion: MKCoordinateRegion?

        /// Timestamp of the last cluster tap handled by the gesture recognizer.
        /// Used to prevent double-handling when both gesture and delegate fire.
        var lastClusterTapTime: Date?

        /// Set before showAnnotations calls to ensure pendingUserGestureRegion is set
        /// even if hasPendingProgrammaticRegion is true from a prior setRegion.
        var hasPendingShowAnnotations = false

        // Previous state for change detection (avoid unnecessary view updates that interfere with clustering)
        var lastShowLabels: Bool = true
        var lastSelectedContactID: UUID?

        // Lazily created map view owned by coordinator
        lazy var mapView: MKMapView = {
            let map = MKMapView()
            return map
        }()

        // MARK: - Cluster Tap Handler

        @objc func clusterTapped(_ gesture: UITapGestureRecognizer) {
            guard let clusterView = gesture.view as? MKAnnotationView,
                  let cluster = clusterView.annotation as? MKClusterAnnotation else {
                return
            }
            // Mark that we handled this tap to prevent delegate double-handling
            lastClusterTapTime = Date()
            // Mark that we're about to call showAnnotations so regionDidChangeAnimated
            // will set pendingUserGestureRegion to protect against stale binding values
            hasPendingShowAnnotations = true
            logger.debug("Cluster: gesture tapped, calling showAnnotations for \(cluster.memberAnnotations.count) members")
            mapView.showAnnotations(cluster.memberAnnotations, animated: true)
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            // Don't provide custom view for user location
            if annotation is MKUserLocation {
                return nil
            }

            // Handle cluster annotations
            if annotation is MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: annotation
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                )
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "person.2.fill")
                view.displayPriority = .defaultHigh
                view.canShowCallout = false

                // Remove existing tap gestures to avoid duplicates on reuse
                view.gestureRecognizers?.filter { $0 is UITapGestureRecognizer }.forEach {
                    view.removeGestureRecognizer($0)
                }

                // Add tap gesture for immediate response (bypasses delegate selection delay)
                let tap = UITapGestureRecognizer(target: self, action: #selector(clusterTapped(_:)))
                view.addGestureRecognizer(tap)

                return view
            }

            // Handle contact annotations
            guard let contactAnnotation = annotation as? ContactAnnotation else {
                return nil
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: ContactPinView.reuseIdentifier,
                for: annotation
            ) as? ContactPinView ?? ContactPinView(
                annotation: annotation,
                reuseIdentifier: ContactPinView.reuseIdentifier
            )

            view.annotation = annotation
            view.showsNameLabel = showLabels
            // Must set clusteringIdentifier here before returning view, not in init/configure
            // MKMapView makes clustering decisions based on this value at return time
            view.clusteringIdentifier = "contact"
            view.onDetail = { [weak self] in
                self?.onDetailTap?(contactAnnotation.contact)
            }
            view.onMessage = { [weak self] in
                self?.onMessageTap?(contactAnnotation.contact)
            }

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            guard !isUpdatingFromSwiftUI else { return }

            // Ignore user location selection
            if annotation is MKUserLocation {
                return
            }

            // Handle cluster selection - zoom to show members
            // Skip if gesture recognizer already handled this tap (within 500ms)
            if let cluster = annotation as? MKClusterAnnotation {
                if let tapTime = lastClusterTapTime, Date().timeIntervalSince(tapTime) < 0.5 {
                    // Gesture already handled this tap, just deselect without zooming again
                    logger.debug("Cluster: didSelect skipped (gesture handled \(Date().timeIntervalSince(tapTime), format: .fixed(precision: 3))s ago)")
                    mapView.deselectAnnotation(cluster, animated: false)
                    return
                }
                logger.debug("Cluster: didSelect calling showAnnotations (fallback path)")
                mapView.deselectAnnotation(cluster, animated: false)
                hasPendingShowAnnotations = true
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }

            guard let contactAnnotation = annotation as? ContactAnnotation else { return }

            logger.debug("Selection: didSelect for \(contactAnnotation.contact.displayName)")

            // Update name label visibility
            if let view = mapView.view(for: annotation) as? ContactPinView {
                view.showsNameLabel = false
            }

            // Defer binding update to avoid SwiftUI state mutation during update
            Task { @MainActor in
                logger.debug("Selection: updating selectedContact binding")
                self.setSelectedContact?(contactAnnotation.contact)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
            guard !isUpdatingFromSwiftUI else { return }

            // Update name label visibility
            if let view = mapView.view(for: annotation) as? ContactPinView {
                view.showsNameLabel = showLabels
            }

            Task { @MainActor in
                self.setSelectedContact?(nil)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isUpdatingFromSwiftUI else {
                logger.debug("Region: regionDidChangeAnimated skipped (isUpdatingFromSwiftUI)")
                return
            }

            let newSpan = mapView.region.span.latitudeDelta

            // Handle showAnnotations region changes - must set pendingUserGestureRegion
            // to protect against stale binding values, since the binding wasn't updated
            if hasPendingShowAnnotations {
                logger.debug("Region: regionDidChangeAnimated from showAnnotations (span=\(newSpan, format: .fixed(precision: 4)))")
                hasPendingShowAnnotations = false
                hasPendingProgrammaticRegion = false // Clear if also set
                lastAppliedRegion = mapView.region
                pendingUserGestureRegion = mapView.region
                Task { @MainActor in
                    logger.debug("Region: updating cameraRegion binding (from showAnnotations)")
                    self.setCameraRegion?(mapView.region)
                }
                return
            }

            // Don't overwrite binding during programmatic region changes from setRegion
            if hasPendingProgrammaticRegion {
                logger.debug("Region: regionDidChangeAnimated from programmatic change (span=\(newSpan, format: .fixed(precision: 4)))")
                hasPendingProgrammaticRegion = false
                lastAppliedRegion = mapView.region
                return
            }

            // Don't write back until we've applied at least one programmatic region
            // This prevents the initial default region from overwriting the intended region
            guard hasAppliedInitialRegion else {
                logger.debug("Region: regionDidChangeAnimated before initial region (span=\(newSpan, format: .fixed(precision: 4)))")
                lastAppliedRegion = mapView.region
                return
            }

            // Track user-initiated region changes
            // Mark as pending so stale binding values won't revert this change
            logger.debug("Region: regionDidChangeAnimated setting pendingUserGestureRegion (span=\(newSpan, format: .fixed(precision: 4)))")
            lastAppliedRegion = mapView.region
            pendingUserGestureRegion = mapView.region

            Task { @MainActor in
                logger.debug("Region: updating cameraRegion binding")
                self.setCameraRegion?(mapView.region)
            }
        }
    }
}

// MARK: - MKCoordinateRegion Comparison

extension MKCoordinateRegion {
    func isApproximatelyEqual(to other: MKCoordinateRegion, tolerance: Double = 0.0001) -> Bool {
        abs(center.latitude - other.center.latitude) < tolerance &&
        abs(center.longitude - other.center.longitude) < tolerance &&
        abs(span.latitudeDelta - other.span.latitudeDelta) < tolerance &&
        abs(span.longitudeDelta - other.span.longitudeDelta) < tolerance
    }
}
