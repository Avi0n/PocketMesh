import Foundation

/// Configuration for mock radio behavior
public struct MockRadioConfig: Sendable {
    /// Simulate packet loss (0.0 = none, 1.0 = all packets)
    public var packetLossRate: Double = 0.0

    /// Simulate random delays (0...maxDelay seconds)
    public var maxRandomDelay: TimeInterval = 0.0

    /// Simulate fragmentation by reducing effective MTU
    public var forcedMTU: Int?

    /// Simulate connection drops after N frames
    public var disconnectAfterFrames: Int?

    /// Enable verbose logging
    public var verboseLogging: Bool = true

    /// Custom device info (uses DeviceInfo.default if nil)
    public var deviceInfo: DeviceInfo?

    /// Custom self info (uses SelfInfo.default if nil)
    public var selfInfo: SelfInfo?

    public init(
        packetLossRate: Double = 0.0,
        maxRandomDelay: TimeInterval = 0.0,
        forcedMTU: Int? = nil,
        disconnectAfterFrames: Int? = nil,
        verboseLogging: Bool = true,
        deviceInfo: DeviceInfo? = nil,
        selfInfo: SelfInfo? = nil,
    ) {
        self.packetLossRate = packetLossRate
        self.maxRandomDelay = maxRandomDelay
        self.forcedMTU = forcedMTU
        self.disconnectAfterFrames = disconnectAfterFrames
        self.verboseLogging = verboseLogging
        self.deviceInfo = deviceInfo
        self.selfInfo = selfInfo
    }

    /// Default configuration for testing
    public static let `default` = MockRadioConfig()

    /// Configuration for testing error conditions
    public static let errorTesting = MockRadioConfig(
        packetLossRate: 0.1,
        maxRandomDelay: 0.5,
        forcedMTU: 64,
    )
}
