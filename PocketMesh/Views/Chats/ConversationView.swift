import SwiftUI
import SwiftData
import PocketMeshKit

struct ConversationView: View {

    let contact: Contact

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var messages: [Message]
    @State private var messageText = ""
    @State private var replyingTo: Message?
    @FocusState private var isInputFocused: Bool

    init(contact: Contact) {
        self.contact = contact

        let contactPublicKey = contact.publicKey
        // Query messages for this contact
        _messages = Query(
            filter: #Predicate<Message> { message in
                message.contact?.publicKey == contactPublicKey
            },
            sort: [SortDescriptor(\.timestamp, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, onReply: {
                                replyingTo = message
                                isInputFocused = true
                            })
                            .id(message.id)
                            .contextMenu {
                                Button("Reply") {
                                    replyingTo = message
                                    isInputFocused = true
                                }

                                if message.isOutgoing && message.deliveryStatus == .queued {
                                    Button("Delete", role: .destructive) {
                                        deleteMessage(message)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Reply indicator
            if let replyingTo = replyingTo {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(replyingTo.text)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: { self.replyingTo = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }

            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isInputFocused)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.isEmpty ? Color.secondary : Color.blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendMessage() {
        guard !messageText.isEmpty,
              let device = coordinator.connectedDevice,
              let messageService = coordinator.messageService else {
            return
        }

        let text = messageText
        messageText = ""
        replyingTo = nil

        Task {
            do {
                try await messageService.sendMessage(text: text, to: contact, device: device)
            } catch {
                // Show error alert
                print("Failed to send message: \(error)")
            }
        }
    }

    private func deleteMessage(_ message: Message) {
        guard let messageService = coordinator.messageService else { return }

        do {
            try messageService.deleteMessage(message)
        } catch {
            print("Failed to delete message: \(error)")
        }
    }
}
