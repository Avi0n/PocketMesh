import Foundation
import MeshCore
@testable import PocketMeshServices

/// Mock implementation of ContactServiceProtocol for testing.
///
/// Configure the mock by setting the stub properties before calling methods.
/// Track method calls by examining the recorded invocations.
public actor MockContactService: ContactServiceProtocol {

    // MARK: - Stubs

    /// Result to return from syncContacts
    public var stubbedSyncContactsResult: Result<ContactSyncResult, Error> = .success(
        ContactSyncResult(contactsReceived: 0, lastSyncTimestamp: 0, isIncremental: false)
    )

    // MARK: - Recorded Invocations

    public struct SyncContactsInvocation: Sendable, Equatable {
        public let deviceID: UUID
        public let since: Date?
    }

    public private(set) var syncContactsInvocations: [SyncContactsInvocation] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Protocol Methods

    public func syncContacts(deviceID: UUID, since: Date? = nil) async throws -> ContactSyncResult {
        syncContactsInvocations.append(SyncContactsInvocation(deviceID: deviceID, since: since))
        switch stubbedSyncContactsResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Test Helpers

    /// Resets all recorded invocations
    public func reset() {
        syncContactsInvocations = []
    }
}
