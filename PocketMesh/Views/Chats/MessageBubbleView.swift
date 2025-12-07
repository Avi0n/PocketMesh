import SwiftUI
import PocketMeshKit

/// iMessage-style message bubble
struct MessageBubbleView: View {
    let message: MessageDTO
    let contactName: String
    let deviceName: String
    let showTimestamp: Bool
    let onRetry: (() -> Void)?
    let onReply: ((String) -> Void)?
    let onDelete: (() -> Void)?

    init(
        message: MessageDTO,
        contactName: String,
        deviceName: String = "Me",
        showTimestamp: Bool = false,
        onRetry: (() -> Void)? = nil,
        onReply: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.message = message
        self.contactName = contactName
        self.deviceName = deviceName
        self.showTimestamp = showTimestamp
        self.onRetry = onRetry
        self.onReply = onReply
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
            // Timestamp (if shown)
            if showTimestamp {
                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Message bubble
            HStack(alignment: .bottom, spacing: 4) {
                if message.isOutgoing {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
                    // Message text
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleColor)
                        .foregroundStyle(textColor)
                        .clipShape(.rect(cornerRadius: 16))
                        .contextMenu {
                            // Reply button
                            Button {
                                let replyText = buildReplyText()
                                onReply?(replyText)
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }

                            // Copy button
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            // Details submenu
                            Menu {
                                // Time sent (always shown)
                                Text("Sent: \(message.date.formatted(date: .abbreviated, time: .shortened))")

                                // Time received (incoming only) - use createdAt as receive time
                                if !message.isOutgoing {
                                    Text("Received: \(message.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                }

                                // SNR (incoming only)
                                if !message.isOutgoing, let snrValue = message.snrValue {
                                    Text("SNR: \(snrFormatted(snrValue))")
                                }
                            } label: {
                                Label("Details", systemImage: "info.circle")
                            }

                            Divider()

                            // Delete button
                            Button(role: .destructive) {
                                onDelete?()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                    // Status row for outgoing messages
                    if message.isOutgoing {
                        statusRow
                    }
                }

                if !message.isOutgoing {
                    Spacer(minLength: 60)
                }
            }
        }
        .padding(.horizontal)
    }

    private var bubbleColor: Color {
        if message.isOutgoing {
            return message.hasFailed ? .red.opacity(0.8) : .blue
        } else {
            return Color(.systemGray5)
        }
    }

    private var textColor: Color {
        message.isOutgoing ? .white : .primary
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            // Retry button for failed messages
            if message.hasFailed, let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }

            // Status icon
            Image(systemName: ChatViewModel.statusIcon(for: message.status))
                .font(.caption2)
                .foregroundStyle(ChatViewModel.statusColor(for: message.status))

            // Status text
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 4)
    }

    private var statusText: String {
        switch message.status {
        case .pending:
            return "Pending"
        case .sending:
            return "Sending..."
        case .sent:
            return "Sent"
        case .delivered:
            if let rtt = message.roundTripTime {
                return "Delivered • \(rtt)ms"
            }
            return "Delivered"
        case .failed:
            return "Failed"
        case .read:
            return "Read"
        }
    }

    // MARK: - Context Menu Helpers

    private func buildReplyText() -> String {
        let senderName = message.isOutgoing ? deviceName : contactName
        let words = message.text.split(separator: " ").prefix(3)
        let preview = words.joined(separator: " ")
        let suffix = message.text.split(separator: " ").count > 3 ? "..." : ""
        return "> \(senderName): \(preview)\(suffix)"
    }

    private func snrFormatted(_ snr: Float) -> String {
        let quality: String
        switch snr {
        case 10...:
            quality = "Excellent"
        case 5..<10:
            quality = "Good"
        case 0..<5:
            quality = "Fair"
        case -10..<0:
            quality = "Poor"
        default:
            quality = "Very Poor"
        }
        return String(format: "%.1f dB (%@)", snr, quality)
    }
}


// MARK: - Message Date Header

struct MessageDateHeader: View {
    let date: Date

    var body: some View {
        Text(formattedDate)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(.rect(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

#Preview("Outgoing - Sent") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hello! How are you doing today?",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.sent.rawValue
    )
    return MessageBubbleView(
        message: MessageDTO(from: message),
        contactName: "Alice",
        deviceName: "My Device"
    )
}

#Preview("Outgoing - Delivered") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "This message was delivered successfully!",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        roundTripTime: 1234
    )
    return MessageBubbleView(
        message: MessageDTO(from: message),
        contactName: "Bob",
        deviceName: "My Device"
    )
}

#Preview("Outgoing - Failed") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "This message failed to send",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.failed.rawValue
    )
    return MessageBubbleView(
        message: MessageDTO(from: message),
        contactName: "Charlie",
        deviceName: "My Device",
        onRetry: { print("Retry tapped") }
    )
}

#Preview("Incoming") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hey there! Great to hear from you!",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue
    )
    return MessageBubbleView(
        message: MessageDTO(from: message),
        contactName: "Dana",
        deviceName: "My Device"
    )
}
