import SwiftUI
import PocketMeshServices

/// Layout constants for message bubbles
private enum MessageLayout {
    static let maxBubbleWidth: CGFloat = 280
    static let outgoingBubbleColor = Color(red: 36/255, green: 99/255, blue: 235/255)
}

/// Configuration for message bubble appearance and behavior
struct MessageBubbleConfiguration: Sendable {
    let accentColor: Color
    let showSenderName: Bool
    let isChannel: Bool
    let senderNameResolver: (@Sendable (MessageDTO) -> String)?

    static let directMessage = MessageBubbleConfiguration(
        accentColor: .blue,
        showSenderName: false,
        isChannel: false,
        senderNameResolver: nil
    )

    static func channel(isPublic: Bool, contacts: [ContactDTO]) -> MessageBubbleConfiguration {
        MessageBubbleConfiguration(
            accentColor: isPublic ? .green : .blue,
            showSenderName: true,
            isChannel: true,
            senderNameResolver: { message in
                resolveSenderName(for: message, contacts: contacts)
            }
        )
    }

    private static func resolveSenderName(for message: MessageDTO, contacts: [ContactDTO]) -> String {
        // First, try parsed sender name from channel message
        if let senderName = message.senderNodeName, !senderName.isEmpty {
            return senderName
        }

        // Fallback: key prefix lookup
        guard let prefix = message.senderKeyPrefix else {
            return "Unknown"
        }

        // Try to find matching contact
        if let contact = contacts.first(where: { contact in
            contact.publicKey.count >= prefix.count &&
            Array(contact.publicKey.prefix(prefix.count)) == Array(prefix)
        }) {
            return contact.displayName
        }

        // Fallback to hex representation
        if prefix.count >= 2 {
            return prefix.prefix(2).map { String(format: "%02X", $0) }.joined()
        }
        return "Unknown"
    }
}

/// Unified message bubble for both direct and channel messages
struct UnifiedMessageBubble: View {
    let message: MessageDTO
    let contactName: String
    let contactNodeName: String
    let deviceName: String
    let configuration: MessageBubbleConfiguration
    let showTimestamp: Bool
    let showDirectionGap: Bool
    let onRetry: (() -> Void)?
    let onReply: ((String) -> Void)?
    let onDelete: (() -> Void)?
    let onShowRepeatDetails: ((MessageDTO) -> Void)?

    // Preview state from display item (replaces @State)
    let previewState: PreviewLoadState
    let loadedPreview: LinkPreviewDataDTO?

    // Callbacks for preview lifecycle
    let onRequestPreviewFetch: (() -> Void)?
    let onManualPreviewFetch: (() -> Void)?

    @AppStorage("linkPreviewsEnabled") private var previewsEnabled = false
    @Environment(\.openURL) private var openURL

    init(
        message: MessageDTO,
        contactName: String,
        contactNodeName: String,
        deviceName: String = "Me",
        configuration: MessageBubbleConfiguration,
        showTimestamp: Bool = false,
        showDirectionGap: Bool = false,
        previewState: PreviewLoadState = .idle,
        loadedPreview: LinkPreviewDataDTO? = nil,
        onRetry: (() -> Void)? = nil,
        onReply: ((String) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onShowRepeatDetails: ((MessageDTO) -> Void)? = nil,
        onRequestPreviewFetch: (() -> Void)? = nil,
        onManualPreviewFetch: (() -> Void)? = nil
    ) {
        self.message = message
        self.contactName = contactName
        self.contactNodeName = contactNodeName
        self.deviceName = deviceName
        self.configuration = configuration
        self.showTimestamp = showTimestamp
        self.showDirectionGap = showDirectionGap
        self.previewState = previewState
        self.loadedPreview = loadedPreview
        self.onRetry = onRetry
        self.onReply = onReply
        self.onDelete = onDelete
        self.onShowRepeatDetails = onShowRepeatDetails
        self.onRequestPreviewFetch = onRequestPreviewFetch
        self.onManualPreviewFetch = onManualPreviewFetch
    }

    var body: some View {
        VStack(spacing: 2) {
            // Centered timestamp (iMessage-style)
            if showTimestamp {
                MessageTimestampView(date: message.date)
            }

            // Bubble content (aligned based on direction)
            HStack(alignment: .bottom, spacing: 4) {
                if message.isOutgoing {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
                    // Sender name for incoming channel messages
                    if !message.isOutgoing && configuration.showSenderName {
                        Text(senderName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Message text with context menu
                    MessageText(message.text, baseColor: textColor, currentUserName: deviceName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleColor)
                        .clipShape(.rect(cornerRadius: 16))
                        .frame(maxWidth: MessageLayout.maxBubbleWidth, alignment: message.isOutgoing ? .trailing : .leading)
                        .contextMenu {
                            contextMenuContent
                        }

                    // Link preview (if applicable)
                    if previewsEnabled {
                        linkPreviewContent
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
        .padding(.top, showDirectionGap ? 12 : 2)
        .padding(.bottom, message.isOutgoing ? 4 : 2)
        .onAppear {
            // Request preview fetch when cell becomes visible
            // ViewModel handles deduplication and cancellation
            if previewState == .idle && detectedURL != nil && message.linkPreviewURL == nil {
                onRequestPreviewFetch?()
            }
        }
    }

    // MARK: - Link Preview Content

    @ViewBuilder
    private var linkPreviewContent: some View {
        switch previewState {
        case .loaded:
            if let preview = loadedPreview,
               let url = URL(string: preview.url) {
                LinkPreviewCard(
                    url: url,
                    title: preview.title,
                    imageData: preview.imageData,
                    iconData: preview.iconData,
                    onTap: { openURL(url) }
                )
                .frame(maxWidth: MessageLayout.maxBubbleWidth)
            }

        case .loading:
            if let url = detectedURL {
                LinkPreviewLoadingCard(url: url)
                    .frame(maxWidth: MessageLayout.maxBubbleWidth)
            }

        case .noPreview:
            EmptyView()

        case .disabled:
            if let url = detectedURL {
                TapToLoadPreview(
                    url: url,
                    isLoading: false,
                    onTap: {
                        onManualPreviewFetch?()
                    }
                )
                .frame(maxWidth: MessageLayout.maxBubbleWidth)
            }

        case .idle:
            // Check for legacy message data
            if let urlString = message.linkPreviewURL,
               let url = URL(string: urlString) {
                LinkPreviewCard(
                    url: url,
                    title: message.linkPreviewTitle,
                    imageData: message.linkPreviewImageData,
                    iconData: message.linkPreviewIconData,
                    onTap: { openURL(url) }
                )
                .frame(maxWidth: MessageLayout.maxBubbleWidth)
            } else if let url = detectedURL {
                // URL detected, waiting for fetch - show loading
                LinkPreviewLoadingCard(url: url)
                    .frame(maxWidth: MessageLayout.maxBubbleWidth)
            }
        }
    }

    // MARK: - Computed Properties

    private var senderName: String {
        configuration.senderNameResolver?(message) ?? "Unknown"
    }

    private var detectedURL: URL? {
        LinkPreviewService.extractFirstURL(from: message.text)
    }

    private var bubbleColor: Color {
        if message.isOutgoing {
            return message.hasFailed ? .red.opacity(0.8) : MessageLayout.outgoingBubbleColor
        } else {
            return Color(.systemGray5)
        }
    }

    private var textColor: Color {
        message.isOutgoing ? .white : .primary
    }

    // MARK: - Context Menu
    //
    // HIG: "Hide unavailable menu items, don't dim them"
    // Only show actions that have handlers provided

    @ViewBuilder
    private var contextMenuContent: some View {
        // Only show Reply for incoming messages (not outgoing)
        if let onReply, !message.isOutgoing {
            Button {
                let replyText = buildReplyText()
                onReply(replyText)
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }

        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        // Repeat Details button (only for outgoing channel messages with repeats)
        if message.isOutgoing, message.channelIndex != nil, message.heardRepeats > 0, let onShowRepeatDetails {
            Button {
                onShowRepeatDetails(message)
            } label: {
                Label("Repeat Details", systemImage: "arrow.triangle.branch")
            }
        }

        // Outgoing message details
        if message.isOutgoing {
            if (message.status == .sent || message.status == .delivered) && message.heardRepeats > 0 {
                Text("Heard: \(message.heardRepeats) repeat\(message.heardRepeats == 1 ? "" : "s")")
            }

            Text("Sent: \(message.date.formatted(date: .abbreviated, time: .shortened))")

            if let rtt = message.roundTripTime {
                Text("Round trip: \(rtt)ms")
            }
        }

        // Incoming message details in submenu (more fields)
        if !message.isOutgoing {
            Menu {
                Text("Sent: \(message.date.formatted(date: .abbreviated, time: .shortened))")
                Text("Received: \(message.createdAt.formatted(date: .abbreviated, time: .shortened))")

                if let snr = message.snr {
                    Text("SNR: \(snrFormatted(snr))")
                }

                Text("Hops: \(hopCountFormatted(message.pathLength))")
            } label: {
                Label("Details", systemImage: "info.circle")
            }
        }

        // Only show Delete if handler is provided
        if let onDelete {
            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 4) {
            // Only show retry button for failed messages (not retrying)
            if message.status == .failed, let onRetry {
                Button {
                    onRetry()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            // Show spinner for retrying status
            if message.status == .retrying {
                ProgressView()
                    .controlSize(.mini)
            }

            // Only show icon for failed status
            if message.status == .failed {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 4)
    }

    private var statusText: String {
        switch message.status {
        case .pending:
            return "Sending..."
        case .sending:
            return "Sending..."
        case .sent:
            // Channel messages stay at .sent (no ACK), so show repeat count if available
            if message.heardRepeats > 0 {
                let repeatText = message.heardRepeats == 1 ? "1 repeat" : "\(message.heardRepeats) repeats"
                return "\(repeatText) • Sent"
            }
            return "Sent"
        case .delivered:
            if message.heardRepeats > 0 {
                let repeatText = message.heardRepeats == 1 ? "1 repeat" : "\(message.heardRepeats) repeats"
                return "\(repeatText) • Delivered"
            }
            return "Delivered"
        case .failed:
            return "Failed"
        case .retrying:
            return "Retrying..."
        }
    }

    // MARK: - Helpers

    /// Builds reply preview text with mention and proper Unicode/locale handling
    ///
    /// Format: @[nodeContactName]"preview.."\n
    ///
    /// Per CLAUDE.md: Use localizedStandard APIs for text filtering.
    /// This handles:
    /// - Unicode word boundaries (emoji, CJK characters)
    /// - RTL languages (Arabic, Hebrew)
    /// - Messages without spaces (Asian languages)
    private func buildReplyText() -> String {
        // Determine the mesh network name for the mention
        let mentionName: String
        if configuration.showSenderName {
            // Channel message - use sender's node name (from message)
            mentionName = message.senderNodeName ?? senderName
        } else {
            // Direct message - use contact's mesh network name
            mentionName = contactNodeName
        }

        // Use locale-aware word enumeration for proper Unicode handling
        // Count up to 3 words to know if there's more than 2
        var wordCount = 0
        var secondWordEndIndex = message.text.startIndex
        message.text.enumerateSubstrings(
            in: message.text.startIndex...,
            options: [.byWords, .localized]
        ) { _, range, _, stop in
            wordCount += 1
            if wordCount <= 2 {
                secondWordEndIndex = range.upperBound
            }
            if wordCount >= 3 {
                stop = true
            }
        }

        // Build preview
        let preview: String
        let hasMore: Bool
        if wordCount > 0 {
            preview = String(message.text[..<secondWordEndIndex]).trimmingCharacters(in: .whitespaces)
            // Only show ".." if message has more than 2 words
            hasMore = wordCount > 2
        } else {
            // Fallback for messages without word boundaries (pure emoji, etc.)
            // Take first ~20 characters
            let maxChars = min(20, message.text.count)
            let index = message.text.index(message.text.startIndex, offsetBy: maxChars)
            preview = String(message.text[..<index])
            hasMore = maxChars < message.text.count
        }

        let suffix = hasMore ? ".." : ""
        let mention = MentionUtilities.createMention(for: mentionName)
        return "\(mention)\"\(preview)\(suffix)\"\n"
    }

    private func snrFormatted(_ snr: Double) -> String {
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
        return "\(snr.formatted(.number.precision(.fractionLength(1)))) dB (\(quality))"
    }

    private func hopCountFormatted(_ pathLength: UInt8) -> String {
        switch pathLength {
        case 0, 0xFF:  // 0 = zero hops, 0xFF = direct/unknown (no route tracking)
            return "Direct"
        default:
            return "\(pathLength)"
        }
    }
}

// MARK: - Previews

#Preview("Direct - Outgoing Sent") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hello! How are you doing today?",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.sent.rawValue
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Alice",
        contactNodeName: "Alice",
        deviceName: "My Device",
        configuration: .directMessage
    )
}

#Preview("Direct - Outgoing Delivered") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "This message was delivered successfully!",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        roundTripTime: 1234,
        heardRepeats: 2
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Bob",
        contactNodeName: "Bob",
        deviceName: "My Device",
        configuration: .directMessage
    )
}

#Preview("Direct - Outgoing Failed") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "This message failed to send",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.failed.rawValue
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Charlie",
        contactNodeName: "Charlie",
        deviceName: "My Device",
        configuration: .directMessage,
        onRetry: { }
    )
}

#Preview("Channel - Public Incoming") {
    let message = Message(
        deviceID: UUID(),
        channelIndex: 1,
        text: "Hello from the public channel!",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        senderNodeName: "RemoteNode"
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "General",
        contactNodeName: "General",
        deviceName: "My Device",
        configuration: .channel(isPublic: true, contacts: [])
    )
}

#Preview("Channel - Private Outgoing") {
    let message = Message(
        deviceID: UUID(),
        channelIndex: 2,
        text: "Private channel message",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.sent.rawValue
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Private Group",
        contactNodeName: "Private Group",
        deviceName: "My Device",
        configuration: .channel(isPublic: false, contacts: [])
    )
}
