import Foundation

// MARK: - Message Polling Service Errors

public enum MessagePollingError: Error, Sendable {
    case notConnected
    case syncFailed(String)
    case parseError(String)
    case deviceNotFound
    case contactNotFound
}

// MARK: - Incoming Message

/// Represents a parsed incoming message ready for storage
public struct IncomingMessage: Sendable, Equatable {
    public let senderKeyPrefix: Data
    public let text: String
    public let timestamp: UInt32
    public let pathLength: UInt8
    public let textType: TextType
    public let snr: Int8?
    public let isChannelMessage: Bool
    public let channelIndex: UInt8?

    public init(
        senderKeyPrefix: Data,
        text: String,
        timestamp: UInt32,
        pathLength: UInt8,
        textType: TextType,
        snr: Int8?,
        isChannelMessage: Bool,
        channelIndex: UInt8?
    ) {
        self.senderKeyPrefix = senderKeyPrefix
        self.text = text
        self.timestamp = timestamp
        self.pathLength = pathLength
        self.textType = textType
        self.snr = snr
        self.isChannelMessage = isChannelMessage
        self.channelIndex = channelIndex
    }
}

// MARK: - Message Polling Delegate

/// Protocol for receiving message polling events
public protocol MessagePollingDelegate: AnyObject, Sendable {
    func messagePollingService(_ service: MessagePollingService, didReceiveDirectMessage message: MessageDTO, from contact: ContactDTO) async
    func messagePollingService(_ service: MessagePollingService, didReceiveChannelMessage message: MessageDTO, channelIndex: UInt8) async
    func messagePollingService(_ service: MessagePollingService, didReceiveUnknownSender keyPrefix: Data) async
    func messagePollingService(_ service: MessagePollingService, didEncounterError error: MessagePollingError) async
    func messagePollingService(_ service: MessagePollingService, didReceiveSendConfirmation confirmation: SendConfirmation) async
}

// MARK: - Message Polling Service Actor

/// Actor-isolated service for polling and processing incoming messages.
/// Handles PUSH_CODE_MSG_WAITING notifications and syncs messages from the device queue.
public actor MessagePollingService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private let dataStore: DataStore
    private weak var delegate: (any MessagePollingDelegate)?

    /// Active device ID for message context
    private var activeDeviceID: UUID?

    /// Whether a sync is currently in progress
    private var isSyncing = false

    /// Count of messages waiting on device (from push notification)
    private var messagesWaiting: Int = 0

    // MARK: - Initialization

    public init(
        bleTransport: any BLETransport,
        dataStore: DataStore
    ) {
        self.bleTransport = bleTransport
        self.dataStore = dataStore
    }

    /// Sets the delegate for receiving message events.
    public func setDelegate(_ delegate: any MessagePollingDelegate) {
        self.delegate = delegate
    }

    /// Sets the active device ID for message context.
    public func setActiveDevice(_ deviceID: UUID) {
        self.activeDeviceID = deviceID
    }

    // MARK: - Push Notification Handling

    /// Called when PUSH_CODE_MSG_WAITING is received from the device.
    /// Triggers a sync of the message queue.
    public func handleMessageWaiting() async {
        messagesWaiting += 1

        // Start sync if not already syncing
        if !isSyncing {
            await syncMessageQueue()
        }
    }

    // MARK: - Message Queue Sync

    /// Syncs all pending messages from the device queue.
    /// Continues until RESP_CODE_NO_MORE_MESSAGES is received.
    public func syncMessageQueue() async {
        guard !isSyncing else { return }

        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            await delegate?.messagePollingService(self, didEncounterError: .notConnected)
            return
        }

        guard let deviceID = activeDeviceID else {
            await delegate?.messagePollingService(self, didEncounterError: .deviceNotFound)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            while true {
                let frameData = FrameCodec.encodeSyncNextMessage()

                guard let response = try await bleTransport.send(frameData),
                      !response.isEmpty else {
                    throw MessagePollingError.syncFailed("No response received")
                }

                // Check response type
                switch response[0] {
                case ResponseCode.noMoreMessages.rawValue:
                    // Queue is empty
                    messagesWaiting = 0
                    return

                case ResponseCode.contactMessageReceivedV3.rawValue:
                    // Direct message (v3 format)
                    try await handleDirectMessageV3(response, deviceID: deviceID)

                case ResponseCode.channelMessageReceivedV3.rawValue:
                    // Channel message (v3 format)
                    try await handleChannelMessageV3(response, deviceID: deviceID)

                case ResponseCode.contactMessageReceived.rawValue:
                    // Legacy direct message (v<3 format) - skip for now
                    continue

                case ResponseCode.channelMessageReceived.rawValue:
                    // Legacy channel message (v<3 format) - skip for now
                    continue

                case ResponseCode.error.rawValue:
                    if response.count >= 2, let error = ProtocolError(rawValue: response[1]) {
                        throw MessagePollingError.syncFailed("Protocol error: \(error)")
                    }
                    throw MessagePollingError.syncFailed("Unknown protocol error")

                default:
                    // Unknown response type
                    continue
                }
            }
        } catch {
            if let pollingError = error as? MessagePollingError {
                await delegate?.messagePollingService(self, didEncounterError: pollingError)
            } else {
                await delegate?.messagePollingService(self, didEncounterError: .syncFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Direct Message Processing

    private func handleDirectMessageV3(_ data: Data, deviceID: UUID) async throws {
        let frame = try FrameCodec.decodeMessageV3(from: data)

        // Look up contact by sender key prefix
        guard let contact = try await dataStore.fetchContact(
            deviceID: deviceID,
            publicKeyPrefix: frame.senderPublicKeyPrefix
        ) else {
            // Unknown sender - notify delegate
            await delegate?.messagePollingService(self, didReceiveUnknownSender: frame.senderPublicKeyPrefix)
            return
        }

        // Create and save message
        let message = Message(
            deviceID: deviceID,
            contactID: contact.id,
            from: frame
        )
        let messageDTO = MessageDTO(from: message)
        try await dataStore.saveMessage(messageDTO)

        // Update contact's last message date and increment unread count
        try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date())
        try await dataStore.incrementUnreadCount(contactID: contact.id)

        // Notify delegate
        await delegate?.messagePollingService(self, didReceiveDirectMessage: messageDTO, from: contact)
    }

    // MARK: - Channel Message Processing

    private func handleChannelMessageV3(_ data: Data, deviceID: UUID) async throws {
        let frame = try FrameCodec.decodeChannelMessageV3(from: data)

        // Create and save message
        let message = Message(deviceID: deviceID, from: frame)
        let messageDTO = MessageDTO(from: message)
        try await dataStore.saveMessage(messageDTO)

        // Update channel's last message date and increment unread count
        if let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: frame.channelIndex) {
            try await dataStore.updateChannelLastMessage(channelID: channel.id, date: Date())
            try await dataStore.incrementChannelUnreadCount(channelID: channel.id)
        }

        // Notify delegate
        await delegate?.messagePollingService(self, didReceiveChannelMessage: messageDTO, channelIndex: frame.channelIndex)
    }

    // MARK: - Push Code Processing

    /// Processes incoming push data from the BLE response handler.
    /// Call this from the BLE service's response handler for push codes.
    public func processPushData(_ data: Data) async throws {
        guard !data.isEmpty else { return }

        switch data[0] {
        case PushCode.messageWaiting.rawValue:
            await handleMessageWaiting()

        case PushCode.sendConfirmed.rawValue:
            // ACK confirmation - route to delegate
            do {
                let confirmation = try FrameCodec.decodeSendConfirmation(from: data)
                await delegate?.messagePollingService(self, didReceiveSendConfirmation: confirmation)
            } catch {
                // Log but don't crash - confirmation may be for message sent before app launch
                print("[MessagePollingService] Failed to decode send confirmation: \(error)")
            }

        case PushCode.advert.rawValue, PushCode.newAdvert.rawValue:
            // Advertisement - handled by AdvertisementService
            break

        case PushCode.pathUpdated.rawValue:
            // Path update - handled by ContactService
            break

        default:
            // Other push codes handled elsewhere
            break
        }
    }

    // MARK: - Status

    /// Returns whether a sync is currently in progress.
    public var isCurrentlySyncing: Bool {
        isSyncing
    }

    /// Returns the count of messages waiting (from push notifications).
    public var waitingMessageCount: Int {
        messagesWaiting
    }
}

// MARK: - Message Parsing Helpers

public extension MessagePollingService {

    /// Parses a direct message frame into an IncomingMessage.
    static func parseDirectMessage(from data: Data) throws -> IncomingMessage {
        let frame = try FrameCodec.decodeMessageV3(from: data)
        return IncomingMessage(
            senderKeyPrefix: frame.senderPublicKeyPrefix,
            text: frame.text,
            timestamp: frame.timestamp,
            pathLength: frame.pathLength,
            textType: frame.textType,
            snr: frame.snr,
            isChannelMessage: false,
            channelIndex: nil
        )
    }

    /// Parses a channel message frame into an IncomingMessage.
    static func parseChannelMessage(from data: Data) throws -> IncomingMessage {
        let frame = try FrameCodec.decodeChannelMessageV3(from: data)
        return IncomingMessage(
            senderKeyPrefix: Data(),
            text: frame.text,
            timestamp: frame.timestamp,
            pathLength: frame.pathLength,
            textType: frame.textType,
            snr: frame.snr,
            isChannelMessage: true,
            channelIndex: frame.channelIndex
        )
    }
}
