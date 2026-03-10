import Foundation
import PocketMeshServices

extension ChatViewModel {

    // MARK: - Channel Messages

    /// Load messages for a channel
    func loadChannelMessages(for channel: ChannelDTO) async {
        logger.info("loadChannelMessages: start channel=\(channel.index) deviceID=\(channel.deviceID)")

        guard let dataStore else {
            logger.info("loadChannelMessages: dataStore is nil, returning early")
            return
        }

        // Clear preview state only when switching to a different conversation
        if currentChannel?.id != channel.id {
            clearPreviewState()
            newMessagesDividerMessageID = nil
            dividerComputed = false
        }

        currentChannel = channel
        currentContact = nil

        // Track active channel for notification suppression
        notificationService?.activeContactID = nil
        notificationService?.activeChannelIndex = channel.index
        notificationService?.activeChannelDeviceID = channel.deviceID

        logger.info("loadChannelMessages: setting isLoading=true, current messages.count=\(self.messages.count)")
        isLoading = true
        errorMessage = nil

        // Reset pagination state for new conversation
        hasMoreMessages = true
        isLoadingOlder = false
        totalFetchedCount = 0

        do {
            var fetchedMessages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index, limit: pageSize, offset: 0)
            let unfilteredCount = fetchedMessages.count
            totalFetchedCount = unfilteredCount
            logger.info("loadChannelMessages: fetched \(unfilteredCount) messages")

            // Compute divider position before filtering, using unfiltered array
            computeDividerPosition(from: fetchedMessages, unreadCount: channel.unreadCount)

            // Filter out messages from blocked senders using SyncCoordinator's cache
            if let syncCoordinator {
                let blockedNames = await syncCoordinator.blockedSenderNames()
                if !blockedNames.isEmpty {
                    fetchedMessages = fetchedMessages.filter { message in
                        guard let senderName = message.senderNodeName else { return true }
                        return !blockedNames.contains(senderName)
                    }
                }
            }

            // Hide sent reaction messages (unless failed)
            fetchedMessages = filterOutgoingReactionMessages(fetchedMessages, isDM: false)

            // Use unfiltered count to determine if more messages exist
            hasMoreMessages = unfilteredCount == pageSize
            messages = fetchedMessages

            buildChannelSenders(deviceID: channel.deviceID)
            buildDisplayItems()

            // Index loaded messages for reaction matching and process any pending reactions
            if let reactionService = appState?.services?.reactionService {
                let localNodeName = appState?.connectedDevice?.nodeName
                let deviceID = appState?.connectedDevice?.id ?? UUID()
                for message in fetchedMessages {
                    let senderName: String?
                    if message.isOutgoing {
                        senderName = localNodeName
                    } else {
                        senderName = message.senderNodeName
                    }
                    if let senderName {
                        let pendingMatches = await reactionService.indexMessage(
                            id: message.id,
                            channelIndex: channel.index,
                            senderName: senderName,
                            text: message.text,
                            timestamp: message.timestamp
                        )

                        // Process any pending reactions that now have their target
                        for pending in pendingMatches {
                            let exists = try? await dataStore.reactionExists(
                                messageID: message.id,
                                senderName: pending.senderNodeName,
                                emoji: pending.parsed.emoji
                            )

                            if exists != true {
                                let reactionDTO = ReactionDTO(
                                    messageID: message.id,
                                    emoji: pending.parsed.emoji,
                                    senderName: pending.senderNodeName,
                                    messageHash: pending.parsed.messageHash,
                                    rawText: pending.rawText,
                                    channelIndex: pending.channelIndex,
                                    deviceID: deviceID
                                )
                                if let result = await reactionService.persistReactionAndUpdateSummary(
                                    reactionDTO,
                                    using: dataStore
                                ) {
                                    updateReactionSummary(for: result.messageID, summary: result.summary)
                                }
                            }
                        }
                    }
                }
            }

            // Clear unread count and mention badge, then notify UI to refresh chat list
            try await dataStore.clearChannelUnreadCount(channelID: channel.id)
            try await dataStore.clearChannelUnreadMentionCount(channelID: channel.id)
            syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            logger.info("loadChannelMessages: error - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        logger.info("loadChannelMessages: done, isLoading=false, messages.count=\(self.messages.count)")
        hasLoadedOnce = true
        isLoading = false
    }

    // MARK: - Channel Actions

    /// Send a channel message
    func sendChannelMessage(text: String) async {
        guard let channel = currentChannel,
              let messageService,
              !text.isEmpty else {
            composingText = text
            return
        }

        errorMessage = nil

        do {
            let (messageID, timestamp) = try await messageService.sendChannelMessage(
                text: text,
                channelIndex: channel.index,
                deviceID: channel.deviceID
            )

            // Index immediately for reaction matching (before reload to avoid race)
            // Pending reactions handled by loadChannelMessages below
            if let reactionService = appState?.services?.reactionService,
               let localNodeName = appState?.connectedDevice?.nodeName {
                _ = await reactionService.indexMessage(
                    id: messageID,
                    channelIndex: channel.index,
                    senderName: localNodeName,
                    text: text,
                    timestamp: timestamp
                )
            }

            // Reload messages to show the sent message
            await loadChannelMessages(for: channel)

            // Reload channels to update conversation list
            await loadChannels(deviceID: channel.deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Retry sending a failed channel message.
    /// This resends the message text to MeshCore - the UI should NOT change
    /// during retry. Only the status will update (Sent -> Delivered or Failed).
    func retryChannelMessage(_ message: MessageDTO) async {
        guard let messageService,
              let channel = currentChannel else { return }

        // Update status to pending
        try? await dataStore?.updateMessageStatus(id: message.id, status: .pending)

        // Reload to show updated status
        await loadChannelMessages(for: channel)

        do {
            // Resend the message text
            _ = try await messageService.sendChannelMessage(
                text: message.text,
                channelIndex: channel.index,
                deviceID: channel.deviceID
            )

            // Delete the old failed message since a new one was created
            try await dataStore?.deleteMessage(id: message.id)

            // Reload messages
            await loadChannelMessages(for: channel)
        } catch {
            // Restore failed status
            try? await dataStore?.updateMessageStatus(id: message.id, status: .failed)
            await loadChannelMessages(for: channel)
            errorMessage = error.localizedDescription
            showRetryError = true
        }
    }

    // MARK: - Channel Sender Tracking

    /// Build synthetic contacts from channel message senders not in contacts.
    /// Called after loading channel messages to populate mention picker.
    /// Builds into local collections first to avoid multiple @Observable updates.
    private func buildChannelSenders(deviceID: UUID) {
        var localNames: Set<String> = []
        var localSenders: [ContactDTO] = []
        var localOrder: [String: UInt32] = [:]

        for message in messages {
            if let name = message.senderNodeName {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed.count <= 128 else { continue }

                // Track latest timestamp for all senders (contacts and non-contacts)
                localOrder[trimmed] = max(message.timestamp, localOrder[trimmed] ?? 0)

                // Build synthetic contacts only for non-contact senders
                guard !contactNameSet.contains(trimmed),
                      !localNames.contains(trimmed) else { continue }

                localNames.insert(trimmed)
                localSenders.append(makeSyntheticContact(name: trimmed, deviceID: deviceID))
            }
        }

        // Assign once to minimize observation updates
        channelSenderNames = localNames
        channelSenders = localSenders
        channelSenderOrder = localOrder

        logger.info("Built \(self.channelSenders.count) synthetic contacts from channel senders")
    }

    /// Add a channel sender as a synthetic contact if not already tracked.
    /// Used for incremental additions when new messages arrive.
    func addChannelSenderIfNew(_ name: String, deviceID: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.count <= 128,
              !contactNameSet.contains(trimmed),
              !channelSenderNames.contains(trimmed) else { return }

        channelSenderNames.insert(trimmed)
        channelSenders.append(makeSyntheticContact(name: trimmed, deviceID: deviceID))
    }

    /// Create a synthetic ContactDTO for a channel sender not in contacts.
    private func makeSyntheticContact(name: String, deviceID: UUID) -> ContactDTO {
        ContactDTO(
            id: name.stableUUID,
            deviceID: deviceID,
            publicKey: Data(),
            name: name,
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0xFF,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0.0,
            longitude: 0.0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }
}
