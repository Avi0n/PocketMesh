import Foundation
import MC1Services

/// Conversation type discriminator for the unified chat view.
/// Not `@MainActor` — no mutable state. `@State` on the view provides main-actor isolation.
enum ChatConversationType: Sendable {
    case dm(ContactDTO)
    case channel(ChannelDTO)

    // MARK: - Computed Properties

    var navigationTitle: String {
        switch self {
        case .dm(let contact):
            contact.displayName
        case .channel(let channel):
            channel.name.isEmpty
                ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index))
                : channel.name
        }
    }

    var navigationSubtitle: String {
        switch self {
        case .dm(let contact):
            if contact.isFloodRouted {
                L10n.Chats.Chats.ConnectionStatus.floodRouting
            } else {
                L10n.Chats.Chats.ConnectionStatus.direct(contact.pathHopCount)
            }
        case .channel:
            if isPublicStyleChannel {
                L10n.Chats.Chats.Channel.typePublic
            } else {
                L10n.Chats.Chats.Channel.typePrivate
            }
        }
    }

    var conversationID: UUID {
        switch self {
        case .dm(let contact):
            contact.id
        case .channel(let channel):
            channel.id
        }
    }

    var isPublicStyleChannel: Bool {
        switch self {
        case .dm:
            false
        case .channel(let channel):
            channel.isPublicChannel || channel.name.hasPrefix("#")
        }
    }

    // MARK: - Mutation

    /// Replaces the contact for DM conversations (contact refresh on dismiss).
    /// Channels are never mutated this way.
    mutating func replacing(contact: ContactDTO) {
        if case .dm = self { self = .dm(contact) }
    }
}
