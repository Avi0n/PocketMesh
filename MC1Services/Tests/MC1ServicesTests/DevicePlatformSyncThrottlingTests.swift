import Testing
import Foundation
@testable import MC1Services

@Suite("DevicePlatform Sync Throttling")
struct DevicePlatformSyncThrottlingTests {

    @Test("ESP32 returns expected throttling values")
    func esp32ThrottlingValues() {
        let platform = DevicePlatform.esp32
        #expect(platform.syncMessageDelay == .milliseconds(100))
        #expect(platform.syncBreathingInterval == 20)
        #expect(platform.syncBreathingDuration == .milliseconds(500))
        #expect(platform.channelSyncSkipWindow == .seconds(30))
    }

    @Test("nRF52 returns zero for all throttling values")
    func nrf52ThrottlingValues() {
        let platform = DevicePlatform.nrf52
        #expect(platform.syncMessageDelay == .zero)
        #expect(platform.syncBreathingInterval == 0)
        #expect(platform.syncBreathingDuration == .zero)
        #expect(platform.channelSyncSkipWindow == .zero)
    }

    @Test("Unknown matches ESP32 for message throttling but zero for channel skip")
    func unknownThrottlingValues() {
        let platform = DevicePlatform.unknown
        #expect(platform.syncMessageDelay == .milliseconds(100))
        #expect(platform.syncBreathingInterval == 20)
        #expect(platform.syncBreathingDuration == .milliseconds(500))
        #expect(platform.channelSyncSkipWindow == .zero)
    }
}
