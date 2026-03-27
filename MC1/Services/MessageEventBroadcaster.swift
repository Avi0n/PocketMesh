import Foundation
import MC1Services
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
    case reactionReceived(messageID: UUID, summary: String)
    case routingChanged(contactID: UUID, isFlood: Bool)
    case roomMessageStatusUpdated(messageID: UUID)
    case roomMessageFailed(messageID: UUID)
    case unknownSender(keyPrefix: Data)
    case error(String)
}

/// Broadcasts message events to SwiftUI views.
/// This bridges service layer callbacks to @MainActor context.
@Observable
@MainActor
public final class MessageEventBroadcaster {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.mc1", category: "MessageEventBroadcaster")

    /// Latest received message (for simple observation)
    var latestMessage: MessageDTO?

    /// Sequence-numbered event log for per-view cursor consumption via `events(after:)`
    @ObservationIgnored private var eventLog: [(sequence: Int, event: MessageEvent)] = []

    /// Next sequence number to assign
    @ObservationIgnored private var nextSequence = 0

    /// Current sequence number. Views use this to initialize their cursor.
    var currentEventSequence: Int { nextSequence }

    /// Count of new messages (triggers view updates)
    var newMessageCount: Int = 0

    /// Count of session state changes (triggers view updates for connection status)
    var sessionStateChangeCount: Int = 0

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

    // MARK: - Initialization

    public init() {}

    // MARK: - Event Queue

    /// Return events after the given cursor.
    /// Each view maintains its own cursor so multiple views can consume independently.
    func events(after cursor: Int) -> (events: [MessageEvent], newCursor: Int, droppedEvents: Bool) {
        let oldestSequence = eventLog.first?.sequence ?? nextSequence
        let dropped = cursor < oldestSequence
        let result = eventLog.lazy.drop { $0.sequence < cursor }.map(\.event)
        return (Array(result), nextSequence, dropped)
    }

    /// Append an event to the log, pruning old entries to cap memory.
    private func enqueue(_ event: MessageEvent) {
        eventLog.append((nextSequence, event))
        nextSequence += 1
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
    }

    // MARK: - Direct Message Handling

    /// Handle incoming direct message (called from SyncCoordinator callback)
    func handleDirectMessage(_ message: MessageDTO, from contact: ContactDTO) {
        logger.info("dispatch: directMessageReceived from \(contact.displayName)")
        self.latestMessage = message
        self.enqueue(.directMessageReceived(message: message, contact: contact))
        self.newMessageCount += 1
    }

    // MARK: - Channel Message Handling

    /// Handle incoming channel message (called from SyncCoordinator callback)
    func handleChannelMessage(_ message: MessageDTO, channelIndex: UInt8) {
        logger.info("dispatch: channelMessageReceived on channel \(channelIndex)")
        self.enqueue(.channelMessageReceived(message: message, channelIndex: channelIndex))
        self.newMessageCount += 1
    }

    // MARK: - Room Message Handling

    /// Handle incoming room message (called from SyncCoordinator callback)
    func handleRoomMessage(_ message: RoomMessageDTO) {
        logger.info("dispatch: roomMessageReceived for session \(message.sessionID)")
        self.enqueue(.roomMessageReceived(message: message, sessionID: message.sessionID))
        self.newMessageCount += 1
    }

    /// Handle room message status update
    func handleRoomMessageStatusUpdated(messageID: UUID) {
        logger.info("dispatch: roomMessageStatusUpdated for \(messageID)")
        self.enqueue(.roomMessageStatusUpdated(messageID: messageID))
        self.newMessageCount += 1
    }

    /// Handle room message delivery failure
    func handleRoomMessageFailed(messageID: UUID) {
        logger.info("dispatch: roomMessageFailed for \(messageID)")
        self.enqueue(.roomMessageFailed(messageID: messageID))
        self.newMessageCount += 1
    }

    // MARK: - Status Event Handlers

    /// Handle acknowledgement/status update
    func handleAcknowledgement(ackCode: UInt32) {
        self.enqueue(.messageStatusUpdated(ackCode: ackCode))
        self.newMessageCount += 1
    }

    /// Called when a message fails due to ACK timeout
    func handleMessageFailed(messageID: UUID) {
        logger.info("dispatch: messageFailed for \(messageID)")
        self.enqueue(.messageFailed(messageID: messageID))
        self.newMessageCount += 1
    }

    /// Called when a message enters retry state
    func handleMessageRetrying(messageID: UUID, attempt: Int, maxAttempts: Int) {
        self.enqueue(.messageRetrying(messageID: messageID, attempt: attempt, maxAttempts: maxAttempts))
        self.newMessageCount += 1
    }

    /// Called when contact routing changes (e.g., direct -> flood)
    func handleRoutingChanged(contactID: UUID, isFlood: Bool) {
        logger.info("handleRoutingChanged called - contactID: \(contactID), isFlood: \(isFlood)")
        self.enqueue(.routingChanged(contactID: contactID, isFlood: isFlood))
        self.newMessageCount += 1
    }

    /// Called when a heard repeat is recorded for a sent channel message
    func handleHeardRepeatRecorded(messageID: UUID, count: Int) {
        self.enqueue(.heardRepeatRecorded(messageID: messageID, count: count))
        self.newMessageCount += 1
    }

    /// Called when a reaction is received for a channel message
    func handleReactionReceived(messageID: UUID, summary: String) {
        self.enqueue(.reactionReceived(messageID: messageID, summary: summary))
        self.newMessageCount += 1
    }

    // MARK: - Other Event Handlers

    /// Handle unknown sender notification
    func handleUnknownSender(keyPrefix: Data) {
        self.enqueue(.unknownSender(keyPrefix: keyPrefix))
    }

    /// Handle error notification
    func handleError(_ message: String) {
        self.enqueue(.error(message))
    }

    /// Handle session connection state change
    func handleSessionStateChanged(sessionID: UUID, isConnected: Bool) {
        logger.info("dispatch: sessionStateChanged for \(sessionID), isConnected: \(isConnected)")
        self.sessionStateChangeCount += 1
    }

    // MARK: - Service Wiring

    /// Wire all service callbacks for message event handling.
    /// Call this once when services become available after connection.
    func wireServices(
        _ services: ServiceContainer,
        onConversationsChanged: @escaping @MainActor () -> Void,
        onReactionReceived: @escaping @Sendable (UUID) async -> Void
    ) async {
        // Assign service references
        messageService = services.messageService
        remoteNodeService = services.remoteNodeService
        dataStore = services.dataStore
        roomServerService = services.roomServerService
        binaryProtocolService = services.binaryProtocolService

        // Wire message event callbacks for real-time chat updates
        await services.syncCoordinator.setMessageEventCallbacks(
            onDirectMessageReceived: { [weak self] message, contact in
                await self?.handleDirectMessage(message, from: contact)
            },
            onChannelMessageReceived: { [weak self] message, channelIndex in
                await self?.handleChannelMessage(message, channelIndex: channelIndex)
            },
            onRoomMessageReceived: { [weak self] message in
                await self?.handleRoomMessage(message)
            },
            onReactionReceived: { [weak self] messageID, summary in
                await self?.handleReactionReceived(messageID: messageID, summary: summary)
                await onReactionReceived(messageID)
            }
        )

        // Wire heard repeat callback for UI updates when repeats are recorded
        await services.heardRepeatsService.setRepeatRecordedHandler { [weak self] messageID, count in
            await MainActor.run {
                self?.handleHeardRepeatRecorded(messageID: messageID, count: count)
            }
        }

        // Wire session state change handler for room connection status UI updates
        await services.remoteNodeService.setSessionStateChangedHandler { [weak self] sessionID, isConnected in
            await MainActor.run {
                onConversationsChanged()
                self?.handleSessionStateChanged(sessionID: sessionID, isConnected: isConnected)
            }
        }

        // Wire room connection recovery handler
        await services.roomServerService.setConnectionRecoveryHandler { [weak self] sessionID in
            await MainActor.run {
                onConversationsChanged()
                self?.handleSessionStateChanged(sessionID: sessionID, isConnected: true)
            }
        }

        // Wire room message status handler for delivery confirmation UI updates
        await services.roomServerService.setStatusUpdateHandler { [weak self] messageID, status in
            await MainActor.run {
                if status == .failed {
                    self?.handleRoomMessageFailed(messageID: messageID)
                } else {
                    self?.handleRoomMessageStatusUpdated(messageID: messageID)
                }
            }
        }

        // Wire ACK confirmation handler to trigger UI refresh on delivery
        await services.messageService.setAckConfirmationHandler { [weak self] ackCode, _ in
            Task { @MainActor in
                self?.handleAcknowledgement(ackCode: ackCode)
            }
        }

        // Wire retry status events from MessageService
        await services.messageService.setRetryStatusHandler { [weak self] messageID, attempt, maxAttempts in
            await MainActor.run {
                self?.handleMessageRetrying(
                    messageID: messageID,
                    attempt: attempt,
                    maxAttempts: maxAttempts
                )
            }
        }

        // Wire routing change events from MessageService
        await services.messageService.setRoutingChangedHandler { [weak self] contactID, isFlood in
            await MainActor.run {
                self?.handleRoutingChanged(
                    contactID: contactID,
                    isFlood: isFlood
                )
            }
        }

        // Wire message failure handler
        await services.messageService.setMessageFailedHandler { [weak self] messageID in
            await MainActor.run {
                self?.handleMessageFailed(messageID: messageID)
            }
        }
    }

}
