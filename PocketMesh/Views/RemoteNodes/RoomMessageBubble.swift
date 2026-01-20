import SwiftUI
import PocketMeshServices

private let outgoingBubbleColor = Color(red: 36/255, green: 99/255, blue: 235/255)

/// Message bubble for room server messages
struct RoomMessageBubble: View {
    let message: RoomMessageDTO
    let showTimestamp: Bool

    private var isFromSelf: Bool { message.isFromSelf }

    var body: some View {
        VStack(spacing: 4) {
            if showTimestamp {
                timestampView
            }

            HStack(alignment: .bottom, spacing: 8) {
                if isFromSelf {
                    Spacer(minLength: 60)
                }

                bubbleContent

                if !isFromSelf {
                    Spacer(minLength: 60)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Timestamp

    private var timestampView: some View {
        Text(message.date, format: .dateTime.month().day().hour().minute())
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    // MARK: - Bubble Content

    private var bubbleContent: some View {
        VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 4) {
            // Show author name for messages from others
            if !isFromSelf {
                Text(message.authorDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            Text(message.text)
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
    }

    private var bubbleBackground: some View {
        Group {
            if isFromSelf {
                outgoingBubbleColor
            } else {
                Color(.systemGray5)
            }
        }
    }

    private var textColor: Color {
        isFromSelf ? .white : .primary
    }
}

#Preview("Self Message") {
    RoomMessageBubble(
        message: RoomMessageDTO(
            sessionID: UUID(),
            authorKeyPrefix: Data(repeating: 0x42, count: 4),
            authorName: "Me",
            text: "Hello from me!",
            timestamp: UInt32(Date().timeIntervalSince1970),
            isFromSelf: true
        ),
        showTimestamp: true
    )
}

#Preview("Other Message") {
    RoomMessageBubble(
        message: RoomMessageDTO(
            sessionID: UUID(),
            authorKeyPrefix: Data(repeating: 0x55, count: 4),
            authorName: "Alice",
            text: "Hello from Alice!",
            timestamp: UInt32(Date().timeIntervalSince1970),
            isFromSelf: false
        ),
        showTimestamp: true
    )
}
