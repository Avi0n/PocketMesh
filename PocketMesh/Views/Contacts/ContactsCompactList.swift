import SwiftUI
import PocketMeshServices
import CoreLocation

struct ContactsCompactList: View {
    @Environment(\.appState) private var appState

    let filteredContacts: [ContactDTO]
    let isSearching: Bool
    let viewModel: ContactsViewModel
    @Binding var selectedSegment: NodeSegment

    var body: some View {
        List {
            Section {
                NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)

            ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                ContactRowView(
                    contact: contact,
                    showTypeLabel: isSearching,
                    userLocation: appState.locationService.currentLocation,
                    index: index,
                    isTogglingFavorite: viewModel.togglingFavoriteID == contact.id
                )
                .listChevron()
                .background {
                    NavigationLink(value: contact) { EmptyView() }
                        .opacity(0)
                }
                .contactSwipeActions(contact: contact, viewModel: viewModel)
            }
        }
        .listStyle(.plain)
    }
}
