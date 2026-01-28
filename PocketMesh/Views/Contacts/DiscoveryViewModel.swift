import CoreLocation
import SwiftUI
import PocketMeshServices

/// Segment for the discovery picker
enum DiscoverSegment: String, CaseIterable {
    case all
    case contacts
    case network

    var localizedTitle: String {
        switch self {
        case .all: L10n.Contacts.Contacts.Discovery.Segment.all
        case .contacts: L10n.Contacts.Contacts.Discovery.Segment.contacts
        case .network: L10n.Contacts.Contacts.Discovery.Segment.network
        }
    }
}

/// ViewModel for discovery view
@Observable
@MainActor
final class DiscoveryViewModel {

    // MARK: - Properties

    /// Discovered contacts from the mesh network
    var discoveredContacts: [ContactDTO] = []

    /// Loading state
    var isLoading = false

    /// Whether data has been loaded at least once (prevents empty state flash)
    var hasLoadedOnce = false

    /// Error message to display
    var errorMessage: String?

    // MARK: - Dependencies

    private var dataStore: DataStore?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.offlineDataStore
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Load Contacts

    func loadDiscoveredContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        isLoading = true
        errorMessage = nil

        do {
            discoveredContacts = try await dataStore.fetchDiscoveredContacts(deviceID: deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoadedOnce = true
        isLoading = false
    }

    // MARK: - Delete

    func deleteDiscoveredContact(_ contact: ContactDTO) async {
        guard let dataStore else { return }

        // Remove from UI immediately
        discoveredContacts.removeAll { $0.id == contact.id }

        do {
            try await dataStore.deleteContact(id: contact.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAllDiscoveredContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            try await dataStore.clearDiscoveredContacts(deviceID: deviceID)
            discoveredContacts = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtering

    func filteredContacts(
        searchText: String,
        segment: DiscoverSegment,
        sortOrder: NodeSortOrder,
        userLocation: CLLocation?
    ) -> [ContactDTO] {
        var result = discoveredContacts

        if searchText.isEmpty {
            switch segment {
            case .all:
                break
            case .contacts:
                result = result.filter { $0.type == .chat }
            case .network:
                result = result.filter { $0.type == .repeater || $0.type == .room }
            }
        } else {
            result = result.filter { contact in
                contact.displayName.localizedStandardContains(searchText)
            }
        }

        return sorted(result, by: sortOrder, userLocation: userLocation)
    }

    // MARK: - Sorting

    private func sorted(
        _ contacts: [ContactDTO],
        by order: NodeSortOrder,
        userLocation: CLLocation?
    ) -> [ContactDTO] {
        switch order {
        case .lastHeard:
            return contacts.sorted { $0.lastAdvertTimestamp > $1.lastAdvertTimestamp }
        case .name:
            return contacts.sorted {
                $0.displayName.localizedCompare($1.displayName) == .orderedAscending
            }
        case .distance:
            guard let userLocation else {
                return sorted(contacts, by: .name, userLocation: nil)
            }
            return contacts.sorted { lhs, rhs in
                let lhsHasLocation = lhs.hasLocation
                let rhsHasLocation = rhs.hasLocation

                if lhsHasLocation != rhsHasLocation {
                    return lhsHasLocation
                }

                guard lhsHasLocation && rhsHasLocation else {
                    return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
                }

                let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
                let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)

                return lhsLocation.distance(from: userLocation) < rhsLocation.distance(from: userLocation)
            }
        }
    }
}
