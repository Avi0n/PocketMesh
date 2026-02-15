import CoreLocation
import OSLog
import PocketMeshServices
import SwiftUI

/// Actions available from the message actions sheet
enum MessageAction: Equatable {
    case react(String)
    case reply
    case copy
    case sendAgain
    case blockSender
    case delete
}

/// Sheet-based message actions UI (ElementX style)
/// Replaces native context menus for unified experience across channel and direct messages
struct MessageActionsSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let message: MessageDTO
    let senderName: String
    let recentEmojis: [String]
    let onAction: (MessageAction) -> Void

    private var availability: MessageActionAvailability {
        MessageActionAvailability(message: message)
    }

    @State private var longPressHapticTrigger = 0
    @State private var showEmojiPicker = false
    @State private var isDetailExpanded = false
    @State private var repeats: [MessageRepeatDTO]?
    @State private var contacts: [ContactDTO] = []
    @State private var pathViewModel = MessagePathViewModel()

    var body: some View {
        VStack(spacing: 0) {
            messagePreviewHeader

            Divider()

            if !dynamicTypeSize.isAccessibilitySize {
                emojiSection
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if dynamicTypeSize.isAccessibilitySize {
                            emojiSection
                            Divider()
                        }
                        actionsSection
                        detailsSection
                        blockSection
                        deleteSection
                    }
                }
                .onChange(of: isDetailExpanded) { _, expanded in
                    if expanded {
                        withAnimation {
                            proxy.scrollTo("expandedContent", anchor: .top)
                        }
                    }
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .onAppear {
            longPressHapticTrigger += 1
        }
        .sensoryFeedback(.impact(flexibility: .solid), trigger: longPressHapticTrigger)
        .task {
            guard let services = appState.services else { return }
            if availability.canShowRepeatDetails {
                do {
                    contacts = try await services.dataStore.fetchContacts(deviceID: message.deviceID)
                } catch {
                    contacts = []
                }
                repeats = await services.heardRepeatsService.refreshRepeats(for: message.id)
            } else if availability.canViewPath {
                await pathViewModel.loadContacts(services: services, deviceID: message.deviceID)
            }
        }
    }

    // MARK: - Header

    private var messagePreviewHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(senderName)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    messageTimestamp
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(senderName)
                        .font(.subheadline)
                        .bold()
                    messageTimestamp
                }
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .padding()
    }

    private var messageTimestamp: some View {
        Text(message.isOutgoing ? message.date : message.createdAt,
             format: .dateTime.hour().minute())
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Emoji Section

    private var emojiSection: some View {
        EmojiPickerRow(
            emojis: recentEmojis,
            onSelect: { emoji in
                onAction(.react(emoji))
                dismiss()
            },
            onOpenKeyboard: {
                showEmojiPicker = true
            }
        )
        .padding()
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet { emoji in
                onAction(.react(emoji))
                dismiss()
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        if availability.canReply {
            actionButton(
                L10n.Chats.Chats.Message.Action.reply,
                icon: "arrowshape.turn.up.left",
                action: .reply
            )
        }

        actionButton(
            L10n.Chats.Chats.Message.Action.copy,
            icon: "doc.on.doc",
            action: .copy
        )

        if availability.canSendAgain {
            actionButton(
                L10n.Chats.Chats.Message.Action.sendAgain,
                icon: "arrow.uturn.forward",
                action: .sendAgain
            )
        }
    }

    @ViewBuilder
    private var blockSection: some View {
        if availability.canBlockSender {
            Divider()
                .padding(.vertical, 8)
            actionButton(
                L10n.Chats.Chats.Message.Action.blockSender,
                icon: "hand.raised",
                action: .blockSender,
                isDestructive: true
            )
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if availability.canDelete {
            Divider()
                .padding(.vertical, 8)
            actionButton(
                L10n.Chats.Chats.Message.Action.delete,
                icon: "trash",
                action: .delete,
                isDestructive: true
            )
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        action: MessageAction,
        isDestructive: Bool = false
    ) -> some View {
        Button {
            onAction(action)
            dismiss()
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
            }
            .padding()
            .contentShape(.rect)
        }
        .foregroundStyle(isDestructive ? .red : .primary)
    }

    // MARK: - Details Section

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if availability.canShowRepeatDetails || availability.canViewPath {
                expandableDetailRow
            }

            Text(L10n.Chats.Chats.Message.Action.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

            if message.isOutgoing {
                outgoingDetailsRows
            } else {
                incomingDetailsRows
            }
        }
    }

    private var expandableDetailRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    isDetailExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(
                        availability.canShowRepeatDetails
                            ? L10n.Chats.Chats.Message.Action.repeatDetails
                            : L10n.Chats.Chats.Message.Action.viewPath,
                        systemImage: availability.canShowRepeatDetails
                            ? "arrow.triangle.branch"
                            : "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isDetailExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
                .contentShape(.rect)
            }
            .foregroundStyle(.primary)
            .accessibilityValue(isDetailExpanded ? "expanded" : "collapsed")

            if isDetailExpanded {
                Divider()
                    .padding(.horizontal)
                expandedContent
                    .padding(.horizontal)
                    .padding(.bottom)
                    .id("expandedContent")
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if availability.canShowRepeatDetails {
            RepeatDetailsContent(
                repeats: repeats,
                contacts: contacts,
                userLocation: appState.locationService.currentLocation
            )
        } else if availability.canViewPath {
            MessagePathContent(
                message: message,
                viewModel: pathViewModel,
                receiverName: appState.connectedDevice?.nodeName ?? L10n.Chats.Chats.Path.Receiver.you,
                userLocation: appState.locationService.currentLocation
            )
        }
    }

    @ViewBuilder
    private var outgoingDetailsRows: some View {
        infoRow(L10n.Chats.Chats.Message.Info.sent(
            message.date.formatted(date: .abbreviated, time: .shortened)))

        if let rtt = message.roundTripTime {
            infoRow(L10n.Chats.Chats.Message.Info.roundTrip(Int(rtt)))
        }

        if message.heardRepeats > 0 {
            let word = message.heardRepeats == 1
                ? L10n.Chats.Chats.Message.Repeat.singular
                : L10n.Chats.Chats.Message.Repeat.plural
            infoRow(L10n.Chats.Chats.Message.Info.heardRepeats(message.heardRepeats, word))
        }
    }

    @ViewBuilder
    private var incomingDetailsRows: some View {
        infoRow(L10n.Chats.Chats.Message.Info.hops(hopCountFormatted(message.pathLength)),
                icon: "arrowshape.bounce.right")

        let sentText = L10n.Chats.Chats.Message.Info.sent(
            message.date.formatted(date: .abbreviated, time: .shortened))
        let adjusted = message.timestampCorrected ? " " + L10n.Chats.Chats.Message.Info.adjusted : ""
        infoRow(sentText + adjusted)

        infoRow(L10n.Chats.Chats.Message.Info.received(
            message.createdAt.formatted(date: .abbreviated, time: .shortened)))

        if let snr = message.snr {
            infoRow(L10n.Chats.Chats.Message.Info.snr(snrFormatted(snr)))
        }
    }

    private func infoRow(_ text: String, icon: String? = nil) -> some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
            Text(text)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
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
        case 0, 0xFF:
            return L10n.Chats.Chats.Message.Hops.direct
        default:
            return "\(pathLength)"
        }
    }
}

#Preview("Outgoing Message") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hello world!",
        directionRawValue: MessageDirection.outgoing.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue
    )
    message.roundTripTime = 234
    message.heardRepeats = 2
    return MessageActionsSheet(
        message: MessageDTO(from: message),
        senderName: "My Device",
        recentEmojis: RecentEmojisStore.defaultEmojis,
        onAction: { print("Action: \($0)") }
    )
}

#Preview("Incoming Message") {
    let message = Message(
        deviceID: UUID(),
        contactID: UUID(),
        text: "Hey, can you meet me at the coffee shop downtown later today? I have something important to discuss.",
        directionRawValue: MessageDirection.incoming.rawValue,
        statusRawValue: MessageStatus.delivered.rawValue,
        pathLength: 2
    )
    message.pathNodes = Data([0xA3, 0x7F])
    message.snr = 8.5
    return MessageActionsSheet(
        message: MessageDTO(from: message),
        senderName: "Alice",
        recentEmojis: RecentEmojisStore.defaultEmojis,
        onAction: { print("Action: \($0)") }
    )
}
