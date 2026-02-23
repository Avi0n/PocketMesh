import SwiftUI

struct ContactsEmptyView: View {
    @Binding var selectedSegment: NodeSegment
    let isSearching: Bool

    var body: some View {
        VStack {
            NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            switch selectedSegment {
            case .favorites:
                ContentUnavailableView(
                    L10n.Contacts.Contacts.List.Empty.Favorites.title,
                    systemImage: "star",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Favorites.description)
                )
            case .contacts:
                ContentUnavailableView(
                    L10n.Contacts.Contacts.List.Empty.Contacts.title,
                    systemImage: "person.2",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Contacts.description)
                )
            case .network:
                ContentUnavailableView(
                    L10n.Contacts.Contacts.List.Empty.Network.title,
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Network.description)
                )
            }

            Spacer()
        }
    }
}
