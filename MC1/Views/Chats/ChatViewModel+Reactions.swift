import Foundation
import PocketMeshServices

extension ChatViewModel {

    // MARK: - Reactions

    /// Send a reaction emoji to a message (channel or DM)
    func sendReaction(emoji: String, to message: MessageDTO) async {
        guard let reactionService = appState?.services?.reactionService,
              let messageService,
              let dataStore else {
            return
        }

        // Prevent duplicate sends from rapid taps
        let reactionKey = "\(message.id)-\(emoji)"
        guard !inFlightReactions.contains(reactionKey) else {
            logger.debug("Reaction \(emoji) already in flight for message \(message.id), ignoring")
            return
        }
        inFlightReactions.insert(reactionKey)
        defer { inFlightReactions.remove(reactionKey) }

        let localNodeName = appState?.connectedDevice?.nodeName ?? "Me"

        // Check if user already reacted with this emoji
        if let alreadyReacted = try? await dataStore.reactionExists(
            messageID: message.id,
            senderName: localNodeName,
            emoji: emoji
        ), alreadyReacted {
            logger.debug("User already reacted with \(emoji), ignoring")
            return
        }

        // Handle channel vs DM
        if let channelIndex = message.channelIndex {
            await sendChannelReaction(
                emoji: emoji,
                to: message,
                channelIndex: channelIndex,
                localNodeName: localNodeName
            )
        } else if let contactID = message.contactID {
            await sendDMReaction(
                emoji: emoji,
                to: message,
                contactID: contactID,
                localNodeName: localNodeName
            )
        }
    }

    private func sendChannelReaction(
        emoji: String,
        to message: MessageDTO,
        channelIndex: UInt8,
        localNodeName: String
    ) async {
        guard let reactionService = appState?.services?.reactionService,
              let messageService,
              let dataStore else { return }

        // Determine target sender name
        let targetSenderName: String
        if message.isOutgoing {
            targetSenderName = localNodeName
        } else {
            guard let senderName = message.senderNodeName else { return }
            targetSenderName = senderName
        }

        let reactionText = reactionService.buildReactionText(
            emoji: emoji,
            targetSender: targetSenderName,
            targetText: message.text,
            targetTimestamp: message.reactionTimestamp
        )

        do {
            _ = try await messageService.sendChannelMessage(
                text: reactionText,
                channelIndex: channelIndex,
                deviceID: message.deviceID
            )

            recentEmojisStore.recordUsage(emoji)

            // Optimistic local update
            let messageHash = ReactionParser.generateMessageHash(
                text: message.text,
                timestamp: message.reactionTimestamp
            )
            let reactionDTO = ReactionDTO(
                messageID: message.id,
                emoji: emoji,
                senderName: localNodeName,
                messageHash: messageHash,
                rawText: reactionText,
                channelIndex: channelIndex,
                deviceID: message.deviceID
            )
            if let result = await reactionService.persistReactionAndUpdateSummary(
                reactionDTO,
                using: dataStore
            ) {
                updateReactionSummary(for: result.messageID, summary: result.summary)
            }
        } catch {
            logger.error("Failed to send channel reaction: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func sendDMReaction(
        emoji: String,
        to message: MessageDTO,
        contactID: UUID,
        localNodeName: String
    ) async {
        guard let reactionService = appState?.services?.reactionService,
              let messageService,
              let dataStore else { return }

        // Fetch the contact for sending
        guard let contact = try? await dataStore.fetchContact(id: contactID) else {
            logger.error("Failed to fetch contact for DM reaction")
            return
        }

        let reactionText = reactionService.buildDMReactionText(
            emoji: emoji,
            targetText: message.text,
            targetTimestamp: message.reactionTimestamp
        )
        logger.debug("[DM-REACTION-SEND] Building reaction: timestamp=\(message.timestamp), senderTimestamp=\(message.senderTimestamp ?? 0), reactionTimestamp=\(message.reactionTimestamp), text=\(message.text.prefix(30))")

        do {
            // Send as DM to the contact
            _ = try await messageService.sendDirectMessage(
                text: reactionText,
                to: contact
            )

            recentEmojisStore.recordUsage(emoji)

            // Optimistic local update
            let messageHash = ReactionParser.generateMessageHash(
                text: message.text,
                timestamp: message.reactionTimestamp
            )
            let reactionDTO = ReactionDTO(
                messageID: message.id,
                emoji: emoji,
                senderName: localNodeName,
                messageHash: messageHash,
                rawText: reactionText,
                contactID: contactID,
                deviceID: message.deviceID
            )
            if let result = await reactionService.persistReactionAndUpdateSummary(
                reactionDTO,
                using: dataStore
            ) {
                updateReactionSummary(for: result.messageID, summary: result.summary)
            }
        } catch {
            logger.error("Failed to send DM reaction: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reaction Filtering

    /// Filter out outgoing reaction messages unless they failed to send.
    /// Reaction messages are hidden from the UI to avoid clutter since they're displayed as badges.
    /// - Parameters:
    ///   - messages: The messages to filter
    ///   - isDM: Whether these are DM messages (uses parseDM) or channel messages (uses parse)
    /// - Returns: Filtered messages with successful outgoing reactions removed
    func filterOutgoingReactionMessages(_ messages: [MessageDTO], isDM: Bool) -> [MessageDTO] {
        messages.filter { message in
            guard message.direction == .outgoing else { return true }

            let isReaction = isDM
                ? ReactionParser.parseDM(message.text) != nil
                : ReactionParser.parse(message.text) != nil

            guard isReaction else { return true }

            return message.status == .failed
        }
    }

    // MARK: - Reaction Updates

    /// Update reaction summary for a specific message inline (O(1) update)
    func updateReactionSummary(for messageID: UUID, summary: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let existing = messagesByID[messageID] else {
            return
        }

        // Create updated MessageDTO with new reaction summary
        let updated = MessageDTO(
            id: existing.id,
            deviceID: existing.deviceID,
            contactID: existing.contactID,
            channelIndex: existing.channelIndex,
            text: existing.text,
            timestamp: existing.timestamp,
            createdAt: existing.createdAt,
            direction: existing.direction,
            status: existing.status,
            textType: existing.textType,
            ackCode: existing.ackCode,
            pathLength: existing.pathLength,
            snr: existing.snr,
            pathNodes: existing.pathNodes,
            senderKeyPrefix: existing.senderKeyPrefix,
            senderNodeName: existing.senderNodeName,
            isRead: existing.isRead,
            replyToID: existing.replyToID,
            roundTripTime: existing.roundTripTime,
            heardRepeats: existing.heardRepeats,
            sendCount: existing.sendCount,
            retryAttempt: existing.retryAttempt,
            maxRetryAttempts: existing.maxRetryAttempts,
            deduplicationKey: existing.deduplicationKey,
            linkPreviewURL: existing.linkPreviewURL,
            linkPreviewTitle: existing.linkPreviewTitle,
            linkPreviewImageData: existing.linkPreviewImageData,
            linkPreviewIconData: existing.linkPreviewIconData,
            linkPreviewFetched: existing.linkPreviewFetched,
            containsSelfMention: existing.containsSelfMention,
            mentionSeen: existing.mentionSeen,
            timestampCorrected: existing.timestampCorrected,
            reactionSummary: summary
        )

        messages[index] = updated
        messagesByID[messageID] = updated
        rebuildDisplayItem(for: messageID)
    }
}
