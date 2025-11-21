import PocketMeshKit
import SwiftData
import SwiftUI

struct ChannelConversationView: View {
    let channel: Channel

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var messages: [Message]
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    init(channel: Channel) {
        self.channel = channel

        let channelId = channel.id
        // Query messages for this channel
        _messages = Query(
            filter: #Predicate<Message> { message in
                message.channel?.id == channelId
            },
            sort: [SortDescriptor(\.timestamp, order: .forward)],
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
                                // Channels don't support reply yet
                            })
                            .id(message.id)
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

            // Input bar
            HStack(spacing: 12) {
                TextField("Message to #\(channel.name)", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 4)
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
        .navigationTitle("#\(channel.name)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendMessage() {
        guard !messageText.isEmpty,
              let device = coordinator.connectedDevice,
              let channelService = coordinator.channelService
        else {
            return
        }

        let text = messageText
        messageText = ""

        Task {
            do {
                try await channelService.sendMessage(text: text, to: channel, device: device)
            } catch {
                // Show error alert
                print("Failed to send channel message: \(error)")
            }
        }
    }
}
