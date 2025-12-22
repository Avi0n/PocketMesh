import SwiftUI
import PocketMeshServices

/// ViewModel for contact management
@Observable
@MainActor
final class ContactsViewModel {

    // MARK: - Properties

    /// All contacts
    var contacts: [ContactDTO] = []

    /// Loading state
    var isLoading = false

    /// Syncing state
    var isSyncing = false

    /// Sync progress (current, total)
    var syncProgress: (Int, Int)?

    /// Error message if any
    var errorMessage: String?

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var contactService: ContactService?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.services?.dataStore
        self.contactService = appState.services?.contactService
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore, contactService: ContactService) {
        self.dataStore = dataStore
        self.contactService = contactService
    }

    // MARK: - Load Contacts

    /// Load contacts from local database
    func loadContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        isLoading = true
        errorMessage = nil

        do {
            contacts = try await dataStore.fetchContacts(deviceID: deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sync Contacts

    /// Sync contacts from device
    func syncContacts(deviceID: UUID) async {
        guard let contactService else { return }

        isSyncing = true
        syncProgress = nil
        errorMessage = nil

        // Set up progress handler
        await contactService.setSyncProgressHandler { [weak self] current, total in
            Task { @MainActor in
                self?.syncProgress = (current, total)
            }
        }

        do {
            let result = try await contactService.syncContacts(deviceID: deviceID)

            // Reload from database
            await loadContacts(deviceID: deviceID)

            // Clear sync progress
            syncProgress = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Contact Actions

    /// Toggle favorite status
    func toggleFavorite(contact: ContactDTO) async {
        guard let contactService else { return }

        do {
            try await contactService.updateContactPreferences(
                contactID: contact.id,
                isFavorite: !contact.isFavorite
            )

            // Update local list
            if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                await loadContacts(deviceID: contact.deviceID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle blocked status
    func toggleBlocked(contact: ContactDTO) async {
        guard let contactService else { return }

        do {
            try await contactService.updateContactPreferences(
                contactID: contact.id,
                isBlocked: !contact.isBlocked
            )

            // Update local list
            await loadContacts(deviceID: contact.deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update nickname
    func updateNickname(contact: ContactDTO, nickname: String?) async {
        guard let contactService else { return }

        do {
            try await contactService.updateContactPreferences(
                contactID: contact.id,
                nickname: nickname?.isEmpty == true ? nil : nickname
            )

            // Update local list
            await loadContacts(deviceID: contact.deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete contact
    func deleteContact(_ contact: ContactDTO) async {
        guard let contactService else { return }

        do {
            try await contactService.removeContact(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey
            )

            // Remove from local list
            contacts.removeAll { $0.id == contact.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtering

    /// Returns contacts filtered and sorted
    func filteredContacts(searchText: String, showFavoritesOnly: Bool) -> [ContactDTO] {
        var result = contacts

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter { contact in
                contact.displayName.localizedStandardContains(searchText)
            }
        }

        // Filter favorites
        if showFavoritesOnly {
            result = result.filter(\.isFavorite)
        }

        // Sort: favorites first, then alphabetically
        return result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Group contacts by type
    func groupedContacts(searchText: String) -> [(type: ContactType, contacts: [ContactDTO])] {
        let filtered = filteredContacts(searchText: searchText, showFavoritesOnly: false)

        var groups: [(type: ContactType, contacts: [ContactDTO])] = []

        // Favorites section
        let favorites = filtered.filter(\.isFavorite)
        if !favorites.isEmpty {
            groups.append((.chat, favorites)) // Using chat as "favorites" type
        }

        // Group by actual type
        for type in [ContactType.chat, .repeater, .room] {
            let typeContacts = filtered.filter { $0.type == type && !$0.isFavorite }
            if !typeContacts.isEmpty {
                groups.append((type, typeContacts))
            }
        }

        return groups
    }
}
