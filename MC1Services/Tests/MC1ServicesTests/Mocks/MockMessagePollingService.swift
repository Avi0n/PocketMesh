import Foundation
import MeshCore
@testable import PocketMeshServices

/// Mock implementation of MessagePollingServiceProtocol for testing.
///
/// Configure the mock by setting the stub properties before calling methods.
/// Track method calls by examining the recorded invocations.
public actor MockMessagePollingService: MessagePollingServiceProtocol {

    // MARK: - Stubs

    /// Result to return from pollAllMessages
    public var stubbedPollAllMessagesResult: Result<Int, Error> = .success(0)

    // MARK: - Recorded Invocations

    public private(set) var pollAllMessagesInvocations: Int = 0
    public private(set) var waitForPendingHandlersInvocations: Int = 0

    // MARK: - Initialization

    public init() {}

    // MARK: - Protocol Methods

    public func pollAllMessages() async throws -> Int {
        pollAllMessagesInvocations += 1
        switch stubbedPollAllMessagesResult {
        case .success(let count):
            return count
        case .failure(let error):
            throw error
        }
    }

    public func waitForPendingHandlers(timeout: Duration) async -> Bool {
        waitForPendingHandlersInvocations += 1
        return true
    }

    // MARK: - Captured Handlers

    /// Captured contact message handler (set via setContactMessageHandler)
    public private(set) var capturedContactMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Captured channel message handler (set via setChannelMessageHandler)
    public private(set) var capturedChannelMessageHandler: (@Sendable (ChannelMessage, ChannelDTO?) async -> Void)?

    /// Captured signed message handler (set via setSignedMessageHandler)
    public private(set) var capturedSignedMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Captured CLI message handler (set via setCLIMessageHandler)
    public private(set) var capturedCLIMessageHandler: (@Sendable (ContactMessage, ContactDTO?) async -> Void)?

    /// Captured acknowledgement handler (set via setAcknowledgementHandler)
    public private(set) var capturedAcknowledgementHandler: (@Sendable (Data) async -> Void)?

    // MARK: - Handler Setter Methods (matching MessagePollingService)

    public func setContactMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        capturedContactMessageHandler = handler
    }

    public func setChannelMessageHandler(_ handler: @escaping @Sendable (ChannelMessage, ChannelDTO?) async -> Void) {
        capturedChannelMessageHandler = handler
    }

    public func setSignedMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        capturedSignedMessageHandler = handler
    }

    public func setCLIMessageHandler(_ handler: @escaping @Sendable (ContactMessage, ContactDTO?) async -> Void) {
        capturedCLIMessageHandler = handler
    }

    public func setAcknowledgementHandler(_ handler: @escaping @Sendable (Data) async -> Void) {
        capturedAcknowledgementHandler = handler
    }

    // MARK: - Test Helpers

    /// Resets all recorded invocations and captured handlers
    public func reset() {
        pollAllMessagesInvocations = 0
        waitForPendingHandlersInvocations = 0
        capturedContactMessageHandler = nil
        capturedChannelMessageHandler = nil
        capturedSignedMessageHandler = nil
        capturedCLIMessageHandler = nil
        capturedAcknowledgementHandler = nil
    }
}
