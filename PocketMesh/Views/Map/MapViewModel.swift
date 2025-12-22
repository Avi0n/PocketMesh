import SwiftUI
import MapKit
import PocketMeshServices

/// ViewModel for map contact locations
@Observable
@MainActor
final class MapViewModel {

    // MARK: - Properties

    /// All contacts with valid locations
    var contactsWithLocation: [ContactDTO] = []

    /// Loading state
    var isLoading = false

    /// Error message if any
    var errorMessage: String?

    /// Selected contact for detail display
    var selectedContact: ContactDTO?

    /// Camera position for map centering
    var cameraPosition: MapCameraPosition = .automatic

    // MARK: - Dependencies

    private var dataStore: PersistenceStore?
    private var deviceID: UUID?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.services?.dataStore
        self.deviceID = appState.connectedDevice?.id
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
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Map Interaction

    /// Center map on a specific contact
    func centerOnContact(_ contact: ContactDTO) {
        guard contact.hasLocation else { return }

        let coordinate = CLLocationCoordinate2D(
            latitude: contact.latitude,
            longitude: contact.longitude
        )

        cameraPosition = .camera(
            MapCamera(centerCoordinate: coordinate, distance: 5000)
        )
        selectedContact = contact
    }

    /// Center map to show all contacts
    func centerOnAllContacts() {
        guard !contactsWithLocation.isEmpty else {
            cameraPosition = .automatic
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
        let latDelta = max(0.01, (maxLat - minLat) * 1.5)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.5)

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region = MKCoordinateRegion(center: center, span: span)

        cameraPosition = .region(region)
    }

    /// Clear selection
    func clearSelection() {
        selectedContact = nil
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
