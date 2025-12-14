import Foundation
import OSLog

// MARK: - Message Service Errors

public enum MessageServiceError: Error, Sendable {
    case notConnected
    case contactNotFound
    case channelNotFound
    case sendFailed(String)
    case invalidRecipient
    case messageTooLong
    case protocolError(ProtocolError)
}

// MARK: - Message Service Configuration

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

    public init(
        floodFallbackOnRetry: Bool = true,
        maxAttempts: Int = 3,
        maxFloodAttempts: Int = 2,
        floodAfter: Int = 2,
        minTimeout: TimeInterval = 0
    ) {
        self.floodFallbackOnRetry = floodFallbackOnRetry
        self.maxAttempts = maxAttempts
        self.maxFloodAttempts = maxFloodAttempts
        self.floodAfter = floodAfter
        self.minTimeout = minTimeout
    }

    public static let `default` = MessageServiceConfig()
}

// MARK: - Pending ACK Tracker

/// Tracks pending ACKs for message delivery confirmation
public struct PendingAck: Sendable {
    public let messageID: UUID
    public let ackCode: UInt32
    public let sentAt: Date
    public let timeout: TimeInterval
    public var heardRepeats: Int = 0  // Count of duplicate confirmations
    public var isDelivered: Bool = false  // Track if first confirmation received

    /// When true, `checkExpiredAcks` will skip this ACK (retry loop manages expiry)
    public var isRetryManaged: Bool = false

    public init(messageID: UUID, ackCode: UInt32, sentAt: Date, timeout: TimeInterval, isRetryManaged: Bool = false) {
        self.messageID = messageID
        self.ackCode = ackCode
        self.sentAt = sentAt
        self.timeout = timeout
        self.isRetryManaged = isRetryManaged
    }

    public var isExpired: Bool {
        !isDelivered && Date().timeIntervalSince(sentAt) > timeout
    }
}

// MARK: - Message Service Actor

/// Actor-isolated service for sending messages with retry logic and ACK tracking.
public actor MessageService {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "MessageService")

    private let bleTransport: any BLETransport
    private let dataStore: DataStore
    private let config: MessageServiceConfig

    /// Contact service for path management (optional - retry with reset requires this)
    private var contactService: ContactService?

    /// Currently tracked pending ACKs
    private var pendingAcks: [UInt32: PendingAck] = [:]

    /// Continuations waiting for specific ACK codes (for retry loop)
    private var ackContinuations: [UInt32: CheckedContinuation<Bool, Never>] = [:]

    /// ACK confirmation callback
    private var ackConfirmationHandler: (@Sendable (UInt32, UInt32) -> Void)?

    /// Message failure callback (messageID)
    private var messageFailedHandler: (@Sendable (UUID) async -> Void)?

    /// Task for periodic ACK expiry checking
    private var ackCheckTask: Task<Void, Never>?

    /// Interval between ACK expiry checks (in seconds)
    private var checkInterval: TimeInterval = 5.0

    // MARK: - Initialization

    public init(
        bleTransport: any BLETransport,
        dataStore: DataStore,
        config: MessageServiceConfig = .default
    ) {
        self.bleTransport = bleTransport
        self.dataStore = dataStore
        self.config = config
    }

    /// Set the contact service for path management during retry.
    /// - Parameter service: The contact service to use for path reset operations.
    public func setContactService(_ service: ContactService) {
        self.contactService = service
    }

    // MARK: - Send Direct Message

    /// Sends a direct message to a contact with a single send attempt.
    /// - Parameters:
    ///   - text: The message text
    ///   - contact: The recipient contact
    ///   - textType: The text type (default: plain)
    ///   - replyToID: Optional message ID to reply to
    ///   - useFlood: Whether to use flood routing (default: false, uses contact's setting)
    /// - Returns: The saved message
    public func sendDirectMessage(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil,
        useFlood: Bool = false
    ) async throws -> MessageDTO {
        // Validate message length (throw early - no message saved)
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        // Save message to store as pending FIRST
        // This ensures retry flow always has a message to show
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

        // Check connection state - mark as failed if not connected
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.notConnected
        }

        // Single send attempt
        do {
            let result = try await sendTextMessageAttempt(
                text: text,
                recipientKeyPrefix: contact.publicKeyPrefix,
                textType: textType,
                attempt: 1,
                timestamp: timestamp
            )

            // Debug logging for message routing
            let routeDescription: String
            if contact.isFloodRouted {
                routeDescription = "flood"
            } else if contact.outPathLength == 0 {
                routeDescription = "direct"
            } else {
                let pathHex = contact.outPath.prefix(Int(contact.outPathLength)).map { String(format: "%02X", $0) }.joined(separator: " → ")
                routeDescription = "\(contact.outPathLength) hops: \(pathHex)"
            }
            let recipientHex = contact.publicKeyPrefix.prefix(3).map { String(format: "%02X", $0) }.joined()
            logger.info("Sent to \(recipientHex)... via \(routeDescription), ack=\(result.ackCode), timeout=\(result.estimatedTimeout)ms")

            // Update message with ACK code
            try await dataStore.updateMessageAck(
                id: messageID,
                ackCode: result.ackCode,
                status: .sent
            )

            // Track pending ACK for confirmation with device timeout + 20% buffer
            let timeout = TimeInterval(result.estimatedTimeout) / 1000.0 * 1.2
            trackPendingAck(messageID: messageID, ackCode: result.ackCode, timeout: timeout)

            // Update contact's last message date
            try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())

            // Return the saved message
            guard let message = try await dataStore.fetchMessage(id: messageID) else {
                throw MessageServiceError.sendFailed("Failed to fetch saved message")
            }
            return message
        } catch {
            // Mark as failed immediately on error
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw error
        }
    }

    /// Retry a failed message with flood routing enabled and automatic retry.
    /// - Parameters:
    ///   - text: The message text
    ///   - contact: The recipient contact
    ///   - textType: The text type (default: plain)
    /// - Returns: The saved message
    public func retryDirectMessage(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain
    ) async throws -> MessageDTO {
        // Use the retry method - it will handle flood fallback automatically
        return try await sendMessageWithRetry(
            text: text,
            to: contact,
            textType: textType
        )
    }

    // MARK: - Send with Automatic Retry

    /// Sends a direct message with automatic retry and flood fallback.
    /// Matches the behavior of `send_msg_with_retry` in MeshCore Python.
    ///
    /// - Parameters:
    ///   - text: The message text
    ///   - contact: The recipient contact
    ///   - textType: The text type (default: plain)
    ///   - replyToID: Optional message ID to reply to
    ///   - timeout: Custom timeout per attempt (0 = use device suggested × 1.2)
    /// - Returns: The saved message (status will be .delivered on success, .failed on exhaustion)
    /// - Throws: CancellationError if the task is cancelled during retry
    public func sendMessageWithRetry(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil,
        timeout: TimeInterval = 0
    ) async throws -> MessageDTO {
        // Validate message length (throw early - no message saved)
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        let messageID = UUID()
        // IMPORTANT: Timestamp must remain constant across all retry attempts
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

        // Check connection state
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            try await dataStore.updateMessageStatus(id: messageID, status: .failed)
            throw MessageServiceError.notConnected
        }

        // Determine initial routing state
        var isFlood = contact.isFloodRouted
        var attempts = 0
        var floodAttempts = 0

        // Retry loop
        while attempts < config.maxAttempts && (!isFlood || floodAttempts < config.maxFloodAttempts) {

            // Check for task cancellation at loop start
            guard !Task.isCancelled else {
                try await dataStore.updateMessageStatus(id: messageID, status: .failed)
                throw CancellationError()
            }

            // Small backoff delay between retries (not before first attempt)
            // Gives network time to settle between attempts
            if attempts > 0 {
                let backoffMs = 200 * attempts  // 200ms, 400ms, 600ms...
                try? await Task.sleep(for: .milliseconds(backoffMs))
            }

            // Switch to flood after floodAfter direct attempts
            if attempts == config.floodAfter && !isFlood {
                if let contactService {
                    logger.info("Resetting path to flood after \(attempts) direct attempts")
                    do {
                        try await contactService.resetPath(
                            deviceID: contact.deviceID,
                            publicKey: contact.publicKey
                        )
                        isFlood = true
                    } catch {
                        logger.warning("Failed to reset path: \(error.localizedDescription)")
                        // Continue anyway - firmware might handle it
                    }
                } else {
                    logger.warning("Cannot reset path - ContactService not set")
                }
            }

            if attempts > 0 {
                logger.info("Retry sending message: attempt \(attempts + 1)")
            }

            // Send attempt
            do {
                let result = try await sendTextMessageAttempt(
                    text: text,
                    recipientKeyPrefix: contact.publicKeyPrefix,
                    textType: textType,
                    attempt: UInt8(attempts),
                    timestamp: timestamp  // Same timestamp across all attempts
                )

                // Calculate timeout: use device suggested × 1.2, or custom, with minimum floor
                let deviceTimeout = TimeInterval(result.estimatedTimeout) / 1000.0 * 1.2
                var effectiveTimeout = timeout > 0 ? timeout : deviceTimeout
                effectiveTimeout = max(effectiveTimeout, config.minTimeout)

                // Update message with ACK code
                try await dataStore.updateMessageAck(
                    id: messageID,
                    ackCode: result.ackCode,
                    status: .sent
                )

                // Track pending ACK (marked as retry-managed to avoid conflict with checkExpiredAcks)
                trackPendingAckForRetry(messageID: messageID, ackCode: result.ackCode, timeout: effectiveTimeout)

                // Wait for ACK using continuation-based approach
                let ackReceived = await waitForAck(ackCode: result.ackCode, timeout: effectiveTimeout)

                if ackReceived {
                    // Success! Update contact's last message date
                    try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())

                    // Return the saved message
                    guard let message = try await dataStore.fetchMessage(id: messageID) else {
                        throw MessageServiceError.sendFailed("Failed to fetch saved message")
                    }
                    return message
                }

                // ACK timeout - remove from pending (it will be added fresh on next attempt)
                pendingAcks.removeValue(forKey: result.ackCode)

            } catch is CancellationError {
                // Re-throw cancellation
                try await dataStore.updateMessageStatus(id: messageID, status: .failed)
                throw CancellationError()
            } catch {
                logger.warning("Send attempt \(attempts + 1) failed: \(error.localizedDescription)")
            }

            attempts += 1
            if isFlood {
                floodAttempts += 1
            }
        }

        // All attempts exhausted
        try await dataStore.updateMessageStatus(id: messageID, status: .failed)

        guard let message = try await dataStore.fetchMessage(id: messageID) else {
            throw MessageServiceError.sendFailed("Failed to fetch saved message")
        }
        return message
    }

    /// Sends a channel message (broadcast, no ACK expected).
    /// - Parameters:
    ///   - text: The message text
    ///   - channelIndex: The channel index (0-7)
    ///   - deviceID: The device ID
    ///   - textType: The text type (default: plain)
    public func sendChannelMessage(
        text: String,
        channelIndex: UInt8,
        deviceID: UUID,
        textType: TextType = .plain
    ) async throws -> UUID {
        // Validate message length
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        // Validate channel index
        guard channelIndex < ProtocolLimits.maxChannels else {
            throw MessageServiceError.channelNotFound
        }

        // Check connection state
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw MessageServiceError.notConnected
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        // Encode and send
        let frameData = FrameCodec.encodeSendChannelMessage(
            textType: textType,
            channelIndex: channelIndex,
            timestamp: timestamp,
            text: text
        )

        guard let response = try await bleTransport.send(frameData),
              !response.isEmpty,
              response[0] == ResponseCode.ok.rawValue else {
            throw MessageServiceError.sendFailed("Channel message send failed")
        }

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

        return messageID
    }

    // MARK: - ACK Handling

    /// Processes a send confirmation (ACK) from the device.
    /// Called when PUSH_CODE_SEND_CONFIRMED is received.
    ///
    /// This method handles duplicate confirmations - MeshCore may send the same
    /// ACK multiple times as the message is relayed through the mesh network.
    public func handleSendConfirmation(_ confirmation: SendConfirmation) async throws {
        let ackCode = confirmation.ackCode

        // CRITICAL: Atomic read-modify-write BEFORE any await points
        // This prevents actor reentrancy issues with rapid duplicate ACKs
        guard pendingAcks[ackCode] != nil else {
            // Unknown ACK - might be from before app launched
            logger.warning("Received confirmation for unknown ACK: \(ackCode)")
            return
        }

        let isFirstConfirmation = pendingAcks[ackCode]?.isDelivered == false

        if isFirstConfirmation {
            // Atomically mark as delivered and set initial repeat count
            pendingAcks[ackCode]?.isDelivered = true
            pendingAcks[ackCode]?.heardRepeats = 1

            // Resume any waiting continuation (for retry loop)
            if let continuation = ackContinuations.removeValue(forKey: ackCode) {
                continuation.resume(returning: true)
            }

            // Now safe to perform async operations
            try await dataStore.updateMessageByAckCode(
                ackCode,
                status: .delivered,
                roundTripTime: confirmation.roundTripTime
            )

            // Notify handler
            ackConfirmationHandler?(ackCode, confirmation.roundTripTime)

            logger.info("ACK received - code: \(ackCode), rtt: \(confirmation.roundTripTime)ms")
        } else {
            // Atomically increment repeat count
            pendingAcks[ackCode]?.heardRepeats += 1

            // Get values before await
            guard let tracking = pendingAcks[ackCode] else { return }
            let repeatCount = tracking.heardRepeats

            // Update persisted repeat count
            try await dataStore.updateMessageHeardRepeats(
                id: tracking.messageID,
                heardRepeats: repeatCount
            )

            logger.debug("Heard repeat #\(repeatCount) for ack: \(ackCode)")
        }
    }

    /// Sets a callback for ACK confirmations.
    public func setAckConfirmationHandler(_ handler: @escaping @Sendable (UInt32, UInt32) -> Void) {
        ackConfirmationHandler = handler
    }

    /// Sets a callback for message failures (timeout or send error).
    public func setMessageFailedHandler(_ handler: @escaping @Sendable (UUID) async -> Void) {
        messageFailedHandler = handler
    }

    /// Grace period for tracking repeats after delivery (60 seconds)
    private let repeatTrackingGracePeriod: TimeInterval = 60.0

    /// Checks for expired ACKs (no confirmation received within timeout).
    /// Marks their messages as failed and removes from tracking.
    /// Note: ACKs marked as `isRetryManaged` are skipped - retry loop handles expiry.
    public func checkExpiredAcks() async throws {
        let now = Date()

        // Collect expired entries (not delivered, past timeout, not managed by retry loop)
        let expiredCodes = pendingAcks.filter { _, tracking in
            !tracking.isRetryManaged &&
            !tracking.isDelivered &&
            now.timeIntervalSince(tracking.sentAt) > tracking.timeout
        }.keys

        for ackCode in expiredCodes {
            if let tracking = pendingAcks.removeValue(forKey: ackCode) {
                try await dataStore.updateMessageStatus(id: tracking.messageID, status: .failed)
                logger.warning("Message failed - ack: \(ackCode), timeout exceeded")

                // Handler is called after updating pendingAcks to ensure consistent state
                // if handler triggers re-entrant calls to MessageService
                await messageFailedHandler?(tracking.messageID)
            }
        }
    }

    /// Fails all pending (undelivered) messages without stopping ACK checking.
    /// Called when iOS auto-reconnect completes - device may have rebooted and lost state.
    public func failAllPendingMessages() async throws {
        // Collect all undelivered entries
        let pendingCodes = pendingAcks.filter { _, tracking in
            !tracking.isDelivered
        }.keys

        guard !pendingCodes.isEmpty else {
            logger.debug("No pending messages to fail after reconnect")
            return
        }

        for ackCode in pendingCodes {
            if let tracking = pendingAcks.removeValue(forKey: ackCode) {
                try await dataStore.updateMessageStatus(id: tracking.messageID, status: .failed)
                logger.warning("Message failed - ack: \(ackCode), device reconnected (may have rebooted)")

                // Handler is called after updating pendingAcks to ensure consistent state
                await messageFailedHandler?(tracking.messageID)
            }
        }
    }

    /// Atomically stops ACK checking and fails all pending messages.
    /// Called when BLE connection is lost to provide instant feedback.
    /// Combines both operations to prevent race conditions.
    public func stopAndFailAllPending() async throws {
        // Stop ACK checking first to prevent race with checkExpiredAcks()
        ackCheckTask?.cancel()
        ackCheckTask = nil

        // Collect all undelivered entries
        let pendingCodes = pendingAcks.filter { _, tracking in
            !tracking.isDelivered
        }.keys

        for ackCode in pendingCodes {
            if let tracking = pendingAcks.removeValue(forKey: ackCode) {
                try await dataStore.updateMessageStatus(id: tracking.messageID, status: .failed)
                logger.warning("Message failed - ack: \(ackCode), BLE disconnected")

                // Handler is called after updating pendingAcks to ensure consistent state
                // if handler triggers re-entrant calls to MessageService
                await messageFailedHandler?(tracking.messageID)
            }
        }
    }

    /// Cleans up old delivered ACK tracking entries.
    /// Called periodically to prevent memory growth.
    public func cleanupDeliveredAcks() {
        let now = Date()

        // Remove delivered entries past their grace period
        let staleDeliveredCodes = pendingAcks.filter { _, tracking in
            tracking.isDelivered &&
            now.timeIntervalSince(tracking.sentAt) > (tracking.timeout + repeatTrackingGracePeriod)
        }.keys

        for ackCode in staleDeliveredCodes {
            pendingAcks.removeValue(forKey: ackCode)
        }
    }

    // MARK: - Periodic ACK Checking

    /// Starts periodic checking for expired ACKs.
    /// - Parameter interval: Check interval in seconds (default: 5.0)
    ///
    /// **Note:** This creates a long-running task. The actor ensures thread safety,
    /// but the task holds a strong reference to self until cancelled.
    public func startAckExpiryChecking(interval: TimeInterval = 5.0) {
        self.checkInterval = interval
        ackCheckTask?.cancel()

        ackCheckTask = Task { [weak self] in
            // CRITICAL: Early exit if actor deallocated
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.checkInterval))
                } catch {
                    // Task was cancelled during sleep
                    break
                }

                // Re-check cancellation after await
                guard !Task.isCancelled else { break }

                // Check for expired ACKs
                try? await self.checkExpiredAcks()

                // Cleanup old delivered entries
                await self.cleanupDeliveredAcks()
            }
        }
    }

    /// Stops the periodic ACK checking.
    public func stopAckExpiryChecking() {
        ackCheckTask?.cancel()
        ackCheckTask = nil
    }

    /// Updates the check interval for future iterations.
    /// Takes effect on the next cycle.
    public func setCheckInterval(_ interval: TimeInterval) {
        self.checkInterval = max(1.0, interval)  // Minimum 1 second
    }

    /// Returns current pending ACK count.
    public var pendingAckCount: Int {
        pendingAcks.count
    }

    /// Returns whether ACK expiry checking is currently active.
    public var isAckExpiryCheckingActive: Bool {
        ackCheckTask != nil
    }

    /// Gets pending ACK info for a message.
    public func getPendingAck(for messageID: UUID) -> PendingAck? {
        pendingAcks.values.first { $0.messageID == messageID }
    }

    // MARK: - ACK Waiting for Retry

    /// Waits for a specific ACK code with timeout using continuations.
    /// Returns true if ACK received, false if timeout.
    /// This is more efficient than polling - provides immediate response when ACK arrives.
    func waitForAck(
        ackCode: UInt32,
        timeout: TimeInterval
    ) async -> Bool {
        // Check if already delivered before waiting
        if let pending = pendingAcks[ackCode], pending.isDelivered {
            return true
        }

        return await withCheckedContinuation { continuation in
            ackContinuations[ackCode] = continuation

            // Spawn timeout task
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self else { return }
                // If continuation still exists, timeout occurred
                if let cont = await self.removeAckContinuation(for: ackCode) {
                    cont.resume(returning: false)
                }
            }
        }
    }

    /// Removes and returns the continuation for an ACK code.
    private func removeAckContinuation(for ackCode: UInt32) -> CheckedContinuation<Bool, Never>? {
        ackContinuations.removeValue(forKey: ackCode)
    }

    // MARK: - Private Helpers

    private func sendTextMessageAttempt(
        text: String,
        recipientKeyPrefix: Data,
        textType: TextType,
        attempt: UInt8,
        timestamp: UInt32
    ) async throws -> SentResponse {
        let frameData = FrameCodec.encodeSendTextMessage(
            textType: textType,
            attempt: attempt,
            timestamp: timestamp,
            recipientKeyPrefix: recipientKeyPrefix,
            text: text
        )

        guard let response = try await bleTransport.send(frameData),
              !response.isEmpty else {
            throw MessageServiceError.sendFailed("No response received")
        }

        // Check for error response
        if response[0] == ResponseCode.error.rawValue {
            if response.count >= 2, let error = ProtocolError(rawValue: response[1]) {
                throw MessageServiceError.protocolError(error)
            }
            throw MessageServiceError.sendFailed("Unknown protocol error")
        }

        // Decode sent response
        return try FrameCodec.decodeSentResponse(from: response)
    }

    private func trackPendingAck(messageID: UUID, ackCode: UInt32, timeout: TimeInterval) {
        let pending = PendingAck(
            messageID: messageID,
            ackCode: ackCode,
            sentAt: Date(),
            timeout: timeout
        )
        pendingAcks[ackCode] = pending
    }

    /// Track a pending ACK that is managed by the retry loop (not by checkExpiredAcks).
    private func trackPendingAckForRetry(messageID: UUID, ackCode: UInt32, timeout: TimeInterval) {
        let pending = PendingAck(
            messageID: messageID,
            ackCode: ackCode,
            sentAt: Date(),
            timeout: timeout,
            isRetryManaged: true
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
