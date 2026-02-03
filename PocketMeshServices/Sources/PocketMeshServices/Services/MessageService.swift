import Foundation
import MeshCore
import os

// MARK: - Message Service Errors

/// Errors that can occur during message operations.
public enum MessageServiceError: Error, Sendable {
    /// Not connected to a device
    case notConnected
    /// Contact not found in database
    case contactNotFound
    /// Channel not found in database
    case channelNotFound
    /// Message send operation failed
    case sendFailed(String)
    /// Attempted to send message to invalid recipient (e.g., repeater)
    case invalidRecipient
    /// Message text exceeds maximum allowed length
    case messageTooLong
    /// Underlying MeshCore session error
    case sessionError(MeshCoreError)
}

// MARK: - Message Service Configuration

/// Configuration for message retry and routing behavior.
///
/// Controls how the message service handles delivery failures and routing fallback.
public struct MessageServiceConfig: Sendable {
    /// Whether to use flood routing when user manually retries a failed message
    public let floodFallbackOnRetry: Bool

    /// Maximum total send attempts for automatic retry
    public let maxAttempts: Int

    /// Maximum attempts to make after switching to flood routing
    public let maxFloodAttempts: Int

    /// Number of direct attempts before switching to flood routing
    public let floodAfter: Int

    /// Minimum timeout in seconds (floor for device-suggested timeout)
    public let minTimeout: TimeInterval

    /// Whether to trigger path discovery after successful flood delivery
    public let triggerPathDiscoveryAfterFlood: Bool

    public init(
        floodFallbackOnRetry: Bool = true,
        maxAttempts: Int = 4,
        maxFloodAttempts: Int = 2,
        floodAfter: Int = 2,
        minTimeout: TimeInterval = 0,
        triggerPathDiscoveryAfterFlood: Bool = true
    ) {
        self.floodFallbackOnRetry = floodFallbackOnRetry
        self.maxAttempts = maxAttempts
        self.maxFloodAttempts = maxFloodAttempts
        self.floodAfter = floodAfter
        self.minTimeout = minTimeout
        self.triggerPathDiscoveryAfterFlood = triggerPathDiscoveryAfterFlood
    }

    public static let `default` = MessageServiceConfig()
}

// MARK: - Pending ACK Tracker

/// Tracks pending ACKs for message delivery confirmation
public struct PendingAck: Sendable {
    public let messageID: UUID
    public let ackCode: Data
    public let sentAt: Date
    public let timeout: TimeInterval
    public var isDelivered: Bool = false

    /// When true, `checkExpiredAcks` will skip this ACK (retry loop manages expiry)
    public var isRetryManaged: Bool = false

    public init(messageID: UUID, ackCode: Data, sentAt: Date, timeout: TimeInterval, isRetryManaged: Bool = false) {
        self.messageID = messageID
        self.ackCode = ackCode
        self.sentAt = sentAt
        self.timeout = timeout
        self.isRetryManaged = isRetryManaged
    }

    public var isExpired: Bool {
        !isDelivered && Date().timeIntervalSince(sentAt) > timeout
    }

    /// Convert Data ack code to UInt32 for storage
    public var ackCodeUInt32: UInt32 {
        guard ackCode.count >= 4 else { return 0 }
        return ackCode.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
}

// MARK: - Message Service Actor

/// Actor-isolated service for sending messages with retry logic and ACK tracking.
///
/// `MessageService` manages all message operations including:
/// - Sending direct messages to contacts with single-attempt or automatic retry
/// - Sending channel broadcast messages
/// - Tracking pending message acknowledgements (ACKs)
/// - Handling delivery confirmations and failures
/// - Automatic retry with flood routing fallback
///
/// # Example Usage
///
/// ```swift
/// // Send a message with automatic retry
/// let message = try await messageService.sendMessageWithRetry(
///     text: "Hello!",
///     to: contact
/// ) { messageDTO in
///     // Message saved, update UI immediately
///     await updateUI(with: messageDTO)
/// }
/// ```
///
/// # ACK Tracking
///
/// After sending a message, the service tracks pending ACKs and automatically:
/// - Marks messages as delivered when ACK is received
/// - Marks messages as failed when timeout expires
/// - Tracks repeat acknowledgements for network analysis
///
/// Call `startEventListening()` to begin processing ACKs from the session.
public actor MessageService {

    // MARK: - Properties

    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "MessageService")

    private let session: MeshCoreSession
    private let dataStore: PersistenceStore
    private let config: MessageServiceConfig

    /// Contact service for path management (optional - retry with reset requires this)
    private var contactService: ContactService?

    /// Currently tracked pending ACKs (keyed by Data for MeshCore compatibility)
    private var pendingAcks: [Data: PendingAck] = [:]

    /// Continuations waiting for specific ACK codes (for retry loop)
    private var ackContinuations: [Data: CheckedContinuation<Bool, Never>] = [:]

    /// ACK confirmation callback (ackCode, roundTripTime)
    private var ackConfirmationHandler: (@Sendable (UInt32, UInt32) -> Void)?

    /// Message failure callback (messageID)
    private var messageFailedHandler: (@Sendable (UUID) async -> Void)?

    /// Event broadcaster for retry status updates (messageID, attempt, maxAttempts)
    private var retryStatusHandler: (@Sendable (UUID, Int, Int) async -> Void)?

    /// Handler for routing change events (contactID, isFlood)
    private var routingChangedHandler: (@Sendable (UUID, Bool) async -> Void)?

    /// Task for periodic ACK expiry checking
    private var ackCheckTask: Task<Void, Never>?

    /// Task for listening to session events
    private var eventListenerTask: Task<Void, Never>?

    /// Interval between ACK expiry checks (in seconds)
    private var checkInterval: TimeInterval = 5.0

    /// Tracks message IDs currently being retried to prevent concurrent retry attempts
    private var inFlightRetries: Set<UUID> = []

    // MARK: - Initialization

    /// Creates a new message service.
    ///
    /// - Parameters:
    ///   - session: The MeshCore session for sending messages
    ///   - dataStore: The persistence store for saving messages
    ///   - config: Configuration for retry and routing behavior (defaults to `.default`)
    public init(
        session: MeshCoreSession,
        dataStore: PersistenceStore,
        config: MessageServiceConfig = .default
    ) {
        self.session = session
        self.dataStore = dataStore
        self.config = config
    }

    /// Sets the contact service for path management during retry.
    ///
    /// The contact service is used to reset contact paths when switching to flood routing.
    ///
    /// - Parameter service: The contact service to use
    public func setContactService(_ service: ContactService) {
        self.contactService = service
    }

    // MARK: - Event Listening

    /// Starts listening for session events to process message acknowledgements.
    ///
    /// Call this method after connection is established to begin processing ACKs.
    /// The service will automatically update message delivery status when ACKs are received.
    ///
    /// # Important
    /// This must be called for ACK tracking to work. Without event listening,
    /// messages will remain in "sent" status even if ACKs are received.
    public func startEventListening() {
        eventListenerTask?.cancel()

        eventListenerTask = Task { [weak self] in
            guard let self else { return }

            for await event in await session.events() {
                guard !Task.isCancelled else { break }

                switch event {
                case .acknowledgement(let code, _):
                    await handleAcknowledgement(code: code)
                default:
                    break
                }
            }
        }
    }

    /// Stops listening for session events.
    ///
    /// Call this when disconnecting from the device.
    public func stopEventListening() {
        eventListenerTask?.cancel()
        eventListenerTask = nil
    }

    // MARK: - Send Direct Message

    /// Sends a direct message to a contact with a single send attempt.
    ///
    /// This method sends a message once without automatic retry. Use this when you want
    /// to manually control retry logic or when retry is not needed.
    ///
    /// - Parameters:
    ///   - text: The message text to send (max 200 characters)
    ///   - contact: The recipient contact
    ///   - textType: The text encoding type (defaults to `.plain`)
    ///   - replyToID: Optional ID of message being replied to
    ///
    /// - Returns: The created message DTO with pending/sent status
    ///
    /// - Throws:
    ///   - `MessageServiceError.invalidRecipient` if contact is a repeater
    ///   - `MessageServiceError.messageTooLong` if text exceeds 200 characters
    ///   - `MessageServiceError.sessionError` if MeshCore send fails
    ///
    /// # Example
    ///
    /// ```swift
    /// let message = try await messageService.sendDirectMessage(
    ///     text: "Hello!",
    ///     to: contact
    /// )
    /// ```
    public func sendDirectMessage(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil
    ) async throws -> MessageDTO {
        // Prevent messaging repeaters
        guard contact.type != .repeater else {
            throw MessageServiceError.invalidRecipient
        }

        // Validate message length
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        // Save message to store as pending FIRST
        let messageDTO = createOutgoingMessage(
            id: messageID,
            deviceID: contact.deviceID,
            contactID: contact.id,
            text: text,
            timestamp: timestamp,
            textType: textType,
            replyToID: replyToID
        )
        try await dataStore.saveMessage(messageDTO)

        // Single send attempt
        do {
            let sentInfo = try await session.sendMessage(
                to: contact.publicKey,
                text: text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            )

            let ackCodeUInt32 = sentInfo.expectedAck.ackCodeUInt32

            // Update message with ACK code
            try await dataStore.updateMessageAck(
                id: messageID,
                ackCode: ackCodeUInt32,
                status: .sent
            )

            // Track pending ACK
            let timeout = TimeInterval(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2
            trackPendingAck(messageID: messageID, ackCode: sentInfo.expectedAck, timeout: timeout)

            // Update contact's last message date
            try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())

            guard let message = try await dataStore.fetchMessage(id: messageID) else {
                throw MessageServiceError.sendFailed("Failed to fetch saved message")
            }
            return message
        } catch let error as MeshCoreError {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.sessionError(error)
        } catch {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw error
        }
    }

    // MARK: - Send with Automatic Retry

    /// Sends a direct message with automatic retry and flood routing fallback.
    ///
    /// This is the recommended method for sending messages. It automatically:
    /// 1. Attempts direct routing up to `maxAttempts` times
    /// 2. Switches to flood routing after `floodAfter` attempts
    /// 3. Makes up to `maxFloodAttempts` using flood routing
    /// 4. Returns immediately when ACK is received
    ///
    /// The message is saved to the database immediately and the `onMessageCreated`
    /// callback is invoked, allowing the UI to update before the send completes.
    ///
    /// - Parameters:
    ///   - text: The message text to send (max 200 characters)
    ///   - contact: The recipient contact
    ///   - textType: The text encoding type (defaults to `.plain`)
    ///   - replyToID: Optional ID of message being replied to
    ///   - timeout: Custom timeout in seconds (0 = use device-suggested timeout)
    ///   - onMessageCreated: Callback invoked after message is saved to database
    ///
    /// - Returns: The message DTO with final delivery status (delivered or failed)
    ///
    /// - Throws:
    ///   - `MessageServiceError.invalidRecipient` if contact is a repeater
    ///   - `MessageServiceError.messageTooLong` if text exceeds 200 characters
    ///   - `MessageServiceError.sessionError` if MeshCore send fails
    ///
    /// # Example
    ///
    /// ```swift
    /// let message = try await messageService.sendMessageWithRetry(
    ///     text: "Hello!",
    ///     to: contact
    /// ) { savedMessage in
    ///     // Update UI immediately with pending message
    ///     await updateConversation(with: savedMessage)
    /// }
    /// // Message is now delivered or failed
    /// ```
    public func sendMessageWithRetry(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil,
        timeout: TimeInterval = 0,
        onMessageCreated: (@Sendable (MessageDTO) async -> Void)? = nil
    ) async throws -> MessageDTO {
        // Prevent messaging repeaters
        guard contact.type != .repeater else {
            throw MessageServiceError.invalidRecipient
        }

        // Validate message length
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        // Save message to store as pending FIRST
        let messageDTO = createOutgoingMessage(
            id: messageID,
            deviceID: contact.deviceID,
            contactID: contact.id,
            text: text,
            timestamp: timestamp,
            textType: textType,
            replyToID: replyToID
        )
        try await dataStore.saveMessage(messageDTO)

        // Notify caller that message is saved
        await onMessageCreated?(messageDTO)

        // Capture initial routing state to detect changes
        let initialPathLength = contact.outPathLength

        // Run app-layer retry loop with UI notifications
        do {
            let sentInfo = try await sendDirectMessageWithRetryLoop(
                messageID: messageID,
                contactID: contact.id,
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                text: text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                timeout: timeout > 0 ? timeout : nil
            )

            if let sentInfo {
                // Message was ACKed
                let ackCodeUInt32 = sentInfo.expectedAck.ackCodeUInt32

                try await dataStore.updateMessageAck(
                    id: messageID,
                    ackCode: ackCodeUInt32,
                    status: .delivered
                )

                // Update contact's last message date
                try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())
            } else {
                // All attempts exhausted
                try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            }

            // Check if routing changed during retry
            await checkAndNotifyRoutingChange(
                publicKey: contact.publicKey,
                contactID: contact.id,
                deviceID: contact.deviceID,
                initialPathLength: initialPathLength
            )

            guard let message = try await dataStore.fetchMessage(id: messageID) else {
                throw MessageServiceError.sendFailed("Failed to fetch saved message")
            }
            return message
        } catch let error as MeshCoreError {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.sessionError(error)
        } catch {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw error
        }
    }

    /// Creates a pending message without sending it.
    ///
    /// Use this when you want to show the message in the UI immediately
    /// and send it later via `sendExistingMessage`.
    ///
    /// - Parameters:
    ///   - text: The message text
    ///   - contact: The recipient contact
    ///   - textType: The type of text content (default: .plain)
    ///   - replyToID: Optional ID of message being replied to
    ///
    /// - Returns: The created message DTO with pending status
    public func createPendingMessage(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil
    ) async throws -> MessageDTO {
        guard contact.type != .repeater else {
            throw MessageServiceError.invalidRecipient
        }

        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        let messageDTO = createOutgoingMessage(
            id: messageID,
            deviceID: contact.deviceID,
            contactID: contact.id,
            text: text,
            timestamp: timestamp,
            textType: textType,
            replyToID: replyToID
        )
        try await dataStore.saveMessage(messageDTO)

        return messageDTO
    }

    /// Sends an already-created pending message.
    ///
    /// Use this after `createPendingMessage` to send the message.
    /// This allows showing the message in UI immediately while sending in background.
    ///
    /// - Parameters:
    ///   - messageID: The ID of the pending message to send
    ///   - contact: The recipient contact
    ///
    /// - Returns: The updated message DTO with delivery status
    public func sendExistingMessage(
        messageID: UUID,
        to contact: ContactDTO
    ) async throws -> MessageDTO {
        guard let existingMessage = try await dataStore.fetchMessage(id: messageID) else {
            throw MessageServiceError.sendFailed("Message not found")
        }

        let initialPathLength = contact.outPathLength

        do {
            let sentInfo = try await session.sendMessageWithRetry(
                to: contact.publicKey,
                text: existingMessage.text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(existingMessage.timestamp)),
                maxAttempts: config.maxAttempts,
                floodAfter: config.floodAfter,
                maxFloodAttempts: config.maxFloodAttempts
            )

            if let sentInfo {
                let ackCodeUInt32 = sentInfo.expectedAck.ackCodeUInt32
                try await dataStore.updateMessageAck(
                    id: messageID,
                    ackCode: ackCodeUInt32,
                    status: .delivered
                )
                try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())
            } else {
                try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            }

            await checkAndNotifyRoutingChange(
                publicKey: contact.publicKey,
                contactID: contact.id,
                deviceID: contact.deviceID,
                initialPathLength: initialPathLength
            )

            guard let message = try await dataStore.fetchMessage(id: messageID) else {
                throw MessageServiceError.sendFailed("Failed to fetch message after send")
            }
            return message
        } catch let error as MeshCoreError {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.sessionError(error)
        } catch {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw error
        }
    }

    /// Retries sending a failed message with automatic retry logic.
    ///
    /// Use this method to retry messages that previously failed. The retry uses the same
    /// automatic retry logic as `sendMessageWithRetry`, including flood routing fallback.
    ///
    /// - Parameters:
    ///   - messageID: The ID of the failed message to retry
    ///   - contact: The recipient contact
    ///
    /// - Returns: The updated message DTO with new delivery status
    ///
    /// - Throws:
    ///   - `MessageServiceError.sendFailed` if message not found or retry already in progress
    ///   - `MessageServiceError.sessionError` if MeshCore send fails
    ///
    /// # Example
    ///
    /// ```swift
    /// let message = try await messageService.retryDirectMessage(
    ///     messageID: failedMessage.id,
    ///     to: contact
    /// )
    /// ```
    public func retryDirectMessage(
        messageID: UUID,
        to contact: ContactDTO
    ) async throws -> MessageDTO {
        // Guard against concurrent retries
        guard !inFlightRetries.contains(messageID) else {
            logger.warning("Retry already in progress for message: \(messageID)")
            throw MessageServiceError.sendFailed("Retry already in progress")
        }

        inFlightRetries.insert(messageID)
        defer { inFlightRetries.remove(messageID) }

        // Capture initial routing state to detect changes
        let initialPathLength = contact.outPathLength

        guard let existingMessage = try await dataStore.fetchMessage(id: messageID) else {
            throw MessageServiceError.sendFailed("Message not found")
        }

        // Run app-layer retry loop with UI notifications
        do {
            let sentInfo = try await sendDirectMessageWithRetryLoop(
                messageID: messageID,
                contactID: contact.id,
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                text: existingMessage.text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(existingMessage.timestamp)),
                timeout: nil
            )

            if let sentInfo {
                let ackCodeUInt32 = sentInfo.expectedAck.ackCodeUInt32

                try await dataStore.updateMessageAck(
                    id: messageID,
                    ackCode: ackCodeUInt32,
                    status: .delivered
                )

                try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())
            } else {
                try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            }

            // Check if routing changed during retry
            await checkAndNotifyRoutingChange(
                publicKey: contact.publicKey,
                contactID: contact.id,
                deviceID: contact.deviceID,
                initialPathLength: initialPathLength
            )

            guard let message = try await dataStore.fetchMessage(id: messageID) else {
                throw MessageServiceError.sendFailed("Failed to fetch message")
            }
            return message
        } catch let error as MeshCoreError {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.sessionError(error)
        } catch {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw error
        }
    }

    // MARK: - Direct Message Retry Loop

    /// Sends a direct message with app-layer retry logic and UI notifications.
    ///
    /// This function manages the retry loop at the app layer (instead of delegating to MeshCore)
    /// to provide per-attempt UI feedback. On each attempt, it:
    /// - Updates the message status in the database
    /// - Notifies the UI via `retryStatusHandler`
    /// - Switches to flood routing after `floodAfter` failed attempts
    /// - Notifies UI of routing changes via `routingChangedHandler`
    ///
    /// - Parameters:
    ///   - messageID: The message ID for status updates
    ///   - contactID: The contact ID for routing change notifications
    ///   - deviceID: The device ID for saving contact updates
    ///   - publicKey: The full 32-byte destination public key
    ///   - text: The message text
    ///   - timestamp: The message timestamp (must remain constant across retries)
    ///   - timeout: Optional custom timeout per attempt (nil = use device suggested)
    ///
    /// - Returns: `MessageSentInfo` if ACK received, `nil` if all attempts exhausted
    /// - Throws: `MeshCoreError` if send fails with unrecoverable error
    private func sendDirectMessageWithRetryLoop(
        messageID: UUID,
        contactID: UUID,
        deviceID: UUID,
        publicKey: Data,
        text: String,
        timestamp: Date,
        timeout: TimeInterval?
    ) async throws -> MessageSentInfo? {
        var attempts = 0
        var floodAttempts = 0
        var isFloodMode = false

        while attempts < config.maxAttempts && (!isFloodMode || floodAttempts < config.maxFloodAttempts) {
            // Check for task cancellation
            guard !Task.isCancelled else {
                throw CancellationError()
            }

            // Update database and notify UI of retry status (only after first attempt fails)
            if attempts > 0 {
                try await dataStore.updateMessageRetryStatus(
                    id: messageID,
                    status: .retrying,
                    retryAttempt: attempts - 1,
                    maxRetryAttempts: config.maxAttempts - 1
                )
                await retryStatusHandler?(messageID, attempts - 1, config.maxAttempts - 1)
            }

            // Switch to flood routing after floodAfter direct attempts
            if attempts == config.floodAfter && !isFloodMode {
                logger.info("Resetting path to flood after \(attempts) failed attempts")
                do {
                    try await session.resetPath(publicKey: publicKey)
                    isFloodMode = true

                    // Notify UI of routing change and save updated contact
                    if let updatedContact = try await session.getContact(publicKey: publicKey) {
                        _ = try await dataStore.saveContact(deviceID: deviceID, from: updatedContact.toContactFrame())
                    }
                    await routingChangedHandler?(contactID, true)
                } catch {
                    logger.warning("Failed to reset path: \(error.localizedDescription), continuing...")
                    // Continue anyway - device might handle it
                    isFloodMode = true
                }
            }

            if attempts > 0 {
                logger.info("Retry sending message: attempt \(attempts + 1)/\(config.maxAttempts)")
            }

            // Send the message
            let sentInfo = try await session.sendMessage(
                to: publicKey.prefix(6),
                text: text,
                timestamp: timestamp,
                attempt: UInt8(attempts)
            )

            // Wait for ACK with timeout
            let ackTimeout = timeout ?? max(
                config.minTimeout,
                Double(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2
            )

            let ackEvent = await session.waitForEvent(
                matching: { event in
                    if case .acknowledgement(let code, _) = event {
                        return code == sentInfo.expectedAck
                    }
                    return false
                },
                timeout: ackTimeout
            )

            if ackEvent != nil {
                logger.info("Message acknowledged on attempt \(attempts + 1)")
                return sentInfo
            }

            // ACK timeout - increment counters and retry
            attempts += 1
            if isFloodMode {
                floodAttempts += 1
            }
        }

        logger.warning("Message delivery failed after \(attempts) attempts")
        return nil
    }

    // MARK: - Routing Change Detection

    /// Checks if contact routing changed and notifies handler if so.
    ///
    /// Called after sendMessageWithRetry to detect if routing switched
    /// between direct and flood modes during the retry process.
    private func checkAndNotifyRoutingChange(
        publicKey: Data,
        contactID: UUID,
        deviceID: UUID,
        initialPathLength: Int8
    ) async {
        do {
            // Fetch fresh contact state from device
            guard let updatedContact = try await session.getContact(publicKey: publicKey) else {
                logger.info("Contact not found in device contacts after retry")
                return
            }

            // Check if routing changed
            let newPathLength = updatedContact.outPathLength
            if newPathLength != initialPathLength {
                logger.info("Routing changed for contact \(contactID): \(initialPathLength) -> \(newPathLength)")

                // Save updated contact to database
                _ = try await dataStore.saveContact(deviceID: deviceID, from: updatedContact.toContactFrame())

                // Notify UI of routing change
                let isNowFlood = newPathLength < 0
                await routingChangedHandler?(contactID, isNowFlood)
            }
        } catch {
            logger.warning("Failed to check routing change: \(error.localizedDescription)")
        }
    }

    // MARK: - Send Channel Message

    /// Sends a broadcast message to a channel.
    ///
    /// Channel messages are broadcast to all devices listening on the specified channel.
    /// No acknowledgement is expected or tracked for channel messages.
    ///
    /// - Parameters:
    ///   - text: The message text to broadcast (max 200 characters)
    ///   - channelIndex: The channel index (0-7)
    ///   - deviceID: The local device ID
    ///   - textType: The text encoding type (defaults to `.plain`)
    ///
    /// - Returns: The ID of the created message
    ///
    /// - Throws:
    ///   - `MessageServiceError.messageTooLong` if text exceeds 200 characters
    ///   - `MessageServiceError.channelNotFound` if channel index is invalid
    ///   - `MessageServiceError.sessionError` if MeshCore send fails
    ///
    /// # Example
    ///
    /// ```swift
    /// let messageID = try await messageService.sendChannelMessage(
    ///     text: "Hello channel!",
    ///     channelIndex: 0,
    ///     deviceID: device.id
    /// )
    /// ```
    public func sendChannelMessage(
        text: String,
        channelIndex: UInt8,
        deviceID: UUID,
        textType: TextType = .plain
    ) async throws -> (id: UUID, timestamp: UInt32) {
        // Validate message length
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        do {
            try await session.sendChannelMessage(
                channel: channelIndex,
                text: text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            )

            // Save message (channel messages are immediately "sent" - no ACK for broadcasts)
            let messageDTO = createOutgoingChannelMessage(
                id: messageID,
                deviceID: deviceID,
                channelIndex: channelIndex,
                text: text,
                timestamp: timestamp,
                textType: textType
            )
            try await dataStore.saveMessage(messageDTO)

            // Update channel's last message date
            if let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: channelIndex) {
                try await dataStore.updateChannelLastMessage(channelID: channel.id, date: Date())
            }

            return (id: messageID, timestamp: timestamp)
        } catch let error as MeshCoreError {
            throw MessageServiceError.sessionError(error)
        }
    }

    /// Resend an existing channel message, incrementing its send count.
    ///
    /// This is used for "Send Again" - it re-transmits the same message
    /// rather than creating a duplicate. Uses a new timestamp so the mesh
    /// treats it as a fresh broadcast, and updates the stored timestamp
    /// so the message moves to the bottom of the chat.
    public func resendChannelMessage(messageID: UUID) async throws {
        guard let message = try await dataStore.fetchMessage(id: messageID) else {
            throw MessageServiceError.sendFailed("Message not found")
        }
        guard let channelIndex = message.channelIndex else {
            throw MessageServiceError.sendFailed("Not a channel message")
        }

        let now = Date()
        let newTimestamp = UInt32(now.timeIntervalSince1970)

        // Re-send via mesh with new timestamp (fresh broadcast)
        try await session.sendChannelMessage(
            channel: channelIndex,
            text: message.text,
            timestamp: now
        )

        // Update stored timestamp (moves message to bottom of chat)
        try await dataStore.updateMessageTimestamp(id: messageID, timestamp: newTimestamp)

        // Increment send count
        _ = try await dataStore.incrementMessageSendCount(id: messageID)
    }

    // MARK: - ACK Handling

    /// Processes an acknowledgement from the session event stream
    private func handleAcknowledgement(code: Data) async {
        guard pendingAcks[code] != nil else {
            return
        }

        guard pendingAcks[code]?.isDelivered == false else {
            // Already delivered, ignore duplicate
            return
        }

        pendingAcks[code]?.isDelivered = true

        // Resume any waiting continuation
        if let continuation = ackContinuations.removeValue(forKey: code) {
            continuation.resume(returning: true)
        }

        guard let tracking = pendingAcks[code] else { return }

        let roundTripMs = UInt32(Date().timeIntervalSince(tracking.sentAt) * 1000)

        try? await dataStore.updateMessageByAckCode(
            tracking.ackCodeUInt32,
            status: .delivered,
            roundTripTime: roundTripMs
        )

        ackConfirmationHandler?(tracking.ackCodeUInt32, roundTripMs)

        logger.info("ACK received")
    }

    /// Sets a callback to be invoked when an ACK is received.
    ///
    /// - Parameter handler: Callback receiving (ackCode, roundTripTimeMs)
    public func setAckConfirmationHandler(_ handler: @escaping @Sendable (UInt32, UInt32) -> Void) {
        ackConfirmationHandler = handler
    }

    /// Sets a callback to be invoked when a message fails after all retries.
    ///
    /// - Parameter handler: Callback receiving the failed message ID
    public func setMessageFailedHandler(_ handler: @escaping @Sendable (UUID) async -> Void) {
        messageFailedHandler = handler
    }

    /// Sets a callback to be invoked during retry attempts.
    ///
    /// Use this to update UI with retry progress.
    ///
    /// - Parameter handler: Callback receiving (messageID, currentAttempt, maxAttempts)
    public func setRetryStatusHandler(_ handler: @escaping @Sendable (UUID, Int, Int) async -> Void) {
        retryStatusHandler = handler
    }

    /// Sets a callback to be invoked when routing mode changes during retry.
    ///
    /// - Parameter handler: Callback receiving (contactID, isFloodRouting)
    public func setRoutingChangedHandler(_ handler: @escaping @Sendable (UUID, Bool) async -> Void) {
        routingChangedHandler = handler
    }

    // MARK: - Periodic ACK Checking

    /// Starts periodic checking for expired ACKs.
    ///
    /// This method runs a background task that periodically checks for messages
    /// that have exceeded their ACK timeout and marks them as failed.
    ///
    /// - Parameter interval: How often to check for expired ACKs (defaults to 5 seconds)
    ///
    /// # Important
    /// This should be started when the connection is established and stopped when disconnecting.
    public func startAckExpiryChecking(interval: TimeInterval = 5.0) {
        self.checkInterval = interval
        ackCheckTask?.cancel()

        ackCheckTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.checkInterval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                try? await self.checkExpiredAcks()
                await self.cleanupDeliveredAcks()
            }
        }
    }

    /// Stops the periodic ACK expiry checking.
    ///
    /// Call this when disconnecting from the device.
    public func stopAckExpiryChecking() {
        ackCheckTask?.cancel()
        ackCheckTask = nil
    }

    /// Checks for expired ACKs and marks their messages as failed.
    ///
    /// This is called automatically by the periodic checker. You can also call it
    /// manually to force an immediate check.
    ///
    /// - Throws: Database errors when updating message status
    public func checkExpiredAcks() async throws {
        let now = Date()

        let expiredCodes = pendingAcks.filter { _, tracking in
            !tracking.isRetryManaged &&
            !tracking.isDelivered &&
            now.timeIntervalSince(tracking.sentAt) > tracking.timeout
        }.keys

        for ackCode in expiredCodes {
            if let tracking = pendingAcks.removeValue(forKey: ackCode) {
                try await dataStore.updateMessageStatus(id: tracking.messageID, status: .failed)
                logger.warning("Message failed - timeout exceeded")

                await messageFailedHandler?(tracking.messageID)
            }
        }
    }

    /// Cleans up delivered ACK tracking entries.
    ///
    /// Removes ACK tracking data for messages that were delivered.
    /// This prevents unbounded memory growth.
    public func cleanupDeliveredAcks() {
        let deliveredCodes = pendingAcks.filter { _, tracking in
            tracking.isDelivered
        }.keys

        for ackCode in deliveredCodes {
            pendingAcks.removeValue(forKey: ackCode)
        }
    }

    /// Fails all pending messages that are awaiting ACK.
    ///
    /// Use this when disconnecting from the device to mark all in-flight messages as failed.
    ///
    /// - Throws: Database errors when updating message status
    public func failAllPendingMessages() async throws {
        let pendingCodes = pendingAcks.filter { _, tracking in
            !tracking.isDelivered
        }.keys

        for ackCode in pendingCodes {
            if let tracking = pendingAcks.removeValue(forKey: ackCode) {
                try await dataStore.updateMessageStatus(id: tracking.messageID, status: .failed)
                await messageFailedHandler?(tracking.messageID)
            }
        }
    }

    /// Stops ACK checking and fails all pending messages atomically.
    ///
    /// This is the recommended method to call when disconnecting from a device.
    /// It ensures the periodic checker is stopped and all pending messages are marked as failed.
    ///
    /// - Throws: Database errors when updating message status
    public func stopAndFailAllPending() async throws {
        ackCheckTask?.cancel()
        ackCheckTask = nil

        try await failAllPendingMessages()
    }

    /// The current number of pending ACKs being tracked.
    ///
    /// This includes both undelivered messages and recently delivered messages
    /// still in the grace period for tracking repeats.
    public var pendingAckCount: Int {
        pendingAcks.count
    }

    /// Whether ACK expiry checking is currently active.
    public var isAckExpiryCheckingActive: Bool {
        ackCheckTask != nil
    }

    // MARK: - Private Helpers

    private func trackPendingAck(messageID: UUID, ackCode: Data, timeout: TimeInterval) {
        let pending = PendingAck(
            messageID: messageID,
            ackCode: ackCode,
            sentAt: Date(),
            timeout: timeout
        )
        pendingAcks[ackCode] = pending
    }

    private func createOutgoingMessage(
        id: UUID,
        deviceID: UUID,
        contactID: UUID,
        text: String,
        timestamp: UInt32,
        textType: TextType,
        replyToID: UUID?
    ) -> MessageDTO {
        let message = Message(
            id: id,
            deviceID: deviceID,
            contactID: contactID,
            text: text,
            timestamp: timestamp,
            directionRawValue: MessageDirection.outgoing.rawValue,
            statusRawValue: MessageStatus.pending.rawValue,
            textTypeRawValue: textType.rawValue,
            replyToID: replyToID
        )
        return MessageDTO(from: message)
    }

    private func createOutgoingChannelMessage(
        id: UUID,
        deviceID: UUID,
        channelIndex: UInt8,
        text: String,
        timestamp: UInt32,
        textType: TextType
    ) -> MessageDTO {
        let message = Message(
            id: id,
            deviceID: deviceID,
            channelIndex: channelIndex,
            text: text,
            timestamp: timestamp,
            directionRawValue: MessageDirection.outgoing.rawValue,
            statusRawValue: MessageStatus.sent.rawValue,
            textTypeRawValue: textType.rawValue
        )
        return MessageDTO(from: message)
    }
}
