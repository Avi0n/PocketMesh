import Foundation

// MARK: - Sync Throttling Configuration

extension DevicePlatform {

    /// Delay between individual getMessage() calls during sync catch-up.
    /// nRF52 uses .zero -- no field evidence of BLE saturation on that platform.
    var syncMessageDelay: Duration {
        switch self {
        case .esp32, .unknown: .milliseconds(100)
        case .nrf52: .zero
        }
    }

    /// Number of messages polled before inserting a breathing pause. 0 disables.
    var syncBreathingInterval: Int {
        switch self {
        case .esp32, .unknown: 20
        case .nrf52: 0
        }
    }

    /// Duration of the breathing pause inserted every `syncBreathingInterval` messages.
    var syncBreathingDuration: Duration {
        switch self {
        case .esp32, .unknown: .milliseconds(500)
        case .nrf52: .zero
        }
    }

    /// If channels were synced more recently than this, skip channel re-sync on resync.
    /// Only enabled for ESP32 where channel re-sync wastes scarce connection time.
    /// Channel skipping is a correctness tradeoff (not just performance), so it stays
    /// disabled for unknown platforms until field evidence warrants it.
    var channelSyncSkipWindow: Duration {
        switch self {
        case .esp32: .seconds(30)
        case .nrf52, .unknown: .zero
        }
    }

    /// Builds a complete throttling config for a sync operation.
    func syncThrottlingConfig(lastCleanChannelSync: Date?) -> SyncThrottlingConfig {
        SyncThrottlingConfig(
            messageDelay: syncMessageDelay,
            breathingInterval: syncBreathingInterval,
            breathingDuration: syncBreathingDuration,
            channelSyncSkipWindow: channelSyncSkipWindow,
            lastCleanChannelSync: lastCleanChannelSync
        )
    }
}
