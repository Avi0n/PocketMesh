import Foundation

/// Groups sync throttling parameters that travel together through the sync pipeline.
/// Computed from `DevicePlatform` and `lastCleanChannelSync` state at sync start.
public struct SyncThrottlingConfig: Sendable {
    /// Delay between individual getMessage() calls during sync catch-up.
    public let messageDelay: Duration

    /// Number of messages polled before inserting a breathing pause. 0 disables.
    public let breathingInterval: Int

    /// Duration of the breathing pause inserted every `breathingInterval` messages.
    public let breathingDuration: Duration

    /// If channels were synced more recently than this window, skip channel re-sync.
    public let channelSyncSkipWindow: Duration

    /// Timestamp of the last fully-clean channel sync for the current device.
    public let lastCleanChannelSync: Date?

    public init(
        messageDelay: Duration = .zero,
        breathingInterval: Int = 0,
        breathingDuration: Duration = .zero,
        channelSyncSkipWindow: Duration = .zero,
        lastCleanChannelSync: Date? = nil
    ) {
        self.messageDelay = messageDelay
        self.breathingInterval = breathingInterval
        self.breathingDuration = breathingDuration
        self.channelSyncSkipWindow = channelSyncSkipWindow
        self.lastCleanChannelSync = lastCleanChannelSync
    }

    /// No throttling — used for WiFi connections.
    public static let none = SyncThrottlingConfig()
}
