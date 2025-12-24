import Foundation
import MeshCore
@testable import PocketMeshServices

/// Mock implementation of ChannelServiceProtocol for testing.
///
/// Configure the mock by setting the stub properties before calling methods.
/// Track method calls by examining the recorded invocations.
public actor MockChannelService: ChannelServiceProtocol {

    // MARK: - Stubs

    /// Result to return from syncChannels
    public var stubbedSyncChannelsResult: Result<ChannelSyncResult, Error> = .success(
        ChannelSyncResult(channelsSynced: 0, errors: [])
    )

    // MARK: - Recorded Invocations

    public struct SyncChannelsInvocation: Sendable, Equatable {
        public let deviceID: UUID
        public let maxChannels: UInt8
    }

    public private(set) var syncChannelsInvocations: [SyncChannelsInvocation] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Protocol Methods

    public func syncChannels(deviceID: UUID, maxChannels: UInt8) async throws -> ChannelSyncResult {
        syncChannelsInvocations.append(SyncChannelsInvocation(deviceID: deviceID, maxChannels: maxChannels))
        switch stubbedSyncChannelsResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Test Helpers

    /// Resets all recorded invocations
    public func reset() {
        syncChannelsInvocations = []
    }
}
