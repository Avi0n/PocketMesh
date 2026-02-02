import SwiftUI

/// Telegram-style full-screen overlay for message actions with emoji picker
struct MessageContextOverlay<MessageContent: View>: View {
    @Binding var isPresented: Bool
    let messageContent: MessageContent
    let emojis: [String]
    let onSelectEmoji: (String) -> Void
    let onOpenEmojiKeyboard: () -> Void
    let menuActions: [MessageContextAction]

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 16) {
                Spacer()

                // Emoji picker
                EmojiPickerRow(
                    emojis: emojis,
                    onSelect: { emoji in
                        onSelectEmoji(emoji)
                        dismiss()
                    },
                    onOpenKeyboard: onOpenEmojiKeyboard
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -20)

                // Message snapshot
                messageContent
                    .scaleEffect(appeared ? 1.02 : 1)
                    .shadow(color: .black.opacity(0.2), radius: 20)

                // Context menu
                VStack(spacing: 0) {
                    ForEach(menuActions) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            action.action()
                            dismiss()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        if action.id != menuActions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            withAnimation(.spring(duration: 0.42)) {
                appeared = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.3)) {
            appeared = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            isPresented = false
        }
    }
}

/// Action for the message context menu
struct MessageContextAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }
}

#Preview {
    @Previewable @State var isPresented = true

    MessageContextOverlay(
        isPresented: $isPresented,
        messageContent: Text("Hello, this is a sample message that would be shown in the overlay.")
            .padding()
            .background(.blue.opacity(0.2), in: .rect(cornerRadius: 12)),
        emojis: ["👍", "👎", "❤️", "😂", "😮", "😢"],
        onSelectEmoji: { print("Selected: \($0)") },
        onOpenEmojiKeyboard: { print("Open keyboard") },
        menuActions: [
            MessageContextAction(L10n.Chats.Chats.Chats.Reactions.reply, systemImage: "arrowshape.turn.up.left") {},
            MessageContextAction(L10n.Chats.Chats.Chats.Reactions.copy, systemImage: "doc.on.doc") {},
            MessageContextAction(L10n.Chats.Chats.Chats.Reactions.delete, systemImage: "trash", isDestructive: true) {}
        ]
    )
}
