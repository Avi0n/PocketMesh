import SwiftUI
import MapKit
import MC1Services

/// ViewModel for map contact locations
@Observable
@MainActor
final class MapViewModel {

    // MARK: - Properties

    /// All contacts with valid locations
    var contactsWithLocation: [ContactDTO] = []

    /// Map points derived from contacts — stored to avoid reallocation on every body eval.
    private(set) var mapPoints: [MapPoint] = []

    /// Loading state
    var isLoading = false

    /// Error message if any
    var errorMessage: String?

    /// Camera region for map centering
    var cameraRegion: MKCoordinateRegion?

    /// Version counter for the camera region, incremented to signal a new camera target
    var cameraRegionVersion = 1

    /// Current map style selection
    var mapStyleSelection: MapStyleSelection = .standard

    /// Whether to show contact name labels
    var showLabels = true

    /// Whether the layers menu is showing
    var showingLayersMenu = false

    // MARK: - Dependencies

    private var dataStore: PersistenceStore?
    private var deviceID: UUID?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.offlineDataStore
        self.deviceID = appState.currentDeviceID
    }

    /// Configure with services (for testing)
    func configure(dataStore: PersistenceStore, deviceID: UUID?) {
        self.dataStore = dataStore
        self.deviceID = deviceID
    }

    // MARK: - Load Contacts

    /// Load contacts with valid locations from the database
    func loadContactsWithLocation() async {
        guard let dataStore, let deviceID else { return }

        isLoading = true
        errorMessage = nil

        do {
            let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
            contactsWithLocation = allContacts.filter(\.hasLocation)
            rebuildMapPoints()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Map Points

    private func rebuildMapPoints() {
        mapPoints = contactsWithLocation.map { contact in
            MapPoint(
                id: contact.id,
                coordinate: contact.coordinate,
                pinStyle: pinStyle(for: contact),
                label: contact.displayName,
                isClusterable: true,
                hopIndex: nil,
                badgeText: nil
            )
        }
    }

    private func pinStyle(for contact: ContactDTO) -> MapPoint.PinStyle {
        switch contact.type {
        case .chat: .contactChat
        case .repeater: .contactRepeater
        case .room: .contactRoom
        }
    }

    // MARK: - Map Interaction

    /// Center map on a specific contact
    func centerOnContact(_ contact: ContactDTO) {
        guard contact.hasLocation else { return }

        let coordinate = CLLocationCoordinate2D(
            latitude: contact.latitude,
            longitude: contact.longitude
        )

        // 5000 meters corresponds to roughly 0.045 degrees latitude span
        let span = MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
        cameraRegion = MKCoordinateRegion(center: coordinate, span: span)
        cameraRegionVersion += 1
    }

    /// Center map to show all contacts
    func centerOnAllContacts() {
        guard !contactsWithLocation.isEmpty else {
            cameraRegion = nil
            return
        }

        // Calculate bounding region
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for contact in contactsWithLocation {
            let lat = contact.latitude
            let lon = contact.longitude
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        // Clamp spans to valid MKCoordinateSpan bounds (lat: 0-180, lon: 0-360)
        let latDelta = min(180, max(0.01, (maxLat - minLat) * 1.5))
        let lonDelta = min(360, max(0.01, (maxLon - minLon) * 1.5))

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)

        cameraRegion = MKCoordinateRegion(center: center, span: span)
        cameraRegionVersion += 1
    }
}

// MARK: - ContactDTO Location Extension

extension ContactDTO {
    /// The coordinate for MapKit
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}
