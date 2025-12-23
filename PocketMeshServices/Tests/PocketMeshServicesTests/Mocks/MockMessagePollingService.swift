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

    // MARK: - Test Helpers

    /// Resets all recorded invocations
    public func reset() {
        pollAllMessagesInvocations = 0
    }
}
