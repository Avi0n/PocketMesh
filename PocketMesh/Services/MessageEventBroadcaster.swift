import Foundation
import PocketMeshServices
import OSLog

/// Events broadcast when messages arrive or status changes
public enum MessageEvent: Sendable, Equatable {
    case directMessageReceived(message: MessageDTO, contact: ContactDTO)
    case channelMessageReceived(message: MessageDTO, channelIndex: UInt8)
    case roomMessageReceived(message: RoomMessageDTO, sessionID: UUID)
    case messageStatusUpdated(ackCode: UInt32)
    case messageFailed(messageID: UUID)
    case messageRetrying(messageID: UUID, attempt: Int, maxAttempts: Int)
    case heardRepeatRecorded(messageID: UUID, count: Int)
    case routingChanged(contactID: UUID, isFlood: Bool)
    case linkPreviewUpdated(messageID: UUID)
    case unknownSender(keyPrefix: Data)
    case error(String)
}

/// Broadcasts message events to SwiftUI views.
/// This bridges service layer callbacks to @MainActor context.
@Observable
@MainActor
public final class MessageEventBroadcaster {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "MessageEventBroadcaster")

    /// Latest received message (for simple observation)
    var latestMessage: MessageDTO?

    /// Latest event for reactive updates
    var latestEvent: MessageEvent?

    /// Count of new messages (triggers view updates)
    var newMessageCount: Int = 0

    /// Reference to message service for handling send confirmations
    var messageService: MessageService?

    /// Reference to remote node service for handling login results
    var remoteNodeService: RemoteNodeService?

    /// Reference to data store for resolving public key prefixes
    var dataStore: PersistenceStore?

    /// Reference to room server service for handling room messages
    var roomServerService: RoomServerService?

    /// Reference to binary protocol service for handling binary responses
    var binaryProtocolService: BinaryProtocolService?

    /// Reference to repeater admin service for telemetry and CLI handling
    var repeaterAdminService: RepeaterAdminService?

    // MARK: - Initialization

    public init() {}

    // MARK: - Direct Message Handling

    /// Handle incoming direct message (called from SyncCoordinator callback)
    func handleDirectMessage(_ message: MessageDTO, from contact: ContactDTO) {
        logger.info("dispatch: directMessageReceived from \(contact.displayName)")
        self.latestMessage = message
        self.latestEvent = .directMessageReceived(message: message, contact: contact)
        self.newMessageCount += 1
    }

    // MARK: - Channel Message Handling

    /// Handle incoming channel message (called from SyncCoordinator callback)
    func handleChannelMessage(_ message: MessageDTO, channelIndex: UInt8) {
        logger.info("dispatch: channelMessageReceived on channel \(channelIndex)")
        self.latestEvent = .channelMessageReceived(message: message, channelIndex: channelIndex)
        self.newMessageCount += 1
    }

    // MARK: - Room Message Handling

    /// Handle incoming room message (called from SyncCoordinator callback)
    func handleRoomMessage(_ message: RoomMessageDTO) {
        logger.info("dispatch: roomMessageReceived for session \(message.sessionID)")
        self.latestEvent = .roomMessageReceived(message: message, sessionID: message.sessionID)
        self.newMessageCount += 1
    }

    // MARK: - Status Event Handlers

    /// Handle acknowledgement/status update
    func handleAcknowledgement(ackCode: UInt32) {
        self.latestEvent = .messageStatusUpdated(ackCode: ackCode)
        self.newMessageCount += 1
    }

    /// Called when a message fails due to ACK timeout
    func handleMessageFailed(messageID: UUID) {
        logger.info("dispatch: messageFailed for \(messageID)")
        self.latestEvent = .messageFailed(messageID: messageID)
        self.newMessageCount += 1
    }

    /// Called when a message enters retry state
    func handleMessageRetrying(messageID: UUID, attempt: Int, maxAttempts: Int) {
        self.latestEvent = .messageRetrying(messageID: messageID, attempt: attempt, maxAttempts: maxAttempts)
        self.newMessageCount += 1
    }

    /// Called when contact routing changes (e.g., direct -> flood)
    func handleRoutingChanged(contactID: UUID, isFlood: Bool) {
        logger.info("handleRoutingChanged called - contactID: \(contactID), isFlood: \(isFlood)")
        self.latestEvent = .routingChanged(contactID: contactID, isFlood: isFlood)
        self.newMessageCount += 1
    }

    /// Called when a heard repeat is recorded for a sent channel message
    func handleHeardRepeatRecorded(messageID: UUID, count: Int) {
        self.latestEvent = .heardRepeatRecorded(messageID: messageID, count: count)
        self.newMessageCount += 1
    }

    /// Called when a link preview is fetched and persisted for a message
    func handleLinkPreviewUpdated(messageID: UUID) {
        self.latestEvent = .linkPreviewUpdated(messageID: messageID)
        self.newMessageCount += 1
    }

    // MARK: - Other Event Handlers

    /// Handle unknown sender notification
    func handleUnknownSender(keyPrefix: Data) {
        self.latestEvent = .unknownSender(keyPrefix: keyPrefix)
    }

    /// Handle error notification
    func handleError(_ message: String) {
        self.latestEvent = .error(message)
    }

    // MARK: - Status Response Handling

    /// Handle status response from remote node
    func handleStatusResponse(_ status: StatusResponse) async {
        await repeaterAdminService?.invokeStatusHandler(status)

        let prefixHex = status.publicKeyPrefix.map { String(format: "%02x", $0) }.joined()
        logger.info("Received status response from node: \(prefixHex)")
    }

    // Note: Login results and binary responses are handled internally by
    // PocketMeshServices via MeshCore event monitoring. No external handlers needed.

    /// Handle telemetry response
    func handleTelemetryResponse(_ response: TelemetryResponse) async {
        await repeaterAdminService?.invokeTelemetryHandler(response)
    }

    /// Handle CLI response
    func handleCLIResponse(_ message: ContactMessage, fromContact contact: ContactDTO) async {
        await repeaterAdminService?.invokeCLIHandler(message, fromContact: contact)
    }
}
