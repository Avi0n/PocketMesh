import SwiftUI
import PocketMeshServices

struct ContactSwipeActionsModifier: ViewModifier {
    @Environment(\.appState) private var appState

    let contact: ContactDTO
    let viewModel: ContactsViewModel

    private var isConnected: Bool {
        appState.connectionState == .ready
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteContact(contact)
                    }
                } label: {
                    Label(L10n.Contacts.Contacts.Common.delete, systemImage: "trash")
                }
                .disabled(!isConnected)

                Button {
                    Task {
                        await viewModel.toggleBlocked(contact: contact)
                    }
                } label: {
                    Label(
                        contact.isBlocked ? L10n.Contacts.Contacts.Swipe.unblock : L10n.Contacts.Contacts.Swipe.block,
                        systemImage: contact.isBlocked ? "hand.raised.slash" : "hand.raised"
                    )
                }
                .tint(.orange)
                .disabled(!isConnected)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task {
                        await viewModel.toggleFavorite(contact: contact)
                    }
                } label: {
                    Label(
                        contact.isFavorite ? L10n.Contacts.Contacts.Swipe.unfavorite : L10n.Contacts.Contacts.Row.favorite,
                        systemImage: contact.isFavorite ? "star.slash" : "star.fill"
                    )
                }
                .tint(.yellow)
                .disabled(!isConnected || viewModel.togglingFavoriteID == contact.id)
            }
    }
}

extension View {
    func contactSwipeActions(contact: ContactDTO, viewModel: ContactsViewModel) -> some View {
        modifier(ContactSwipeActionsModifier(contact: contact, viewModel: viewModel))
    }
}
