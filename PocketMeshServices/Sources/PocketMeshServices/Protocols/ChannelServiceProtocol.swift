import Foundation
import MeshCore

/// Protocol for ChannelService to enable testability of SyncCoordinator.
///
/// This protocol abstracts the channel sync operations used by SyncCoordinator,
/// allowing it to be tested with mock implementations.
///
/// ## Usage
///
/// Services can accept this protocol type for dependency injection:
/// ```swift
/// actor MyCoordinator {
///     private let channelService: any ChannelServiceProtocol
///
///     init(channelService: any ChannelServiceProtocol) {
///         self.channelService = channelService
///     }
/// }
/// ```
public protocol ChannelServiceProtocol: Actor {

    // MARK: - Channel Sync

    /// Fetches all channels for a device from the remote device.
    /// - Parameters:
    ///   - deviceID: The device UUID
    ///   - maxChannels: Maximum number of channels to fetch (default: 8)
    /// - Returns: Sync result with number of channels synced
    func syncChannels(deviceID: UUID, maxChannels: UInt8) async throws -> ChannelSyncResult
}
