import SwiftUI
import PocketMeshServices

extension ChatViewModel {

    // MARK: - Notification Level

    /// Sets notification level for a conversation with optimistic UI update
    func setNotificationLevel(_ conversation: Conversation, level: NotificationLevel) async {
        guard appState?.connectionState == .ready else { return }
        let originalLevel = conversation.notificationLevel

        // Optimistic UI update
        updateConversationNotificationLevel(conversation, level: level)

        do {
            switch conversation {
            case .direct(let contact):
                // Contacts still use boolean muted
                try await dataStore?.setContactMuted(contact.id, isMuted: level == .muted)
            case .channel(let channel):
                try await dataStore?.setChannelNotificationLevel(channel.id, level: level)
            case .room(let session):
                try await dataStore?.setSessionNotificationLevel(session.id, level: level)
            }
            await notificationService?.updateBadgeCount()
        } catch {
            // Rollback on failure
            updateConversationNotificationLevel(conversation, level: originalLevel)
            logger.error("Failed to set notification level: \(error)")
        }
    }

    /// Toggles between muted and all (for swipe action)
    func toggleMute(_ conversation: Conversation) async {
        let newLevel: NotificationLevel = conversation.isMuted ? .all : .muted
        await setNotificationLevel(conversation, level: newLevel)
    }

    /// Updates the notification level in the local conversations array
    private func updateConversationNotificationLevel(_ conversation: Conversation, level: NotificationLevel) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            if let index = conversations.firstIndex(where: { $0.id == contact.id }) {
                let updated = conversations[index]
                conversations[index] = ContactDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    typeRawValue: updated.typeRawValue,
                    flags: updated.flags,
                    outPathLength: updated.outPathLength,
                    outPath: updated.outPath,
                    lastAdvertTimestamp: updated.lastAdvertTimestamp,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    lastModified: updated.lastModified,
                    nickname: updated.nickname,
                    isBlocked: updated.isBlocked,
                    isMuted: level == .muted,
                    isFavorite: updated.isFavorite,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    ocvPreset: updated.ocvPreset,
                    customOCVArrayString: updated.customOCVArrayString
                )
            }
        case .channel(let channel):
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                let updated = channels[index]
                channels[index] = ChannelDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    index: updated.index,
                    name: updated.name,
                    secret: updated.secret,
                    isEnabled: updated.isEnabled,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    unreadMentionCount: updated.unreadMentionCount,
                    notificationLevel: level,
                    isFavorite: updated.isFavorite
                )
            }
        case .room(let session):
            if let index = roomSessions.firstIndex(where: { $0.id == session.id }) {
                let updated = roomSessions[index]
                roomSessions[index] = RemoteNodeSessionDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    role: updated.role,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    isConnected: updated.isConnected,
                    permissionLevel: updated.permissionLevel,
                    lastConnectedDate: updated.lastConnectedDate,
                    lastBatteryMillivolts: updated.lastBatteryMillivolts,
                    lastUptimeSeconds: updated.lastUptimeSeconds,
                    lastNoiseFloor: updated.lastNoiseFloor,
                    unreadCount: updated.unreadCount,
                    notificationLevel: level,
                    isFavorite: updated.isFavorite,
                    lastRxAirtimeSeconds: updated.lastRxAirtimeSeconds,
                    neighborCount: updated.neighborCount,
                    lastSyncTimestamp: updated.lastSyncTimestamp,
                    lastMessageDate: updated.lastMessageDate
                )
            }
        }
    }

    // MARK: - Favorite

    /// Sets favorite state for a conversation with optimistic UI update
    func setFavorite(_ conversation: Conversation, isFavorite: Bool) async {
        guard appState?.connectionState == .ready else { return }
        guard conversation.isFavorite != isFavorite else { return }

        // Reuse existing toggle logic
        await toggleFavorite(conversation)
    }

    /// Toggles favorite state for a conversation.
    ///
    /// For direct messages (contacts), this pushes the change to the device and waits
    /// for confirmation before updating the UI. For channels and rooms (app-only),
    /// this uses optimistic updates.
    ///
    /// - Parameters:
    ///   - conversation: The conversation to toggle
    ///   - disableAnimation: When true, disables SwiftUI List animations to prevent
    ///     conflicts with swipe action dismissal animations
    func toggleFavorite(_ conversation: Conversation, disableAnimation: Bool = false) async {
        guard appState?.connectionState == .ready else { return }
        let originalState = conversation.isFavorite
        let newState = !originalState

        switch conversation {
        case .direct(let contact):
            // Contacts sync with device - wait for confirmation
            togglingFavoriteID = contact.id
            defer { togglingFavoriteID = nil }

            do {
                try await contactService?.setContactFavorite(contact.id, isFavorite: newState)
                // Device confirmed - update local UI
                if disableAnimation {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        updateConversationFavoriteState(conversation, isFavorite: newState)
                    }
                } else {
                    updateConversationFavoriteState(conversation, isFavorite: newState)
                }
            } catch {
                logger.error("Failed to toggle contact favorite: \(error)")
            }

        case .channel(let channel):
            // Channels are app-only - optimistic update
            if disableAnimation {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    updateConversationFavoriteState(conversation, isFavorite: newState)
                }
            } else {
                updateConversationFavoriteState(conversation, isFavorite: newState)
            }

            do {
                try await dataStore?.setChannelFavorite(channel.id, isFavorite: newState)
            } catch {
                // Rollback on failure
                if disableAnimation {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        updateConversationFavoriteState(conversation, isFavorite: originalState)
                    }
                } else {
                    updateConversationFavoriteState(conversation, isFavorite: originalState)
                }
                logger.error("Failed to toggle channel favorite: \(error)")
            }

        case .room(let session):
            // Rooms are app-only - optimistic update
            if disableAnimation {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    updateConversationFavoriteState(conversation, isFavorite: newState)
                }
            } else {
                updateConversationFavoriteState(conversation, isFavorite: newState)
            }

            do {
                try await dataStore?.setSessionFavorite(session.id, isFavorite: newState)
            } catch {
                // Rollback on failure
                if disableAnimation {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        updateConversationFavoriteState(conversation, isFavorite: originalState)
                    }
                } else {
                    updateConversationFavoriteState(conversation, isFavorite: originalState)
                }
                logger.error("Failed to toggle room favorite: \(error)")
            }
        }
    }

    /// Updates the favorite state in the local conversations array
    private func updateConversationFavoriteState(_ conversation: Conversation, isFavorite: Bool) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            if let index = conversations.firstIndex(where: { $0.id == contact.id }) {
                let updated = conversations[index]
                conversations[index] = ContactDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    typeRawValue: updated.typeRawValue,
                    flags: updated.flags,
                    outPathLength: updated.outPathLength,
                    outPath: updated.outPath,
                    lastAdvertTimestamp: updated.lastAdvertTimestamp,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    lastModified: updated.lastModified,
                    nickname: updated.nickname,
                    isBlocked: updated.isBlocked,
                    isMuted: updated.isMuted,
                    isFavorite: isFavorite,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    ocvPreset: updated.ocvPreset,
                    customOCVArrayString: updated.customOCVArrayString
                )
            }
        case .channel(let channel):
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                let updated = channels[index]
                channels[index] = ChannelDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    index: updated.index,
                    name: updated.name,
                    secret: updated.secret,
                    isEnabled: updated.isEnabled,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    unreadMentionCount: updated.unreadMentionCount,
                    notificationLevel: updated.notificationLevel,
                    isFavorite: isFavorite
                )
            }
        case .room(let session):
            if let index = roomSessions.firstIndex(where: { $0.id == session.id }) {
                let updated = roomSessions[index]
                roomSessions[index] = RemoteNodeSessionDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    role: updated.role,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    isConnected: updated.isConnected,
                    permissionLevel: updated.permissionLevel,
                    lastConnectedDate: updated.lastConnectedDate,
                    lastBatteryMillivolts: updated.lastBatteryMillivolts,
                    lastUptimeSeconds: updated.lastUptimeSeconds,
                    lastNoiseFloor: updated.lastNoiseFloor,
                    unreadCount: updated.unreadCount,
                    notificationLevel: updated.notificationLevel,
                    isFavorite: isFavorite,
                    lastRxAirtimeSeconds: updated.lastRxAirtimeSeconds,
                    neighborCount: updated.neighborCount,
                    lastSyncTimestamp: updated.lastSyncTimestamp,
                    lastMessageDate: updated.lastMessageDate
                )
            }
        }
    }

    // MARK: - Conversation List

    /// Removes a conversation from local arrays for optimistic UI update.
    func removeConversation(_ conversation: Conversation) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            conversations = conversations.filter { $0.id != contact.id }
        case .channel(let channel):
            channels = channels.filter { $0.id != channel.id }
        case .room(let session):
            roomSessions = roomSessions.filter { $0.id != session.id }
        }
    }

    /// Load conversations for a device
    func loadConversations(deviceID: UUID) async {
        guard let dataStore else { return }

        isLoading = true
        errorMessage = nil

        do {
            conversations = try await dataStore.fetchConversations(deviceID: deviceID)
            invalidateConversationCache()
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoadedOnce = true
        isLoading = false
    }

    /// Load all contacts for mention autocomplete
    func loadAllContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
            contactNameSet = Set(allContacts.map(\.name))
        } catch {
            logger.warning("Failed to load contacts for mentions: \(error.localizedDescription)")
        }
    }

    /// Load channels for a device
    func loadChannels(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            channels = try await dataStore.fetchChannels(deviceID: deviceID)
            invalidateConversationCache()
        } catch {
            // Silently handle - channels are optional
        }
    }

    /// Load room sessions for a device
    func loadRoomSessions(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            let sessions = try await dataStore.fetchRemoteNodeSessions(deviceID: deviceID)
            roomSessions = sessions.filter { $0.isRoom }
            invalidateConversationCache()
        } catch {
            // Silently handle - rooms are optional
        }
    }

    /// Load all conversations (contacts + channels + rooms) for unified display
    func loadAllConversations(deviceID: UUID) async {
        await loadConversations(deviceID: deviceID)
        await loadChannels(deviceID: deviceID)
        await loadRoomSessions(deviceID: deviceID)
        await loadLastMessagePreviews()
    }

    // MARK: - Messages

    /// Load messages for a contact
    func loadMessages(for contact: ContactDTO) async {
        guard let dataStore else { return }

        // Clear preview state only when switching to a different conversation
        if currentContact?.id != contact.id {
            clearPreviewState()
            newMessagesDividerMessageID = nil
            dividerComputed = false
        }

        currentContact = contact

        // Track active conversation for notification suppression
        notificationService?.activeContactID = contact.id

        isLoading = true
        errorMessage = nil

        // Reset pagination state for new conversation
        hasMoreMessages = true
        isLoadingOlder = false
        totalFetchedCount = 0

        do {
            var fetchedMessages = try await dataStore.fetchMessages(contactID: contact.id, limit: pageSize, offset: 0)
            let unfilteredCount = fetchedMessages.count
            totalFetchedCount = unfilteredCount

            // Compute divider position before filtering, using unfiltered array
            computeDividerPosition(from: fetchedMessages, unreadCount: contact.unreadCount)

            // Hide sent reaction messages (unless failed)
            fetchedMessages = filterOutgoingReactionMessages(fetchedMessages, isDM: true)

            messages = fetchedMessages
            hasMoreMessages = unfilteredCount == pageSize

            buildDisplayItems()

            // Index loaded messages for reaction matching and process any pending reactions
            if let reactionService = appState?.services?.reactionService {
                for message in fetchedMessages {
                    let pendingMatches = await reactionService.indexDMMessage(
                        id: message.id,
                        contactID: contact.id,
                        text: message.text,
                        timestamp: message.reactionTimestamp
                    )

                    // Process any pending reactions that now have their target
                    for pending in pendingMatches {
                        let exists = try? await dataStore.reactionExists(
                            messageID: message.id,
                            senderName: pending.senderName,
                            emoji: pending.parsed.emoji
                        )

                        if exists != true {
                            let reactionDTO = ReactionDTO(
                                messageID: message.id,
                                emoji: pending.parsed.emoji,
                                senderName: pending.senderName,
                                messageHash: pending.parsed.messageHash,
                                rawText: pending.rawText,
                                contactID: contact.id,
                                deviceID: contact.deviceID
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

            // Clear unread count and mention badge, then notify UI to refresh chat list
            try await dataStore.clearUnreadCount(contactID: contact.id)
            try await dataStore.clearUnreadMentionCount(contactID: contact.id)
            syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoadedOnce = true
        isLoading = false
    }

    /// Optimistically append a message if not already present.
    /// Called synchronously before async reload to ensure ChatTableView
    /// sees the new count immediately for unread tracking.
    func appendMessageIfNew(_ message: MessageDTO) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        let previous = messages.last
        messages.append(message)
        messagesByID[message.id] = message
        totalFetchedCount += 1

        // Build display item synchronously for immediate consistency
        let flags = Self.computeDisplayFlags(for: message, previous: previous)
        let newItem = MessageDisplayItem(
            messageID: message.id,
            showTimestamp: flags.showTimestamp,
            showDirectionGap: flags.showDirectionGap,
            showSenderName: flags.showSenderName,
            showNewMessagesDivider: false,
            detectedURL: nil,  // URL detection deferred to avoid main thread blocking
            isImageURL: false,
            isOutgoing: message.isOutgoing,
            status: message.status,
            containsSelfMention: message.containsSelfMention,
            mentionSeen: message.mentionSeen,
            heardRepeats: message.heardRepeats,
            retryAttempt: message.retryAttempt,
            maxRetryAttempts: message.maxRetryAttempts,
            reactionSummary: message.reactionSummary,
            previewState: .idle,
            loadedPreview: nil
        )
        displayItems.append(newItem)
        displayItemIndexByID[message.id] = displayItems.count - 1

        // Async URL detection for this message only
        // Capture messageID (not index) to handle concurrent buildDisplayItems() calls
        let messageID = message.id
        let text = message.text
        Task {
            await updateURLForDisplayItem(messageID: messageID, text: text)
        }

        // Add sender to channelSenders if new (for channel messages)
        if let senderName = message.senderNodeName,
           let deviceID = currentChannel?.deviceID {
            addChannelSenderIfNew(senderName, deviceID: deviceID)
        }
    }

    /// Update URL detection for a single display item by message ID.
    /// Uses O(1) dictionary lookup to handle concurrent array modifications.
    private func updateURLForDisplayItem(messageID: UUID, text: String) async {
        let detectedURL = await Task.detached(priority: .userInitiated) {
            LinkPreviewService.extractFirstURL(from: text)
        }.value

        guard let index = displayItemIndexByID[messageID] else { return }
        let item = displayItems[index]
        displayItems[index] = MessageDisplayItem(
            messageID: item.messageID,
            showTimestamp: item.showTimestamp,
            showDirectionGap: item.showDirectionGap,
            showSenderName: item.showSenderName,
            showNewMessagesDivider: item.showNewMessagesDivider,
            detectedURL: detectedURL,
            isImageURL: detectedURL.map { ImageURLDetector.isImageURL($0) } ?? false,
            isOutgoing: item.isOutgoing,
            status: item.status,
            containsSelfMention: item.containsSelfMention,
            mentionSeen: item.mentionSeen,
            heardRepeats: item.heardRepeats,
            retryAttempt: item.retryAttempt,
            maxRetryAttempts: item.maxRetryAttempts,
            reactionSummary: item.reactionSummary,
            previewState: previewStates[messageID] ?? .idle,
            loadedPreview: loadedPreviews[messageID]
        )
    }

    /// Load any saved draft for the current contact
    /// Drafts are consumed (removed) after loading to prevent re-display
    /// If no draft exists, this method does nothing
    func loadDraftIfExists() {
        guard let contact = currentContact,
              let notificationService,
              let draft = notificationService.consumeDraft(for: contact.id) else {
            return
        }
        composingText = draft
    }

    /// Send a message to the current contact
    /// This is non-blocking - message is created and shown immediately, sent in background
    func sendMessage() async {
        guard let contact = currentContact,
              let messageService,
              !composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let text = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        composingText = ""
        errorMessage = nil

        do {
            // Create message immediately and show it
            let message = try await messageService.createPendingMessage(text: text, to: contact)
            appendMessageIfNew(message)

            // Queue for sending
            sendQueue.append(QueuedMessage(messageID: message.id, contactID: contact.id))

            // Start processor if not already running
            if !isProcessingQueue {
                Task { await processQueue() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh messages for current contact
    func refreshMessages() async {
        guard let contact = currentContact else { return }
        await loadMessages(for: contact)
    }

    // MARK: - Pagination

    /// Load older messages when user scrolls near the top
    func loadOlderMessages() async {
        // Guard against duplicate fetches and end of history
        guard !isLoadingOlder, hasMoreMessages else { return }
        guard let dataStore else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        // Snapshot conversation context before any await — actor reentrancy
        // means currentContact/currentChannel can change during suspensions
        let contact = currentContact
        let channel = currentChannel

        do {
            let currentOffset = totalFetchedCount
            var olderMessages: [MessageDTO]

            if let contact {
                olderMessages = try await dataStore.fetchMessages(
                    contactID: contact.id,
                    limit: pageSize,
                    offset: currentOffset
                )
            } else if let channel {
                olderMessages = try await dataStore.fetchMessages(
                    deviceID: channel.deviceID,
                    channelIndex: channel.index,
                    limit: pageSize,
                    offset: currentOffset
                )
            } else {
                return
            }

            // Use unfiltered count to determine if more messages exist
            let unfilteredCount = olderMessages.count
            totalFetchedCount += unfilteredCount
            if unfilteredCount < pageSize {
                hasMoreMessages = false
            }

            // Filter blocked senders for channel messages
            if channel != nil, let syncCoordinator {
                let blockedNames = await syncCoordinator.blockedSenderNames()
                if !blockedNames.isEmpty {
                    olderMessages = olderMessages.filter { message in
                        guard let senderName = message.senderNodeName else { return true }
                        return !blockedNames.contains(senderName)
                    }
                }
            }

            // Hide sent reaction messages (unless failed)
            let isDM = contact != nil
            olderMessages = filterOutgoingReactionMessages(olderMessages, isDM: isDM)

            // Filter out messages already in array (race condition: appendMessageIfNew can add
            // a message while this fetch is in-flight, causing duplicates)
            let existingIDs = Set(messages.map(\.id))
            olderMessages = olderMessages.filter { !existingIDs.contains($0.id) }

            // Prepend older messages (they're chronologically earlier)
            messages.insert(contentsOf: olderMessages, at: 0)

            // Update lookup dictionary
            for message in olderMessages {
                messagesByID[message.id] = message
            }

            // Rebuild display items with new messages
            buildDisplayItems()

            // Index older channel messages for reaction matching and process pending reactions
            if let channel,
               let reactionService = appState?.services?.reactionService {
                let localNodeName = appState?.connectedDevice?.nodeName
                let deviceID = appState?.connectedDevice?.id ?? UUID()
                for message in olderMessages {
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

            // Index older DM messages for reaction matching and process pending reactions
            if let contact,
               let reactionService = appState?.services?.reactionService {
                for message in olderMessages {
                    let pendingMatches = await reactionService.indexDMMessage(
                        id: message.id,
                        contactID: contact.id,
                        text: message.text,
                        timestamp: message.reactionTimestamp
                    )

                    // Process any pending reactions that now have their target
                    for pending in pendingMatches {
                        let exists = try? await dataStore.reactionExists(
                            messageID: message.id,
                            senderName: pending.senderName,
                            emoji: pending.parsed.emoji
                        )

                        if exists != true {
                            let reactionDTO = ReactionDTO(
                                messageID: message.id,
                                emoji: pending.parsed.emoji,
                                senderName: pending.senderName,
                                messageHash: pending.parsed.messageHash,
                                rawText: pending.rawText,
                                contactID: contact.id,
                                deviceID: contact.deviceID
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

        } catch {
            errorMessage = L10n.Chats.Chats.Errors.loadOlderMessagesFailed
            logger.error("Failed to load older messages: \(error)")
        }
    }

    // MARK: - Message Previews

    /// Get the last message preview for a contact
    func lastMessagePreview(for contact: ContactDTO) -> String? {
        // Check cache first
        if let cached = lastMessageCache[contact.id] {
            return cached.text
        }
        return nil
    }

    /// Load last message previews for all conversations
    func loadLastMessagePreviews() async {
        guard let dataStore else { return }

        // Load contact message previews
        for contact in conversations {
            do {
                // Fetch extra messages in case recent ones are reactions
                let messages = try await dataStore.fetchMessages(contactID: contact.id, limit: 10)

                // Find the last non-reaction message (skip outgoing reactions unless failed)
                let lastMessage = messages.last { message in
                    guard message.direction == .outgoing,
                          ReactionParser.parseDM(message.text) != nil else {
                        return true
                    }
                    return message.status == .failed
                }

                if let lastMessage {
                    lastMessageCache[contact.id] = lastMessage
                }
            } catch {
                // Silently ignore errors for preview loading
            }
        }

        // Load channel message previews (filter out blocked senders)
        let blockedNames = await syncCoordinator?.blockedSenderNames() ?? []
        for channel in channels {
            do {
                // Fetch extra messages in case recent ones are from blocked senders
                let messages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index, limit: 20)

                // Filter out messages from blocked senders and outgoing reactions
                let lastMessage = messages.last { message in
                    // Skip blocked senders
                    if let senderName = message.senderNodeName,
                       blockedNames.contains(senderName) {
                        return false
                    }
                    // Skip outgoing reactions (unless failed)
                    if message.direction == .outgoing,
                       ReactionParser.parse(message.text) != nil,
                       message.status != .failed {
                        return false
                    }
                    return true
                }

                if let lastMessage {
                    lastMessageCache[channel.id] = lastMessage
                } else {
                    lastMessageCache.removeValue(forKey: channel.id)
                }
            } catch {
                // Silently ignore errors for preview loading
            }
        }
    }

    /// Get the last message preview for a channel
    func lastMessagePreview(for channel: ChannelDTO) -> String? {
        if let cached = lastMessageCache[channel.id] {
            return cached.text
        }
        return nil
    }

    // MARK: - Message Actions

    /// Retry sending a failed message with flood routing enabled
    func retryMessage(_ message: MessageDTO) async {
        logger.info("retryMessage called for message: \(message.id)")

        guard let messageService else {
            logger.warning("retryMessage: messageService is nil")
            return
        }

        guard let contact = currentContact else {
            logger.warning("retryMessage: currentContact is nil")
            return
        }

        logger.info("retryMessage: starting retry for contact \(contact.displayName)")

        errorMessage = nil

        // Update status to pending and reload immediately for instant "Sending" feedback
        try? await dataStore?.updateMessageStatus(id: message.id, status: .pending)
        await loadMessages(for: contact)

        do {
            // Retry the existing message (preserves message identity)
            logger.info("retryMessage: calling retryDirectMessage with messageID")
            let result = try await messageService.retryDirectMessage(messageID: message.id, to: contact)
            logger.info("retryMessage: completed with status \(String(describing: result.status))")

            // Reload messages to show updated status
            await loadMessages(for: contact)
        } catch {
            logger.error("retryMessage: error - \(error)")
            errorMessage = error.localizedDescription
            showRetryError = true
            // Reload to show the failed status
            await loadMessages(for: contact)
        }
    }

    /// Resend a channel message in place, or copy text for direct messages.
    /// Used for "Send Again" context menu action.
    func sendAgain(_ message: MessageDTO) async {
        if message.channelIndex != nil {
            // Channel messages: resend in place (increments send count)
            guard let messageService else { return }
            do {
                try await messageService.resendChannelMessage(messageID: message.id)
                // Reload to show updated send count
                if let channel = currentChannel {
                    await loadChannelMessages(for: channel)
                }
            } catch {
                logger.error("Failed to resend message: \(error)")
            }
        } else {
            // Direct messages: keep existing behavior (copy to compose field)
            composingText = message.text
            await sendMessage()
        }
    }

    /// Delete a single message
    func deleteMessage(_ message: MessageDTO) async {
        guard appState?.connectionState == .ready else { return }
        guard let dataStore else { return }

        do {
            try await dataStore.deleteMessage(id: message.id)

            // Remove from all local collections
            messages.removeAll { $0.id == message.id }
            messagesByID.removeValue(forKey: message.id)
            displayItems.removeAll { $0.messageID == message.id }
            // Rebuild index dictionary after removal (indices shift)
            displayItemIndexByID = Dictionary(uniqueKeysWithValues: displayItems.enumerated().map { ($0.element.messageID, $0.offset) })

            // Clean up preview state for deleted message
            cleanupPreviewState(for: message.id)

            // Update last message date if needed
            if let currentContact {
                if let lastMessage = messages.last {
                    try await dataStore.updateContactLastMessage(
                        contactID: currentContact.id,
                        date: lastMessage.date
                    )
                } else {
                    try await dataStore.updateContactLastMessage(
                        contactID: currentContact.id,
                        date: Date.distantPast
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all messages for a contact (conversation deletion)
    func deleteConversation(for contact: ContactDTO) async throws {
        guard appState?.connectionState == .ready else { return }
        guard let dataStore else { return }

        // Fetch all messages for this contact
        let messages = try await dataStore.fetchMessages(contactID: contact.id, limit: 10000)

        // Delete each message
        for message in messages {
            try await dataStore.deleteMessage(id: message.id)
        }

        // Clear unread count before hiding from list
        try await dataStore.clearUnreadCount(contactID: contact.id)

        // Clear last message date on contact (nil removes it from conversations list)
        try await dataStore.updateContactLastMessage(contactID: contact.id, date: nil)

        // Recalculate badge
        await notificationService?.updateBadgeCount()
    }

    // MARK: - Display Items

    /// Build display items with pre-computed properties.
    func buildDisplayItems() {
        messagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })

        let urls = messages.map { LinkPreviewService.extractFirstURL(from: $0.text) }

        displayItems = messages.enumerated().map { index, message in
            // Compute all display flags in single pass to avoid redundant array lookups
            let previous: MessageDTO? = index > 0 ? messages[index - 1] : nil
            let flags = Self.computeDisplayFlags(for: message, previous: previous)
            let url = urls[index]

            return MessageDisplayItem(
                messageID: message.id,
                showTimestamp: flags.showTimestamp,
                showDirectionGap: flags.showDirectionGap,
                showSenderName: flags.showSenderName,
                showNewMessagesDivider: message.id == newMessagesDividerMessageID,
                detectedURL: url,
                isImageURL: url.map { ImageURLDetector.isImageURL($0) } ?? false,
                isOutgoing: message.isOutgoing,
                status: message.status,
                containsSelfMention: message.containsSelfMention,
                mentionSeen: message.mentionSeen,
                heardRepeats: message.heardRepeats,
                retryAttempt: message.retryAttempt,
                maxRetryAttempts: message.maxRetryAttempts,
                reactionSummary: message.reactionSummary,
                previewState: previewStates[message.id] ?? .idle,
                loadedPreview: loadedPreviews[message.id]
            )
        }

        // Build O(1) index lookup
        displayItemIndexByID = Dictionary(uniqueKeysWithValues: displayItems.enumerated().map { ($0.element.messageID, $0.offset) })
    }

    /// Get full message DTO for a display item.
    /// Logs a warning if lookup fails (indicates data inconsistency).
    func message(for displayItem: MessageDisplayItem) -> MessageDTO? {
        guard let message = messagesByID[displayItem.messageID] else {
            logger.warning("Message lookup failed for displayItem id=\(displayItem.messageID)")
            return nil
        }
        return message
    }

    // MARK: - Message Queue

    /// Add a message to the send queue (for testing)
    func enqueueMessage(_ messageID: UUID, contactID: UUID) {
        sendQueue.append(QueuedMessage(messageID: messageID, contactID: contactID))
    }

    /// Process the queue (exposed for testing)
    func processQueueForTesting() async {
        await processQueue()
    }

    /// Process queued messages serially
    private func processQueue() async {
        guard let messageService,
              let dataStore else { return }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        // Snapshot before suspensions — currentContact can change if user switches conversations
        let contact = currentContact
        var lastDeviceID: UUID?

        // Process messages with re-check after reload to catch any that arrived during reload
        repeat {
            while !sendQueue.isEmpty {
                let queued = sendQueue.removeFirst()

                // Fetch the target contact by ID - it may differ from currentContact
                guard let contact = try? await dataStore.fetchContact(id: queued.contactID) else {
                    // Contact was deleted, skip this message
                    logger.info("Skipping queued message - contact \(queued.contactID) was deleted")
                    continue
                }

                lastDeviceID = contact.deviceID

                do {
                    _ = try await messageService.retryDirectMessage(
                        messageID: queued.messageID,
                        to: contact
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            // Reload after queue drains - syncs statuses and conversation list
            if let contact {
                await loadMessages(for: contact)
            }
            if let deviceID = lastDeviceID {
                await loadConversations(deviceID: deviceID)
            }
        } while !sendQueue.isEmpty
    }
}
