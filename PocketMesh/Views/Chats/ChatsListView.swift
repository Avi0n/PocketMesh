import PocketMeshKit
import SwiftData
import SwiftUI

struct ChatsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(sort: \Message.timestamp, order: .reverse)
    private var allMessages: [Message]

    @State private var selectedContact: Contact?
    @State private var selectedChannel: Channel?

    var body: some View {
        NavigationStack {
            List {
                // Direct message conversations
                if !directConversations.isEmpty {
                    Section("Direct Messages") {
                        ForEach(directConversations, id: \.contact?.id) { conversation in
                            if let contact = conversation.contact {
                                NavigationLink(value: ChatDestination.contact(contact)) {
                                    ConversationRow(
                                        name: contact.name,
                                        lastMessage: conversation.lastMessage,
                                        unreadCount: conversation.unreadCount,
                                        timestamp: conversation.timestamp,
                                    )
                                }
                            }
                        }
                    }
                }

                // Channel conversations
                if !channelConversations.isEmpty {
                    Section("Channels") {
                        ForEach(channelConversations, id: \.channel?.id) { conversation in
                            if let channel = conversation.channel {
                                NavigationLink(value: ChatDestination.channel(channel)) {
                                    ConversationRow(
                                        name: channel.name,
                                        lastMessage: conversation.lastMessage,
                                        unreadCount: conversation.unreadCount,
                                        timestamp: conversation.timestamp,
                                    )
                                }
                            }
                        }
                    }
                }

                if directConversations.isEmpty, channelConversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "message",
                        description: Text("Start messaging by selecting a contact or joining a channel"),
                    )
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: ChatDestination.self) { destination in
                switch destination {
                case let .contact(contact):
                    ConversationView(contact: contact)
                case let .channel(channel):
                    ChannelConversationView(channel: channel)
                }
            }
        }
    }

    private var directConversations: [ConversationSummary] {
        Dictionary(grouping: allMessages.filter { $0.contact != nil }, by: { $0.contact })
            .compactMap { contact, messages -> ConversationSummary? in
                guard let contact,
                      let lastMessage = messages.first else { return nil }

                return ConversationSummary(
                    contact: contact,
                    channel: nil,
                    lastMessage: lastMessage.text,
                    timestamp: lastMessage.timestamp,
                    unreadCount: messages.count(where: { !$0.isOutgoing }),
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var channelConversations: [ConversationSummary] {
        Dictionary(grouping: allMessages.filter { $0.channel != nil }, by: { $0.channel })
            .compactMap { channel, messages -> ConversationSummary? in
                guard let channel,
                      let lastMessage = messages.first else { return nil }

                return ConversationSummary(
                    contact: nil,
                    channel: channel,
                    lastMessage: lastMessage.text,
                    timestamp: lastMessage.timestamp,
                    unreadCount: messages.count(where: { !$0.isOutgoing }),
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

enum ChatDestination: Hashable {
    case contact(Contact)
    case channel(Channel)
}

struct ConversationSummary {
    let contact: Contact?
    let channel: Channel?
    let lastMessage: String
    let timestamp: Date
    let unreadCount: Int
}

struct ConversationRow: View {
    let name: String
    let lastMessage: String
    let unreadCount: Int
    let timestamp: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(name.prefix(1).uppercased())
                        .font(.title3)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
