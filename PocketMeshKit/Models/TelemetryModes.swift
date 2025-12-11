import Foundation

/// Packed telemetry modes for all three categories
public struct TelemetryModes: Sendable, Equatable {
    public var base: TelemetryMode
    public var location: TelemetryMode
    public var environment: TelemetryMode

    public init(
        base: TelemetryMode = .deny,
        location: TelemetryMode = .deny,
        environment: TelemetryMode = .deny
    ) {
        self.base = base
        self.location = location
        self.environment = environment
    }

    /// Initialize from packed byte
    public init(packed: UInt8) {
        self.base = TelemetryMode(rawValue: packed & 0x03) ?? .deny
        self.location = TelemetryMode(rawValue: (packed >> 2) & 0x03) ?? .deny
        self.environment = TelemetryMode(rawValue: (packed >> 4) & 0x03) ?? .deny
    }

    /// Pack into single byte for protocol
    public var packed: UInt8 {
        base.rawValue | (location.rawValue << 2) | (environment.rawValue << 4)
    }
}
