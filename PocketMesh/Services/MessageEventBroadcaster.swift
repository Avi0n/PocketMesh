import Foundation
import PocketMeshKit
import OSLog

/// Events broadcast when messages arrive or status changes
public enum MessageEvent: Sendable, Equatable {
    case directMessageReceived(message: MessageDTO, contact: ContactDTO)
    case channelMessageReceived(message: MessageDTO, channelIndex: UInt8)
    case roomMessageReceived(message: RoomMessageDTO, sessionID: UUID)
    case messageStatusUpdated(ackCode: UInt32)
    case messageFailed(messageID: UUID)
    case messageRetrying(messageID: UUID, attempt: Int, maxAttempts: Int)
    case routingChanged(contactID: UUID, isFlood: Bool)
    case unknownSender(keyPrefix: Data)
    case error(String)
}

/// Broadcasts message events from MessagePollingService to SwiftUI views.
/// This bridges actor isolation to @MainActor context.
@Observable
@MainActor
public final class MessageEventBroadcaster: MessagePollingDelegate {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "MessageEventBroadcaster")

    /// Latest received message (for simple observation)
    var latestMessage: MessageDTO?

    /// Latest event for reactive updates
    var latestEvent: MessageEvent?

    /// Count of new messages (triggers view updates)
    var newMessageCount: Int = 0

    /// Triggers conversation list refresh (increment to force reload)
    /// Use this for state changes like mark-as-read, not for new messages
    var conversationRefreshTrigger: Int = 0

    /// Trigger for contact list refresh (increment to force refresh)
    var contactsRefreshTrigger: Int = 0

    /// Reference to notification service for posting notifications
    var notificationService: NotificationService?

    /// Channel name lookup function (set by AppState)
    var channelNameLookup: ((_ deviceID: UUID, _ channelIndex: UInt8) async -> String?)?

    /// Reference to message service for handling send confirmations
    var messageService: MessageService?

    /// Reference to remote node service for handling login results
    var remoteNodeService: RemoteNodeService?

    /// Reference to data store for resolving public key prefixes
    var dataStore: DataStore?

    /// Reference to room server service for handling room messages
    var roomServerService: RoomServerService?

    /// Reference to binary protocol service for handling binary responses
    var binaryProtocolService: BinaryProtocolService?

    /// Reference to repeater admin service for telemetry and CLI handling
    var repeaterAdminService: RepeaterAdminService?

    // MARK: - Initialization

    public init() {}

    // MARK: - MessagePollingDelegate

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveDirectMessage message: MessageDTO,
        from contact: ContactDTO
    ) async {
        // Update state on MainActor
        await MainActor.run {
            self.latestMessage = message
            self.latestEvent = .directMessageReceived(message: message, contact: contact)
            self.newMessageCount += 1
        }

        // Post notification directly (NotificationService is @MainActor)
        await notificationService?.postDirectMessageNotification(
            from: contact.displayName,
            contactID: contact.id,
            messageText: message.text,
            messageID: message.id
        )
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveChannelMessage message: MessageDTO,
        channelIndex: UInt8
    ) async {
        // All operations on MainActor, but properly awaited (no nested Task)
        await handleChannelMessage(message, channelIndex: channelIndex)
    }

    /// Helper to handle channel message on MainActor (enables proper async/await)
    @MainActor
    private func handleChannelMessage(_ message: MessageDTO, channelIndex: UInt8) async {
        // Update state
        self.latestEvent = .channelMessageReceived(message: message, channelIndex: channelIndex)
        self.newMessageCount += 1

        // Resolve channel name and post notification directly (no Task wrapper)
        let channelName = await channelNameLookup?(message.deviceID, channelIndex) ?? "Channel \(channelIndex)"
        await notificationService?.postChannelMessageNotification(
            channelName: channelName,
            channelIndex: channelIndex,
            deviceID: message.deviceID,
            senderName: message.senderNodeName,
            messageText: message.text,
            messageID: message.id
        )
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveUnknownSender keyPrefix: Data
    ) async {
        await MainActor.run {
            self.latestEvent = .unknownSender(keyPrefix: keyPrefix)
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didEncounterError error: MessagePollingError
    ) async {
        await MainActor.run {
            self.latestEvent = .error(error.localizedDescription)
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveSendConfirmation confirmation: SendConfirmation
    ) async {
        // Access messageService on MainActor then call into the actor
        let msgService = await MainActor.run { self.messageService }

        guard let msgService else {
            await MainActor.run {
                self.logger.warning("Received send confirmation but MessageService not ready - ack: \(confirmation.ackCode)")
            }
            return
        }

        do {
            try await msgService.handleSendConfirmation(confirmation)

            // Notify views of status update so they refresh
            await MainActor.run {
                self.latestEvent = .messageStatusUpdated(ackCode: confirmation.ackCode)
                self.newMessageCount += 1
            }
        } catch {
            await MainActor.run {
                self.logger.error("Failed to handle send confirmation: \(error)")
            }
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveStatusResponse status: RemoteNodeStatus
    ) async {
        let adminService = await MainActor.run { self.repeaterAdminService }
        // Use actor method invocation instead of direct property access
        await adminService?.invokeStatusHandler(status)

        let prefixHex = status.publicKeyPrefix.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
            self.logger.info("Received status response from node: \(prefixHex)")
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveLoginResult result: LoginResult,
        fromPublicKeyPrefix: Data
    ) async {
        await MainActor.run {
            self.logger.debug("Received login result from node: \(fromPublicKeyPrefix.map { String(format: "%02x", $0) }.joined()), success: \(result.success)")
        }

        let nodeService = await MainActor.run { self.remoteNodeService }

        guard let nodeService else {
            await MainActor.run {
                self.logger.warning("Cannot handle login result - RemoteNodeService not configured")
            }
            return
        }

        // Forward to RemoteNodeService using the 6-byte prefix directly
        // No contact lookup needed - RemoteNodeService keys pending logins by prefix
        await nodeService.handleLoginResult(result, fromPublicKeyPrefix: fromPublicKeyPrefix)
    }

    /// Called when a message fails due to ACK timeout
    func handleMessageFailed(messageID: UUID) {
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

    /// Handles contact update notification from AdvertisementService
    func handleContactsUpdated() {
        contactsRefreshTrigger += 1
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveRoomMessage frame: MessageFrame,
        fromRoom contact: ContactDTO
    ) async {
        let (roomService, notifService) = await MainActor.run {
            (self.roomServerService, self.notificationService)
        }

        guard let roomService else {
            await MainActor.run {
                self.logger.warning("Room message received but RoomServerService not configured")
            }
            return
        }

        guard let authorPrefix = frame.extraData, authorPrefix.count >= 4 else {
            await MainActor.run {
                self.logger.warning("Room message missing author prefix")
            }
            return
        }

        do {
            if let messageDTO = try await roomService.handleIncomingMessage(
                senderPublicKeyPrefix: frame.senderPublicKeyPrefix,
                timestamp: frame.timestamp,
                authorPrefix: Data(authorPrefix.prefix(4)),
                text: frame.text
            ) {
                // Post notification for backgrounded app
                await notifService?.postRoomMessageNotification(
                    roomName: contact.displayName,
                    senderName: messageDTO.authorName,
                    messageText: messageDTO.text,
                    messageID: messageDTO.id
                )

                // Broadcast event for UI updates
                await MainActor.run {
                    self.latestEvent = .roomMessageReceived(message: messageDTO, sessionID: messageDTO.sessionID)
                    self.newMessageCount += 1
                }
            }
        } catch {
            await MainActor.run {
                self.logger.error("Failed to handle room message: \(error)")
            }
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveBinaryResponse data: Data
    ) async {
        let binaryService = await MainActor.run { self.binaryProtocolService }
        guard let binaryService else { return }

        await binaryService.processBinaryResponse(data)
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveTelemetryResponse response: TelemetryResponse
    ) async {
        let adminService = await MainActor.run { self.repeaterAdminService }
        // Use actor method invocation instead of direct property access
        await adminService?.invokeTelemetryHandler(response)
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveCLIResponse frame: MessageFrame,
        fromContact contact: ContactDTO
    ) async {
        let adminService = await MainActor.run { self.repeaterAdminService }
        // Route CLI responses to RepeaterAdminService for ViewModel handling
        await adminService?.invokeCLIHandler(frame, fromContact: contact)
    }
}
