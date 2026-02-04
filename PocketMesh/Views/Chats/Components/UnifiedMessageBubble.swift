import SwiftUI
import PocketMeshServices

/// Layout constants for message bubbles
private enum MessageLayout {
    static let maxBubbleWidth: CGFloat = 280
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
            return L10n.Chats.Chats.Message.Sender.unknown
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
        return L10n.Chats.Chats.Message.Sender.unknown
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
    let showSenderName: Bool
    let onRetry: (() -> Void)?
    let onReaction: ((String) -> Void)?
    let onLongPress: (() -> Void)?

    // Preview state from display item (replaces @State)
    let previewState: PreviewLoadState
    let loadedPreview: LinkPreviewDataDTO?

    // Callbacks for preview lifecycle
    let onRequestPreviewFetch: (() -> Void)?
    let onManualPreviewFetch: (() -> Void)?

    @AppStorage("linkPreviewsEnabled") private var previewsEnabled = false
    @AppStorage("showIncomingPath") private var showIncomingPath = false
    @AppStorage("showIncomingHopCount") private var showIncomingHopCount = false
    @Environment(\.openURL) private var openURL
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var showingReactionDetails = false
    @State private var longPressTriggered = false

    init(
        message: MessageDTO,
        contactName: String,
        contactNodeName: String,
        deviceName: String = "Me",
        configuration: MessageBubbleConfiguration,
        showTimestamp: Bool = false,
        showDirectionGap: Bool = false,
        showSenderName: Bool = true,
        previewState: PreviewLoadState = .idle,
        loadedPreview: LinkPreviewDataDTO? = nil,
        onRetry: (() -> Void)? = nil,
        onReaction: ((String) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
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
        self.showSenderName = showSenderName
        self.previewState = previewState
        self.loadedPreview = loadedPreview
        self.onRetry = onRetry
        self.onReaction = onReaction
        self.onLongPress = onLongPress
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
                    // Sender name for incoming channel messages (hidden for continuation messages in a group)
                    if !message.isOutgoing && configuration.showSenderName && showSenderName {
                        Text(senderName)
                            .font(.footnote)
                            .bold()
                            .foregroundStyle(senderColor)
                    }

                    // Message bubble with text and optional routing footer
                    messageBubbleContent
                        .onLongPressGesture(minimumDuration: 0.3) {
                            longPressTriggered.toggle()
                            onLongPress?()
                        }
                        .sensoryFeedback(.impact(weight: .medium), trigger: longPressTriggered)

                    // Reaction badges (for messages with reactions)
                    if let summary = message.reactionSummary, !summary.isEmpty {
                        ReactionBadgesView(
                            summary: summary,
                            onTapReaction: { emoji in
                                onReaction?(emoji)
                            },
                            onLongPress: {
                                showingReactionDetails = true
                            }
                        )
                        .offset(y: -6)
                        .padding(.bottom, -6)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityMessageLabel)

                if !message.isOutgoing {
                    Spacer(minLength: 60)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, showDirectionGap ? 12 : (showSenderName ? 8 : 2))
        .padding(.bottom, message.isOutgoing ? 4 : 2)
        .onAppear {
            // Request preview fetch when cell becomes visible
            // ViewModel handles deduplication and cancellation
            if previewState == .idle && detectedURL != nil && message.linkPreviewURL == nil {
                onRequestPreviewFetch?()
            }
        }
        .sheet(isPresented: $showingReactionDetails) {
            ReactionDetailsSheet(messageID: message.id)
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

    // MARK: - Message Bubble Content

    private var messageBubbleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            MessageText(message.text, baseColor: textColor, currentUserName: deviceName)

            if !message.isOutgoing {
                if showIncomingPath {
                    pathFooter
                }
                if showIncomingHopCount && !isDirect {
                    hopCountFooter
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleColor)
        .clipShape(.rect(cornerRadius: 16))
        .frame(maxWidth: MessageLayout.maxBubbleWidth, alignment: message.isOutgoing ? .trailing : .leading)
    }

    // MARK: - Computed Properties

    private var senderName: String {
        configuration.senderNameResolver?(message) ?? "Unknown"
    }

    private var senderColor: Color {
        AppColors.NameColor.color(for: senderName, highContrast: colorSchemeContrast == .increased)
    }

    private var detectedURL: URL? {
        LinkPreviewService.extractFirstURL(from: message.text)
    }

    private var bubbleColor: Color {
        if message.isOutgoing {
            return message.hasFailed ? AppColors.Message.outgoingBubbleFailed : AppColors.Message.outgoingBubble
        } else {
            return AppColors.Message.incomingBubble
        }
    }

    private var textColor: Color {
        message.isOutgoing ? .white : .primary
    }

    private var isDirect: Bool {
        message.pathLength == 0 || message.pathLength == 0xFF
    }

    private var accessibilityMessageLabel: String {
        var label = ""
        // Always include sender name for screen readers, even when visually hidden
        if !message.isOutgoing && configuration.showSenderName {
            label = "\(senderName): "
        }
        label += message.text
        if message.isOutgoing {
            label += ", \(statusText)"
        }
        return label
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
                        Text(L10n.Chats.Chats.Message.Status.retry)
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
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

    // MARK: - Routing Info Footer Views

    private var pathFooter: some View {
        let formattedPath = MessagePathFormatter.format(message)
        return HStack(spacing: 4) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            Text(formattedPath)
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Chats.Chats.Message.Path.accessibilityLabel(formattedPath))
    }

    private var hopCountFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.bounce.right")
            Text("\(message.pathLength)")
        }
        .font(.caption2)  // Not monospaced - only hex paths need alignment
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Chats.Chats.Message.HopCount.accessibilityLabel(Int(message.pathLength)))
    }

    private var statusText: String {
        switch message.status {
        case .pending:
            return L10n.Chats.Chats.Message.Status.sending
        case .sending:
            return L10n.Chats.Chats.Message.Status.sending
        case .sent:
            // Build status parts: repeats, send count, sent
            var parts: [String] = []
            if message.heardRepeats > 0 {
                let repeatWord = message.heardRepeats == 1
                    ? L10n.Chats.Chats.Message.Repeat.singular
                    : L10n.Chats.Chats.Message.Repeat.plural
                parts.append("\(message.heardRepeats) \(repeatWord)")
            }
            if message.sendCount > 1 {
                parts.append(L10n.Chats.Chats.Message.Status.sentMultiple(message.sendCount))
            } else {
                parts.append(L10n.Chats.Chats.Message.Status.sent)
            }
            return parts.joined(separator: " • ")
        case .delivered:
            if message.heardRepeats > 0 {
                let repeatWord = message.heardRepeats == 1
                    ? L10n.Chats.Chats.Message.Repeat.singular
                    : L10n.Chats.Chats.Message.Repeat.plural
                let repeatText = "\(message.heardRepeats) \(repeatWord)"
                return "\(repeatText) • \(L10n.Chats.Chats.Message.Status.delivered)"
            }
            return L10n.Chats.Chats.Message.Status.delivered
        case .failed:
            return L10n.Chats.Chats.Message.Status.failed
        case .retrying:
            // Show attempt count: "Retrying 1/4" (1-indexed for user display)
            let displayAttempt = message.retryAttempt + 1
            let maxAttempts = message.maxRetryAttempts
            if maxAttempts > 0 {
                return L10n.Chats.Chats.Message.Status.retryingAttempt(displayAttempt, maxAttempts)
            }
            return L10n.Chats.Chats.Message.Status.retrying
        }
    }

    // MARK: - Helpers

    private func snrFormatted(_ snr: Double) -> String {
        let quality: String
        switch snr {
        case 10...:
            quality = L10n.Chats.Chats.Signal.excellent
        case 5..<10:
            quality = L10n.Chats.Chats.Signal.good
        case 0..<5:
            quality = L10n.Chats.Chats.Signal.fair
        case -10..<0:
            quality = L10n.Chats.Chats.Signal.poor
        default:
            quality = L10n.Chats.Chats.Signal.veryPoor
        }
        return "\(snr.formatted(.number.precision(.fractionLength(1)))) dB (\(quality))"
    }

    private func hopCountFormatted(_ pathLength: UInt8) -> String {
        switch pathLength {
        case 0, 0xFF:  // 0 = zero hops, 0xFF = direct/unknown (no route tracking)
            return L10n.Chats.Chats.Message.Hops.direct
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

#Preview("Incoming - Direct Path") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "This came directly!",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        pathLength: 0
    )
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Alice",
        contactNodeName: "Alice",
        configuration: .directMessage
    )
}

#Preview("Incoming - 3 Hop Path") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Routed through 3 nodes",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        pathLength: 3
    )
    message.pathNodes = Data([0xA3, 0x7F, 0x42])
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Bob",
        contactNodeName: "Bob",
        configuration: .directMessage
    )
}

#Preview("Incoming - 6 Hop Truncated") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Long path message",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        pathLength: 6
    )
    message.pathNodes = Data([0xA3, 0x7F, 0x42, 0xB2, 0xC1, 0xD4])
    return UnifiedMessageBubble(
        message: MessageDTO(from: message),
        contactName: "Charlie",
        contactNodeName: "Charlie",
        configuration: .directMessage
    )
}
