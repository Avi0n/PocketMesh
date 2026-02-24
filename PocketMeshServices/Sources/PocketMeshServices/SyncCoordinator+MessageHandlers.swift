// SyncCoordinator+MessageHandlers.swift
import Foundation

// MARK: - Message & Discovery Handler Wiring

extension SyncCoordinator {

    // MARK: - Message Handler Wiring

    /// Persists a reaction if it doesn't already exist, notifying the UI on success.
    ///
    /// Deduplicates the check-exists → create → persist → notify pattern used across
    /// DM and channel reaction handlers.
    ///
    /// - Returns: `true` if the reaction was new and saved
    @discardableResult
    private func persistReactionIfNew(
        _ reactionDTO: ReactionDTO,
        services: ServiceContainer
    ) async -> Bool {
        let exists = try? await services.dataStore.reactionExists(
            messageID: reactionDTO.messageID,
            senderName: reactionDTO.senderName,
            emoji: reactionDTO.emoji
        )

        guard exists != true else { return false }

        if let result = await services.reactionService.persistReactionAndUpdateSummary(
            reactionDTO,
            using: services.dataStore
        ) {
            await onReactionReceived?(result.messageID, result.summary)
        }

        return true
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func wireMessageHandlers(services: ServiceContainer, deviceID: UUID) async {
        logger.info("Wiring message handlers for device \(deviceID)")

        // Populate blocked contacts cache
        await refreshBlockedContactsCache(deviceID: deviceID, dataStore: services.dataStore)

        // Cache device node name for self-mention detection
        let device = try? await services.dataStore.fetchDevice(id: deviceID)
        let selfNodeName = device?.nodeName ?? ""

        // Contact message handler (direct messages)
        await services.messagePollingService.setContactMessageHandler { [weak self] message, contact in
            guard let self else { return }

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            // Correct invalid timestamps (sender clock wrong)
            let receiveTime = Date()
            let (finalTimestamp, timestampCorrected) = Self.correctTimestampIfNeeded(timestamp, receiveTime: receiveTime)
            if timestampCorrected {
                self.logger.debug("Corrected invalid direct message timestamp from \(Date(timeIntervalSince1970: TimeInterval(timestamp))) to \(receiveTime)")
            }

            // Look up path data from RxLogEntry (for direct messages, channelIndex is nil)
            var pathNodes: Data?
            var pathLength = message.pathLength
            do {
                if let rxEntry = try await services.dataStore.findRxLogEntry(
                    channelIndex: nil,
                    senderTimestamp: timestamp,
                    withinSeconds: 10,
                    contactName: contact?.displayName
                ) {
                    pathNodes = rxEntry.pathNodes
                    pathLength = rxEntry.pathLength  // Use RxLogEntry pathLength for consistency
                    self.logger.debug("Correlated incoming direct message to RxLogEntry, pathLength: \(pathLength), pathNodes: \(pathNodes?.count ?? 0) bytes")
                } else {
                    self.logger.debug("No RxLogEntry found for direct message from \(contact?.displayName ?? "unknown")")
                }
            } catch {
                self.logger.error("Failed to lookup RxLogEntry for direct message: \(error)")
            }

            // Check for self-mention before creating DTO
            let hasSelfMention = !selfNodeName.isEmpty &&
                MentionUtilities.containsSelfMention(in: message.text, selfName: selfNodeName)

            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: contact?.id,
                channelIndex: nil,
                text: message.text,
                timestamp: finalTimestamp,
                createdAt: receiveTime,
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: pathLength,
                snr: message.snr,
                pathNodes: pathNodes,
                senderKeyPrefix: message.senderPublicKeyPrefix,
                senderNodeName: nil,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0,
                containsSelfMention: hasSelfMention,
                mentionSeen: false,
                timestampCorrected: timestampCorrected,
                senderTimestamp: timestampCorrected ? timestamp : nil
            )

            // Check for duplicate before saving
            if await self.deduplicationCache.isDuplicateDirectMessage(
                contactID: contact?.id ?? MessageDeduplicationCache.unknownContactID,
                timestamp: timestamp,
                content: message.text
            ) {
                self.logger.info("Skipping duplicate direct message")
                return
            }

            // Check if this is a DM reaction
            if let parsed = ReactionParser.parseDM(message.text),
               let contact {
                // Try to find target in cache first
                if let targetMessageID = await services.reactionService.findDMTargetMessage(
                    messageHash: parsed.messageHash,
                    contactID: contact.id
                ) {
                    let reactionDTO = ReactionDTO(
                        messageID: targetMessageID,
                        emoji: parsed.emoji,
                        senderName: contact.displayName,
                        messageHash: parsed.messageHash,
                        rawText: message.text,
                        contactID: contact.id,
                        deviceID: deviceID
                    )
                    if await self.persistReactionIfNew(reactionDTO, services: services) {
                        self.logger.debug("Saved DM reaction \(parsed.emoji) to message \(targetMessageID)")
                    }

                    return  // Don't save as regular message
                }

                // Try persistence fallback
                let now = UInt32(Date().timeIntervalSince1970)
                let windowStart = now > self.reactionTimestampWindowSeconds ? now - self.reactionTimestampWindowSeconds : 0
                let windowEnd = now + self.reactionTimestampWindowSeconds

                if let targetMessage = try? await services.dataStore.findDMMessageForReaction(
                    deviceID: deviceID,
                    contactID: contact.id,
                    messageHash: parsed.messageHash,
                    timestampWindow: windowStart...windowEnd,
                    limit: 200
                ) {
                    let reactionDTO = ReactionDTO(
                        messageID: targetMessage.id,
                        emoji: parsed.emoji,
                        senderName: contact.displayName,
                        messageHash: parsed.messageHash,
                        rawText: message.text,
                        contactID: contact.id,
                        deviceID: deviceID
                    )
                    if await self.persistReactionIfNew(reactionDTO, services: services) {
                        self.logger.debug("Saved DM reaction \(parsed.emoji) to message \(targetMessage.id) (from DB)")
                    }

                    return
                }

                // Queue as pending if target not found
                await services.reactionService.queuePendingDMReaction(
                    parsed: parsed,
                    contactID: contact.id,
                    senderName: contact.displayName,
                    rawText: message.text,
                    deviceID: deviceID
                )

                self.logger.debug("Queued pending DM reaction \(parsed.emoji)")
                return  // Don't save as regular message
            }

            do {
                try await services.dataStore.saveMessage(messageDTO)

                // Index DM message for reaction targeting
                if let contact {
                    let pendingMatches = await services.reactionService.indexDMMessage(
                        id: messageDTO.id,
                        contactID: contact.id,
                        text: message.text,
                        timestamp: timestamp
                    )

                    // Process pending reactions that now have their target
                    for pending in pendingMatches {
                        let reactionDTO = ReactionDTO(
                            messageID: messageDTO.id,
                            emoji: pending.parsed.emoji,
                            senderName: pending.senderName,
                            messageHash: pending.parsed.messageHash,
                            rawText: pending.rawText,
                            contactID: contact.id,
                            deviceID: deviceID
                        )
                        if await self.persistReactionIfNew(reactionDTO, services: services) {
                            self.logger.debug("Processed pending DM reaction \(pending.parsed.emoji)")
                        }
                    }
                }

                // Update contact's last message date
                if let contactID = contact?.id {
                    try await services.dataStore.updateContactLastMessage(contactID: contactID, date: Date())
                }

                // Only increment unread count, post notification, and update badge for non-blocked contacts
                if let contactID = contact?.id, contact?.isBlocked != true {
                    // Only increment unread if user is NOT currently viewing this contact's chat
                    let isViewingContact = await services.notificationService.activeContactID == contactID
                    if !isViewingContact {
                        try await services.dataStore.incrementUnreadCount(contactID: contactID)

                        // Increment unread mention count if message contains self-mention
                        if hasSelfMention {
                            try await services.dataStore.incrementUnreadMentionCount(contactID: contactID)
                        }
                    }

                    await services.notificationService.postDirectMessageNotification(
                        from: contact?.displayName ?? "Unknown",
                        contactID: contactID,
                        messageText: message.text,
                        messageID: messageDTO.id,
                        isMuted: contact?.isMuted ?? false
                    )
                    await services.notificationService.updateBadgeCount()
                }

                // Notify UI via SyncCoordinator
                await self.notifyConversationsChanged()

                // Notify MessageEventBroadcaster for real-time chat updates
                if let contact {
                    await self.onDirectMessageReceived?(messageDTO, contact)
                }
            } catch {
                self.logger.error("Failed to save contact message: \(error)")
            }
        }

        // Channel message handler
        await services.messagePollingService.setChannelMessageHandler { [weak self] message, channel in
            guard let self else { return }

            // Parse "NodeName: text" format for sender name
            let (senderNodeName, messageText) = Self.parseChannelMessage(message.text)

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            // Correct invalid timestamps (sender clock wrong)
            let receiveTime = Date()
            let (finalTimestamp, timestampCorrected) = Self.correctTimestampIfNeeded(timestamp, receiveTime: receiveTime)
            if timestampCorrected {
                self.logger.debug("Corrected invalid channel message timestamp from \(Date(timeIntervalSince1970: TimeInterval(timestamp))) to \(receiveTime)")
            }

            // Look up path data from RxLogEntry using sender timestamp (stored during decryption)
            var pathNodes: Data?
            var pathLength = message.pathLength
            self.logger.debug("Looking up RxLogEntry for channel \(message.channelIndex) with senderTimestamp: \(timestamp)")
            do {
                if let rxEntry = try await services.dataStore.findRxLogEntry(
                    channelIndex: message.channelIndex,
                    senderTimestamp: timestamp,
                    withinSeconds: 10
                ) {
                    pathNodes = rxEntry.pathNodes
                    pathLength = rxEntry.pathLength  // Use RxLogEntry pathLength for consistency
                    self.logger.info("Correlated channel message to RxLogEntry: pathLength=\(pathLength), pathNodes=\(pathNodes?.count ?? 0) bytes")
                } else {
                    self.logger.warning("No RxLogEntry found for channel \(message.channelIndex), senderTimestamp: \(timestamp)")
                }
            } catch {
                self.logger.error("Failed to lookup RxLogEntry for channel message: \(error)")
            }

            // Check for self-mention before creating DTO
            // Filter out messages where user mentions themselves
            let hasSelfMention = !selfNodeName.isEmpty &&
                senderNodeName != selfNodeName &&
                MentionUtilities.containsSelfMention(in: messageText, selfName: selfNodeName)

            let messageDTO = MessageDTO(
                id: UUID(),
                deviceID: deviceID,
                contactID: nil,
                channelIndex: message.channelIndex,
                text: messageText,
                timestamp: finalTimestamp,
                createdAt: receiveTime,
                direction: .incoming,
                status: .delivered,
                textType: TextType(rawValue: message.textType) ?? .plain,
                ackCode: nil,
                pathLength: pathLength,
                snr: message.snr,
                pathNodes: pathNodes,
                senderKeyPrefix: nil,
                senderNodeName: senderNodeName,
                isRead: false,
                replyToID: nil,
                roundTripTime: nil,
                heardRepeats: 0,
                retryAttempt: 0,
                maxRetryAttempts: 0,
                containsSelfMention: hasSelfMention,
                mentionSeen: false,
                timestampCorrected: timestampCorrected,
                senderTimestamp: timestampCorrected ? timestamp : nil
            )

            // Check for duplicate before saving
            if await self.deduplicationCache.isDuplicateChannelMessage(
                channelIndex: message.channelIndex,
                timestamp: timestamp,
                username: senderNodeName ?? "",
                content: messageText
            ) {
                self.logger.info("Skipping duplicate channel message")
                return
            }

            // Check if this is a reaction
            if let parsed = services.reactionService.tryProcessAsReaction(messageText) {
                if let targetMessageID = await services.reactionService.findTargetMessage(
                    parsed: parsed,
                    channelIndex: message.channelIndex
                ) {
                    let reactionDTO = ReactionDTO(
                        messageID: targetMessageID,
                        emoji: parsed.emoji,
                        senderName: senderNodeName ?? "Unknown",
                        messageHash: parsed.messageHash,
                        rawText: messageText,
                        channelIndex: message.channelIndex,
                        deviceID: deviceID
                    )
                    if await self.persistReactionIfNew(reactionDTO, services: services) {
                        self.logger.debug("Saved reaction \(parsed.emoji) to message \(targetMessageID)")
                    }

                    return  // Don't save as regular message
                }
                let now = UInt32(receiveTime.timeIntervalSince1970)
                let windowStart = now > self.reactionTimestampWindowSeconds ? now - self.reactionTimestampWindowSeconds : 0
                let windowEnd = now + self.reactionTimestampWindowSeconds

                self.logger.debug("[REACTION-DEBUG] DB lookup: selfNodeName='\(selfNodeName)', targetSender=\(parsed.targetSender), hash=\(parsed.messageHash)")

                if let targetMessage = try? await services.dataStore.findChannelMessageForReaction(
                    deviceID: deviceID,
                    channelIndex: message.channelIndex,
                    parsedReaction: parsed,
                    localNodeName: selfNodeName.isEmpty ? nil : selfNodeName,
                    timestampWindow: windowStart...windowEnd,
                    limit: 200
                ) {
                    let targetMessageID = targetMessage.id
                    let reactionDTO = ReactionDTO(
                        messageID: targetMessageID,
                        emoji: parsed.emoji,
                        senderName: senderNodeName ?? "Unknown",
                        messageHash: parsed.messageHash,
                        rawText: messageText,
                        channelIndex: message.channelIndex,
                        deviceID: deviceID
                    )
                    if await self.persistReactionIfNew(reactionDTO, services: services) {
                        let targetSenderName: String?
                        if targetMessage.direction == .outgoing {
                            targetSenderName = selfNodeName.isEmpty ? nil : selfNodeName
                        } else {
                            targetSenderName = targetMessage.senderNodeName
                        }

                        if let targetSenderName {
                            // Index for future reactions (pending matches not needed here since
                            // message exists in DB, so pending reactions would also match via DB fallback)
                            _ = await services.reactionService.indexMessage(
                                id: targetMessageID,
                                channelIndex: message.channelIndex,
                                senderName: targetSenderName,
                                text: targetMessage.text,
                                timestamp: targetMessage.reactionTimestamp
                            )
                        }

                        self.logger.debug("Saved reaction \(parsed.emoji) to message \(targetMessageID) via DB lookup")
                    }

                    return  // Don't save as regular message
                }

                // Queue reaction for later matching when target message arrives
                await services.reactionService.queuePendingReaction(
                    parsed: parsed,
                    channelIndex: message.channelIndex,
                    senderNodeName: senderNodeName ?? "Unknown",
                    rawText: messageText,
                    deviceID: deviceID
                )
                return  // Don't save as regular message
            }

            do {
                try await services.dataStore.saveMessage(messageDTO)

                // Index message for reaction matching and process any pending reactions
                // Use original timestamp for indexing so pending reactions can match
                if let senderName = senderNodeName {
                    let pendingMatches = await services.reactionService.indexMessage(
                        id: messageDTO.id,
                        channelIndex: message.channelIndex,
                        senderName: senderName,
                        text: messageText,
                        timestamp: timestamp
                    )

                    // Process any pending reactions that now have their target
                    for pending in pendingMatches {
                        let reactionDTO = ReactionDTO(
                            messageID: messageDTO.id,
                            emoji: pending.parsed.emoji,
                            senderName: pending.senderNodeName,
                            messageHash: pending.parsed.messageHash,
                            rawText: pending.rawText,
                            channelIndex: pending.channelIndex,
                            deviceID: pending.deviceID
                        )
                        await self.persistReactionIfNew(reactionDTO, services: services)
                    }
                }

                // Update channel's last message date
                if let channelID = channel?.id {
                    try await services.dataStore.updateChannelLastMessage(channelID: channelID, date: Date())
                }

                // Only update unread count, badges, and notify UI for non-blocked senders
                if await !self.isBlockedSender(senderNodeName) {
                    if let channelID = channel?.id {
                        // Only increment unread if user is NOT currently viewing this channel
                        let activeIndex = await services.notificationService.activeChannelIndex
                        let activeDeviceID = await services.notificationService.activeChannelDeviceID
                        let isViewingChannel = activeIndex == channel?.index && activeDeviceID == channel?.deviceID
                        if !isViewingChannel {
                            try await services.dataStore.incrementChannelUnreadCount(channelID: channelID)

                            // Increment unread mention count if message contains self-mention
                            if hasSelfMention {
                                try await services.dataStore.incrementChannelUnreadMentionCount(channelID: channelID)
                            }
                        }
                    }
                    if channel == nil {
                        await self.recordUnresolvedChannelNotification(
                            channelIndex: message.channelIndex,
                            deviceID: deviceID,
                            senderTimestamp: timestamp
                        )
                    }

                    await services.notificationService.postChannelMessageNotification(
                        channelName: channel?.name ?? "Channel \(message.channelIndex)",
                        channelIndex: message.channelIndex,
                        deviceID: deviceID,
                        senderName: senderNodeName,
                        messageText: messageText,
                        messageID: messageDTO.id,
                        notificationLevel: channel?.notificationLevel ?? .all,
                        hasSelfMention: hasSelfMention
                    )
                    await services.notificationService.updateBadgeCount()

                    // Notify MessageEventBroadcaster for real-time chat updates
                    await self.onChannelMessageReceived?(messageDTO, message.channelIndex)
                }

                // Notify conversation list of changes
                await self.notifyConversationsChanged()
            } catch {
                self.logger.error("Failed to save channel message: \(error)")
            }
        }

        // Signed message handler (room server messages)
        await services.messagePollingService.setSignedMessageHandler { [weak self] message, _ in
            guard let self else { return }

            // For signed room messages, the signature contains the 4-byte author key prefix
            guard let authorPrefix = message.signature?.prefix(4), authorPrefix.count == 4 else {
                self.logger.warning("Dropping signed message: missing or invalid author prefix")
                return
            }

            let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

            do {
                let savedMessage = try await services.roomServerService.handleIncomingMessage(
                    senderPublicKeyPrefix: message.senderPublicKeyPrefix,
                    timestamp: timestamp,
                    authorPrefix: Data(authorPrefix),
                    text: message.text
                )

                // If message was saved (not a duplicate), notify UI and post notification
                if let savedMessage {
                    // Fetch session for room name and mute status
                    let session = try? await services.dataStore.fetchRemoteNodeSession(id: savedMessage.sessionID)

                    // Post notification for room message
                    await services.notificationService.postRoomMessageNotification(
                        roomName: session?.name ?? "Room",
                        senderName: savedMessage.authorName,
                        messageText: savedMessage.text,
                        messageID: savedMessage.id,
                        notificationLevel: session?.notificationLevel ?? .all
                    )
                    await services.notificationService.updateBadgeCount()

                    await self.notifyConversationsChanged()
                    await self.onRoomMessageReceived?(savedMessage)
                }
            } catch {
                self.logger.error("Failed to handle room message: \(error)")
            }
        }

        // CLI message handler (repeater admin responses)
        await services.messagePollingService.setCLIMessageHandler { [weak self] message, contact in
            guard let self else { return }

            if let contact {
                await services.repeaterAdminService.invokeCLIHandler(message, fromContact: contact)
            } else {
                self.logger.warning("Dropping CLI response: no contact found for sender")
            }
        }

        logger.info("Message handlers wired successfully")
    }

    // MARK: - Discovery Handler Wiring

    func wireDiscoveryHandlers(services: ServiceContainer, deviceID: UUID) async {
        logger.info("Wiring discovery handlers for device \(deviceID)")

        // New contact discovered handler (manual-add mode)
        // Posts notification when a new contact is discovered via advertisement
        await services.advertisementService.setNewContactDiscoveredHandler { [weak self] contactName, contactID, contactType in
            guard let self else { return }

            await services.notificationService.postNewContactNotification(
                contactName: contactName,
                contactID: contactID,
                contactType: contactType
            )

            await self.notifyContactsChanged()
        }

        // Contact sync request handler (auto-add mode)
        // AdvertisementService fetches and saves the new contact directly,
        // this handler just triggers UI refresh
        await services.advertisementService.setContactSyncRequestHandler { [weak self] _ in
            guard let self else { return }
            await self.notifyContactsChanged()
        }

        logger.info("Discovery handlers wired successfully")
    }

    // MARK: - Message Handler Helpers

    private func recordUnresolvedChannelNotification(
        channelIndex: UInt8,
        deviceID: UUID,
        senderTimestamp: UInt32
    ) {
        let isNewIndex = unresolvedChannelIndices.insert(channelIndex).inserted
        logger.warning(
            "Posting notification for unresolved channel \(channelIndex) on device \(deviceID), senderTimestamp: \(senderTimestamp)"
        )

        let now = Date()
        let shouldEmitSummary: Bool
        if isNewIndex {
            shouldEmitSummary = true
        } else if let lastSummary = lastUnresolvedChannelSummaryAt {
            shouldEmitSummary = now.timeIntervalSince(lastSummary) >= unresolvedChannelSummaryIntervalSeconds
        } else {
            shouldEmitSummary = true
        }

        guard shouldEmitSummary else { return }
        let sortedIndices = unresolvedChannelIndices.sorted()
        logger.warning(
            "Unresolved channel notification summary: total=\(sortedIndices.count), indices=\(sortedIndices)"
        )
        lastUnresolvedChannelSummaryAt = now
    }

    private nonisolated static func parseChannelMessage(_ text: String) -> (senderNodeName: String?, messageText: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        if parts.count > 1 {
            let senderName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let messageText = String(parts[1]).trimmingCharacters(in: .whitespaces)
            return (senderName, messageText)
        }
        return (nil, text)
    }
}
