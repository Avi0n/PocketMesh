import SwiftUI

struct ContactsSearchEmptyView: View {
    @Binding var selectedSegment: NodeSegment
    let isSearching: Bool
    let searchText: String

    var body: some View {
        VStack {
            NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            ContentUnavailableView(
                L10n.Contacts.Contacts.List.Empty.Search.title,
                systemImage: "magnifyingglass",
                description: Text(L10n.Contacts.Contacts.List.Empty.Search.description(searchText))
            )

            Spacer()
        }
    }
}
