import Foundation

// MARK: - Message Service Errors

public enum MessageServiceError: Error, Sendable {
    case notConnected
    case contactNotFound
    case channelNotFound
    case sendFailed(String)
    case maxRetriesExceeded
    case invalidRecipient
    case messageTooLong
    case protocolError(ProtocolError)
}

// MARK: - Message Send Result

public struct MessageSendResult: Sendable, Equatable {
    public let messageID: UUID
    public let ackCode: UInt32
    public let isFlood: Bool
    public let estimatedTimeout: UInt32
    public let attemptCount: UInt8

    public init(messageID: UUID, ackCode: UInt32, isFlood: Bool, estimatedTimeout: UInt32, attemptCount: UInt8) {
        self.messageID = messageID
        self.ackCode = ackCode
        self.isFlood = isFlood
        self.estimatedTimeout = estimatedTimeout
        self.attemptCount = attemptCount
    }
}

// MARK: - Message Service Configuration

public struct MessageServiceConfig: Sendable {
    public let maxRetries: UInt8
    public let initialRetryDelay: TimeInterval
    public let maxRetryDelay: TimeInterval
    public let retryBackoffMultiplier: Double
    public let floodFallbackEnabled: Bool

    public init(
        maxRetries: UInt8 = 3,
        initialRetryDelay: TimeInterval = 1.0,
        maxRetryDelay: TimeInterval = 8.0,
        retryBackoffMultiplier: Double = 2.0,
        floodFallbackEnabled: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.initialRetryDelay = initialRetryDelay
        self.maxRetryDelay = maxRetryDelay
        self.retryBackoffMultiplier = retryBackoffMultiplier
        self.floodFallbackEnabled = floodFallbackEnabled
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

    public init(messageID: UUID, ackCode: UInt32, sentAt: Date, timeout: TimeInterval) {
        self.messageID = messageID
        self.ackCode = ackCode
        self.sentAt = sentAt
        self.timeout = timeout
    }

    public var isExpired: Bool {
        Date().timeIntervalSince(sentAt) > timeout
    }
}

// MARK: - Message Service Actor

/// Actor-isolated service for sending messages with retry logic and ACK tracking.
public actor MessageService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private let dataStore: DataStore
    private let config: MessageServiceConfig

    /// Currently tracked pending ACKs
    private var pendingAcks: [UInt32: PendingAck] = [:]

    /// ACK confirmation callback
    private var ackConfirmationHandler: (@Sendable (UInt32, UInt32) -> Void)?

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

    // MARK: - Send Direct Message

    /// Sends a direct message to a contact with retry logic.
    /// - Parameters:
    ///   - text: The message text
    ///   - contact: The recipient contact
    ///   - textType: The text type (default: plain)
    ///   - replyToID: Optional message ID to reply to
    /// - Returns: The send result with ACK code and tracking info
    public func sendDirectMessage(
        text: String,
        to contact: ContactDTO,
        textType: TextType = .plain,
        replyToID: UUID? = nil
    ) async throws -> MessageSendResult {
        // Validate message length
        guard text.utf8.count <= ProtocolLimits.maxMessageLength else {
            throw MessageServiceError.messageTooLong
        }

        // Check connection state
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw MessageServiceError.notConnected
        }

        let messageID = UUID()
        let timestamp = UInt32(Date().timeIntervalSince1970)

        // Save message to store as pending
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

        // Attempt to send with retries
        var attemptCount: UInt8 = 0
        var useFlood = contact.isFloodRouted

        for attempt in 1...Int(config.maxRetries) {
            attemptCount = UInt8(attempt)

            do {
                let result = try await sendTextMessageAttempt(
                    text: text,
                    recipientKeyPrefix: contact.publicKeyPrefix,
                    textType: textType,
                    attempt: attemptCount,
                    timestamp: timestamp
                )

                // Update message with ACK code
                try await dataStore.updateMessageAck(
                    id: messageID,
                    ackCode: result.ackCode,
                    status: .sent
                )

                // Track pending ACK for confirmation
                let timeout = TimeInterval(result.estimatedTimeout) / 1000.0
                trackPendingAck(messageID: messageID, ackCode: result.ackCode, timeout: timeout)

                // Update contact's last message date
                try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())

                return MessageSendResult(
                    messageID: messageID,
                    ackCode: result.ackCode,
                    isFlood: result.isFlood,
                    estimatedTimeout: result.estimatedTimeout,
                    attemptCount: attemptCount
                )
            } catch {
                // If not flood and flood fallback enabled, try flood on last attempt
                if !useFlood && config.floodFallbackEnabled && attempt == Int(config.maxRetries) - 1 {
                    useFlood = true
                }

                // Wait before retrying with exponential backoff
                if attempt < Int(config.maxRetries) {
                    let delay = calculateRetryDelay(attempt: attempt)
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        // Mark message as failed after all retries exhausted
        try await dataStore.updateMessageStatus(id: messageID, status: .failed)

        throw MessageServiceError.maxRetriesExceeded
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
    public func handleSendConfirmation(_ confirmation: SendConfirmation) async throws {
        guard pendingAcks.removeValue(forKey: confirmation.ackCode) != nil else {
            return
        }

        // Update message to delivered status
        try await dataStore.updateMessageByAckCode(
            confirmation.ackCode,
            status: .delivered,
            roundTripTime: confirmation.roundTripTime
        )

        // Notify handler
        ackConfirmationHandler?(confirmation.ackCode, confirmation.roundTripTime)
    }

    /// Sets a callback for ACK confirmations.
    public func setAckConfirmationHandler(_ handler: @escaping @Sendable (UInt32, UInt32) -> Void) {
        ackConfirmationHandler = handler
    }

    /// Checks for expired ACKs and marks their messages as failed.
    public func checkExpiredAcks() async throws {
        let now = Date()
        var expiredCodes: [UInt32] = []

        for (code, pending) in pendingAcks {
            if now.timeIntervalSince(pending.sentAt) > pending.timeout {
                expiredCodes.append(code)
            }
        }

        for code in expiredCodes {
            if let pending = pendingAcks.removeValue(forKey: code) {
                try await dataStore.updateMessageStatus(id: pending.messageID, status: .failed)
            }
        }
    }

    /// Returns current pending ACK count.
    public var pendingAckCount: Int {
        pendingAcks.count
    }

    /// Gets pending ACK info for a message.
    public func getPendingAck(for messageID: UUID) -> PendingAck? {
        pendingAcks.values.first { $0.messageID == messageID }
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

    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let delay = config.initialRetryDelay * pow(config.retryBackoffMultiplier, Double(attempt - 1))
        return min(delay, config.maxRetryDelay)
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
