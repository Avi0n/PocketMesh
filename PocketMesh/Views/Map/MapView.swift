import MapKit
import PocketMeshKit
import SwiftData
import SwiftUI

struct MapView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var contactAnnotations: [MapContactAnnotation] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180),
    )

    @State private var selectedContact: Contact?
    @State private var lastUpdateTime: Date = .distantPast
    @State private var updateTimer: Timer?
    @State private var isUserInteracting = false
    @State private var isProcessingTap = false

    // Performance optimization states
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var loadingTask: Task<Void, Never>?

    // Smart caching system
    @State private var cachedAnnotations: [MapContactAnnotation] = []
    @State private var lastCacheUpdate: Date = .init()
    private let cacheValidityDuration: TimeInterval = 30.0 // 30 seconds

    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, annotationItems: contactAnnotations) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        Button {
                            guard !isProcessingTap else { return }
                            guard canShowContactDetails(annotation.contact) else { return }

                            isProcessingTap = true
                            selectedContact = annotation.contact

                            // Reset processing state after brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isProcessingTap = false
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Image(systemName: iconName(for: annotation.contact.type))
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(iconColor(for: annotation.contact.type))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2),
                                    )
                                    .shadow(radius: 3)

                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.caption)
                                    .foregroundStyle(iconColor(for: annotation.contact.type))
                                    .offset(y: -5)
                            }
                        }
                        .disabled(isProcessingTap) // Provide visual feedback
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { _ in
                            isUserInteracting = true
                        }
                        .onEnded { _ in
                            // User finished interacting, allow updates after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isUserInteracting = false
                                Task {
                                    await updateAnnotationsIfNeeded()
                                }
                            }
                        },
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading, !hasLoadedOnce {
                    VStack {
                        ProgressView("Loading contacts...")
                            .scaleEffect(1.2)
                        Text("Finding contact locations...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .background(Color(uiColor: .systemBackground).opacity(0.9))
                } else if contactAnnotations.isEmpty, !isLoading {
                    VStack {
                        Spacer()
                        ContentUnavailableView(
                            "No Contact Locations",
                            systemImage: "map",
                            description: Text("Contacts will appear on the map once they broadcast their location"),
                        )
                        Spacer()
                    }
                    .background(Color(uiColor: .systemBackground).opacity(0.9))
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedContact) { contact in
                ContactDetailSheet(contact: contact)
            }
            .onAppear {
                if !hasLoadedOnce {
                    loadInitialData()
                }
                startPeriodicUpdates()
            }
            .onDisappear {
                stopPeriodicUpdates()
                loadingTask?.cancel()
            }
        }
    }

    // Private methods for optimized annotation management

    private func loadInitialData() {
        // Set loading state immediately to show loading indicator
        isLoading = true

        loadingTask = Task {
            do {
                let repository = ContactRepository(modelContext: modelContext)
                let contacts = try await repository.getContactsWithLocation()

                await MainActor.run {
                    let annotations: [MapContactAnnotation] = contacts.compactMap { contact in
                        guard contact.latitude != nil, contact.longitude != nil else { return nil }
                        return MapContactAnnotation(contact: contact)
                    }

                    // Update cache with initial data
                    cachedAnnotations = annotations
                    contactAnnotations = annotations
                    isLoading = false
                    hasLoadedOnce = true
                    updateRegion()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    hasLoadedOnce = true
                    print("Failed to load initial contacts: \(error)")
                }
            }
        }
    }

    private func startPeriodicUpdates() {
        // Update every 30 seconds to check for contact changes (performance optimization)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await updateAnnotationsIfNeeded()
            }
        }
    }

    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateAnnotationsIfNeeded() async {
        // Don't update if user is actively panning/zooming or still loading initial data
        guard !isUserInteracting, !isLoading else { return }

        let now = Date()

        // Use cache if still valid and not empty
        if now.timeIntervalSince(lastCacheUpdate) < cacheValidityDuration, !cachedAnnotations.isEmpty {
            // Check if cached data differs from current annotations
            if cachedAnnotations.count != contactAnnotations.count ||
                !cachedAnnotations.elementsEqual(contactAnnotations, by: { $0.id == $1.id })
            {
                await MainActor.run {
                    withAnimation(.none) {
                        contactAnnotations = cachedAnnotations
                    }
                    updateRegion()
                }
            }
            return
        }

        await updateAnnotations()
        lastCacheUpdate = now
    }

    private func updateAnnotations() async {
        do {
            let repository = ContactRepository(modelContext: modelContext)
            let contacts = try await repository.getContactsWithLocation()

            await MainActor.run {
                let newAnnotations: [MapContactAnnotation] = contacts.compactMap { contact in
                    guard contact.latitude != nil, contact.longitude != nil else { return nil }
                    return MapContactAnnotation(contact: contact)
                }

                // Update cache with latest data
                cachedAnnotations = newAnnotations

                // Only update if annotations actually changed
                if newAnnotations.count != contactAnnotations.count ||
                    !newAnnotations.elementsEqual(contactAnnotations, by: { $0.id == $1.id })
                {
                    // Use no animation to prevent conflicts with user interactions
                    withAnimation(.none) {
                        contactAnnotations = newAnnotations
                    }
                    updateRegion()
                }

                lastUpdateTime = Date()
            }
        } catch {
            await MainActor.run {
                print("Error updating annotations: \(error)")
            }
        }
    }
}

// MARK: - Helper Methods

extension MapView {
    private func iconName(for type: ContactType) -> String {
        switch type {
        case .repeater:
            "antenna.radiowaves.left.and.right.circle.fill"
        case .room:
            "person.3.fill"
        case .chat, .none:
            "person.circle.fill"
        }
    }

    private func iconColor(for type: ContactType) -> Color {
        switch type {
        case .repeater:
            .orange
        case .room:
            .purple
        case .chat, .none:
            .blue
        }
    }

    private func updateRegion() {
        withAnimation {
            region = calculateOptimalRegion(for: contactAnnotations)
        }
    }

    private func canShowContactDetails(_ contact: Contact) -> Bool {
        // Basic validation to ensure contact has minimum required data
        !contact.name.isEmpty && !contact.publicKey.isEmpty
    }

    private func calculateOptimalRegion(for annotations: [MapContactAnnotation]) -> MKCoordinateRegion {
        let contacts = annotations.map(\.contact)
        guard !contacts.isEmpty else {
            // Default to world view when no contacts
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180),
            )
        }

        let coordinates = annotations.compactMap { annotation -> CLLocationCoordinate2D? in
            let contact = annotation.contact
            guard let lat = contact.latitude, let lon = contact.longitude else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        guard !coordinates.isEmpty else {
            // No valid coordinates
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180),
            )
        }

        if coordinates.count == 1 {
            // Single contact - zoom in close
            let coordinate = coordinates[0]
            return MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05),
            )
        }

        // Multiple contacts - calculate bounding box
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2,
        )

        // Add 20% padding to the span
        let latDelta = (maxLat - minLat) * 1.2
        let lonDelta = (maxLon - minLon) * 1.2

        // Apply minimum zoom level
        let span = MKCoordinateSpan(
            latitudeDelta: max(latDelta, 0.01),
            longitudeDelta: max(lonDelta, 0.01),
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}

struct MapContactAnnotation: Identifiable {
    let id: UUID // Use Contact's stable UUID
    let contact: Contact

    init(contact: Contact) {
        self.contact = contact
        id = contact.id // Use Contact's stable UUID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: contact.latitude ?? 0,
            longitude: contact.longitude ?? 0,
        )
    }
}
