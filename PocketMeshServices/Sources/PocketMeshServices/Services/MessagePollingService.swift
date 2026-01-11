import Foundation
import MeshCore
import os

// MARK: - Message Polling Errors

public enum MessagePollingError: Error, Sendable {
    case notConnected
    case pollingFailed
    case sessionError(MeshCoreError)
}

// MARK: - Message Polling Service

/// Service for polling messages from the mesh device.
/// Handles automatic message fetching and contact message routing.
public actor MessagePollingService {

    // MARK: - Properties

    private let session: MeshCoreSession
    private let dataStore: PersistenceStore
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "MessagePolling")

    /// Handler for incoming contact messages
    private var contactMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Handler for incoming channel messages
    private var channelMessageHandler: (@Sendable (ChannelMessage, ChannelDTO?) async -> Void)?

    /// Handler for signed messages (from room servers)
    private var signedMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Handler for CLI responses (textType = 0x01)
    private var cliMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Handler for acknowledgements (message delivery confirmations)
    private var acknowledgementHandler: (@Sendable (Data) async -> Void)?

    /// Event monitoring task
    private var eventMonitorTask: Task<Void, Never>?

    /// Whether auto-fetch is currently enabled
    private var isAutoFetchEnabled = false

    /// Device ID for contact lookups
    private var currentDeviceID: UUID?

    /// Count of message handlers currently executing
    /// Used to wait for sync-time handlers to complete before resuming notifications
    private var pendingHandlerCount: Int = 0

    // MARK: - Initialization

    public init(session: MeshCoreSession, dataStore: PersistenceStore) {
        self.session = session
        self.dataStore = dataStore
    }

    deinit {
        eventMonitorTask?.cancel()
    }

    // MARK: - Event Handlers

    /// Set handler for incoming contact messages
    public func setContactMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        contactMessageHandler = handler
    }

    /// Set handler for incoming channel messages
    public func setChannelMessageHandler(_ handler: @escaping @Sendable (ChannelMessage, ChannelDTO?) async -> Void) {
        channelMessageHandler = handler
    }

    /// Set handler for signed messages (from room servers)
    public func setSignedMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        signedMessageHandler = handler
    }

    /// Set handler for CLI responses (textType = 0x01)
    public func setCLIMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        cliMessageHandler = handler
    }

    /// Set handler for acknowledgements
    public func setAcknowledgementHandler(_ handler: @escaping @Sendable (Data) async -> Void) {
        acknowledgementHandler = handler
    }

    // MARK: - Auto-Fetch Control

    /// Start automatic message fetching for a device.
    /// This enables the session's auto-fetch feature and monitors for incoming messages.
    /// - Parameter deviceID: The device ID for contact lookups
    public func startAutoFetch(deviceID: UUID) async {
        guard !isAutoFetchEnabled else { return }

        currentDeviceID = deviceID
        isAutoFetchEnabled = true

        startEventMonitoring()
        await session.startAutoMessageFetching()

        logger.info("Auto-fetch started for device \(deviceID)")
    }

    /// Stop automatic message fetching
    public func stopAutoFetch() async {
        guard isAutoFetchEnabled else { return }

        isAutoFetchEnabled = false

        // Stop session-level auto-fetch
        await session.stopAutoMessageFetching()

        // Stop event monitoring
        stopEventMonitoring()

        logger.info("Auto-fetch stopped")
    }

    /// Check if auto-fetch is currently enabled
    public var isAutoFetching: Bool {
        isAutoFetchEnabled
    }

    // MARK: - Manual Polling

    /// Manually poll for one message from the device.
    /// - Returns: The message result (contact message, channel message, or no more messages)
    public func pollMessage() async throws -> MessageResult {
        do {
            return try await session.getMessage()
        } catch let error as MeshCoreError {
            throw MessagePollingError.sessionError(error)
        }
    }

    /// Poll all waiting messages from the device.
    /// - Returns: Count of messages retrieved
    public func pollAllMessages() async throws -> Int {
        var count = 0

        while true {
            let result = try await pollMessage()
            switch result {
            case .contactMessage, .channelMessage:
                count += 1
            case .noMoreMessages:
                return count
            }
        }
    }

    /// Wait for all pending message handlers to complete.
    /// Call this after pollAllMessages() to ensure all messages are fully processed
    /// before performing actions that depend on completion (like resuming notifications).
    public func waitForPendingHandlers() async {
        // Poll until no handlers are executing
        // The event monitor processes handlers sequentially, so we're waiting for the queue to drain
        while pendingHandlerCount > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Event Monitoring

    /// Start monitoring MeshCore events for messages
    private func startEventMonitoring() {
        eventMonitorTask?.cancel()

        eventMonitorTask = Task { [weak self] in
            guard let self else { return }
            let events = await session.events()

            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handleEvent(event)
            }
        }
    }

    /// Stop monitoring events
    private func stopEventMonitoring() {
        eventMonitorTask?.cancel()
        eventMonitorTask = nil
    }

    /// Handle incoming MeshCore event
    private func handleEvent(_ event: MeshEvent) async {
        switch event {
        case .contactMessageReceived(let message):
            pendingHandlerCount += 1
            defer { pendingHandlerCount -= 1 }
            await handleContactMessage(message)

        case .channelMessageReceived(let message):
            pendingHandlerCount += 1
            defer { pendingHandlerCount -= 1 }
            await handleChannelMessage(message)

        case .acknowledgement(let code, _):
            await acknowledgementHandler?(code)

        default:
            break
        }
    }

    // MARK: - Private Message Handlers

    /// Handle incoming contact message
    private func handleContactMessage(_ message: ContactMessage) async {
        guard let deviceID = currentDeviceID else {
            logger.warning("Received message but no device ID set")
            await contactMessageHandler?(message, nil)
            return
        }

        // Look up the sender contact
        let contact = try? await dataStore.fetchContact(
            deviceID: deviceID,
            publicKeyPrefix: message.senderPublicKeyPrefix
        )

        // Route based on text type
        switch message.textType {
        case MeshTextType.cliData.rawValue:
            // CLI responses from repeaters (textType = 0x01)
            await cliMessageHandler?(message, contact)
        case MeshTextType.signedPlain.rawValue:
            // Signed messages from room servers (textType = 0x02)
            await signedMessageHandler?(message, contact)
        default:
            // Regular contact messages (textType = 0x00 or unknown)
            await contactMessageHandler?(message, contact)
        }
    }

    /// Handle incoming channel message
    private func handleChannelMessage(_ message: ChannelMessage) async {
        guard let deviceID = currentDeviceID else {
            logger.warning("Received channel message but no device ID set")
            await channelMessageHandler?(message, nil)
            return
        }

        // Look up the channel
        let channel = try? await dataStore.fetchChannel(deviceID: deviceID, index: message.channelIndex)

        await channelMessageHandler?(message, channel)
    }
}

// MARK: - MessagePollingServiceProtocol Conformance

extension MessagePollingService: MessagePollingServiceProtocol {
    // Already implements pollAllMessages() -> Int
}

// MARK: - Message Text Type Constants

/// Text type identifiers for mesh messages
public enum MeshTextType: UInt8 {
    case plain = 0x00
    case cliData = 0x01
    case signedPlain = 0x02
}
