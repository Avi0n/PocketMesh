import Foundation
@testable import MeshCore

/// Mock clock for deterministic timeout testing
/// Uses yield-based waiting that can be advanced manually
public final class MockClock: Clock, @unchecked Sendable {
    public typealias Duration = Swift.Duration
    public typealias Instant = ContinuousClock.Instant

    private var _now: Instant
    private let lock = NSLock()
    private let spinSleepInterval: Duration

    public var now: Instant {
        lock.withLock { _now }
    }

    public var minimumResolution: Duration { .zero }

    /// Create a MockClock for testing
    /// - Parameters:
    ///   - now: Initial time (defaults to current time)
    ///   - spinSleepInterval: Real sleep duration between spin checks
    ///                        Use .zero for fastest tests, .milliseconds(1) to reduce CPU usage
    public init(
        now: Instant = ContinuousClock().now,
        spinSleepInterval: Duration = .milliseconds(1)
    ) {
        self._now = now
        self.spinSleepInterval = spinSleepInterval
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        // Yield-based waiting - allows time to be advanced by test code
        // Configurable sleep prevents CPU spinning while still allowing manual time advancement
        while now < deadline {
            if spinSleepInterval > .zero {
                try? await Task.sleep(for: spinSleepInterval)
            }
            try await Task.yield()
            if Task.isCancelled { throw CancellationError() }
        }
    }

    /// Advance time by duration
    public func advance(by duration: Duration) {
        lock.withLock {
            _now = _now.advanced(by: duration)
        }
    }
}

/// Test fixtures with realistic packet data for parser testing
/// Data structures match Python reference implementation
enum TestFixtures {

    // MARK: - Contact Fixture (147 bytes)

    /// Valid contact payload for testing Contact parser
    /// Structure: 32 (pubkey) + 1 (type) + 1 (flags) + 1 (path_len) + 64 (path) +
    ///            32 (name) + 4 (last_advert) + 4 (lat) + 4 (lon) + 4 (lastmod)
    static var validContactPayload: Data {
        var data = Data(capacity: PacketSize.contact)

        // Public key (32 bytes) - test key
        data.append(contentsOf: [UInt8](repeating: 0xAB, count: 32))

        // Type: 0x01 = repeater
        data.append(0x01)

        // Flags: 0x00
        data.append(0x00)

        // Path length: 2 hops
        data.append(0x02)

        // Path (64 bytes) - first 2 bytes used, rest padding
        data.append(contentsOf: [0x11, 0x22])
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 62))

        // Name (32 bytes) - "TestNode" + padding
        let nameBytes = "TestNode".data(using: .utf8)!
        data.append(nameBytes)
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 32 - nameBytes.count))

        // Last advertisement timestamp: 1700000000 (Nov 14, 2023)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Latitude: 37.7749 (San Francisco) = 37774900 microdegrees
        data.append(contentsOf: withUnsafeBytes(of: Int32(37774900).littleEndian) { Array($0) })

        // Longitude: -122.4194 = -122419400 microdegrees
        data.append(contentsOf: withUnsafeBytes(of: Int32(-122419400).littleEndian) { Array($0) })

        // Last modified: 1700000100
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000100).littleEndian) { Array($0) })

        return data
    }

    // MARK: - DeviceInfo V3 Fixture (79 bytes)

    /// DeviceInfo v3 format payload
    /// Structure: 1 (fwVer) + 1 (maxContacts/2) + 1 (maxChannels) + 4 (blePin) +
    ///            12 (fwBuild) + 40 (model) + 20 (version)
    static var deviceInfoV3Payload: Data {
        var data = Data(capacity: PacketSize.deviceInfoV3Full)

        // Firmware version: 3
        data.append(0x03)

        // Max contacts: 50 (will be multiplied by 2 to get 100)
        data.append(50)

        // Max channels: 8
        data.append(8)

        // BLE PIN: 123456 (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(123456).littleEndian) { Array($0) })

        // Firmware build (12 bytes): "1.2.3" + padding
        let fwBuild = "1.2.3".data(using: .utf8)!
        data.append(fwBuild)
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 12 - fwBuild.count))

        // Model (40 bytes): "T-Echo" + padding
        let model = "T-Echo".data(using: .utf8)!
        data.append(model)
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 40 - model.count))

        // Version (20 bytes): "2.0.0" + padding
        let version = "2.0.0".data(using: .utf8)!
        data.append(version)
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 20 - version.count))

        return data
    }

    // MARK: - ContactMessage V1 Fixture (17+ bytes)

    /// ContactMessage v1 format (no SNR prefix)
    /// Structure: 6 (pubkey prefix) + 1 (pathLen) + 1 (txtType) + 4 (timestamp) + text
    static var contactMessageV1Payload: Data {
        var data = Data()

        // Sender public key prefix (6 bytes)
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34])

        // Path length: 1 hop
        data.append(0x01)

        // Text type: 0x00 = plain text
        data.append(0x00)

        // Timestamp: 1700000000 (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Message text
        data.append("Hello".data(using: .utf8)!)

        return data
    }

    // MARK: - ContactMessage V3 Fixture (20+ bytes)

    /// ContactMessage v3 format (includes SNR prefix)
    /// Structure: 1 (snr) + 2 (reserved) + 6 (pubkey prefix) + 1 (pathLen) + 1 (txtType) + 4 (timestamp) + text
    static var contactMessageV3Payload: Data {
        var data = Data()

        // SNR: -5.25 dB = -21 raw (Int8)
        data.append(UInt8(bitPattern: Int8(-21)))

        // Reserved (2 bytes)
        data.append(contentsOf: [0x00, 0x00])

        // Sender public key prefix (6 bytes)
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34])

        // Path length: 2 hops
        data.append(0x02)

        // Text type: 0x00 = plain text
        data.append(0x00)

        // Timestamp: 1700000000 (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Message text
        data.append("Hello from mesh!".data(using: .utf8)!)

        return data
    }

    // MARK: - SelfInfo Fixture (55+ bytes)

    /// SelfInfo response payload
    static var selfInfoPayload: Data {
        var data = Data(capacity: 70)

        // Advertisement type: 0x01
        data.append(0x01)

        // TX power: 20 dBm
        data.append(20)

        // Max TX power: 30 dBm
        data.append(30)

        // Public key (32 bytes)
        data.append(contentsOf: [UInt8](repeating: 0xCD, count: 32))

        // Latitude: 37.7749
        data.append(contentsOf: withUnsafeBytes(of: Int32(37774900).littleEndian) { Array($0) })

        // Longitude: -122.4194
        data.append(contentsOf: withUnsafeBytes(of: Int32(-122419400).littleEndian) { Array($0) })

        // Multi-acks: 1
        data.append(0x01)

        // Advertisement location policy: 0
        data.append(0x00)

        // Telemetry mode: 0x15 (env=1, loc=1, base=1)
        data.append(0x15)

        // Manual add: false
        data.append(0x00)

        // Radio frequency: 915000 kHz = 915.0 MHz (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(915000000).littleEndian) { Array($0) })

        // Radio bandwidth: 125000 Hz = 125 kHz (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(125000000).littleEndian) { Array($0) })

        // Spreading factor: 10
        data.append(10)

        // Coding rate: 5
        data.append(5)

        // Name: "MyNode"
        data.append("MyNode".data(using: .utf8)!)

        return data
    }

    // MARK: - Invalid UTF-8 Fixture

    /// ContactMessage with invalid UTF-8 sequence for testing lossy conversion
    static var contactMessageWithInvalidUTF8: Data {
        var data = Data()

        // Standard v1 header
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34]) // pubkey prefix
        data.append(0x01) // path length
        data.append(0x00) // text type
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Invalid UTF-8: 0x80-0xBF are continuation bytes, invalid as start
        data.append(contentsOf: [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x80, 0x81, 0x82]) // "Hello" + invalid

        return data
    }

    // MARK: - ChannelMessage V1 Fixture

    /// ChannelMessage v1 format (no SNR prefix)
    /// Structure: 1 (channelIndex) + 1 (pathLen) + 1 (txtType) + 4 (timestamp) + text
    static var channelMessageV1Payload: Data {
        var data = Data()

        // Channel index: 1
        data.append(0x01)

        // Path length: 1 hop
        data.append(0x01)

        // Text type: 0x00 = plain text
        data.append(0x00)

        // Timestamp: 1700000000 (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Message text
        data.append("Channel message".data(using: .utf8)!)

        return data
    }

    // MARK: - ChannelMessage V3 Fixture

    /// ChannelMessage v3 format (includes SNR prefix)
    static var channelMessageV3Payload: Data {
        var data = Data()

        // SNR: -3.5 dB = -14 raw
        data.append(UInt8(bitPattern: Int8(-14)))

        // Reserved (2 bytes)
        data.append(contentsOf: [0x00, 0x00])

        // Channel index: 2
        data.append(0x02)

        // Path length: 3 hops
        data.append(0x03)

        // Text type: 0x00 = plain text
        data.append(0x00)

        // Timestamp
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })

        // Message text
        data.append("V3 channel message".data(using: .utf8)!)

        return data
    }

    // MARK: - Battery Fixture

    /// Battery response payload (basic)
    static var batteryBasicPayload: Data {
        var data = Data()
        // Battery level: 4200 mV (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4200).littleEndian) { Array($0) })
        return data
    }

    /// Battery response payload (extended with storage)
    static var batteryExtendedPayload: Data {
        var data = Data()
        // Battery level: 4200 mV
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4200).littleEndian) { Array($0) })
        // Used storage: 1024 KB
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1024).littleEndian) { Array($0) })
        // Total storage: 4096 KB
        data.append(contentsOf: withUnsafeBytes(of: UInt32(4096).littleEndian) { Array($0) })
        return data
    }

    // MARK: - Stats Fixtures

    /// Core stats payload (9 bytes)
    static var coreStatsPayload: Data {
        var data = Data()
        // Battery: 4200 mV
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4200).littleEndian) { Array($0) })
        // Uptime: 3600 seconds
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3600).littleEndian) { Array($0) })
        // Errors: 5
        data.append(contentsOf: withUnsafeBytes(of: UInt16(5).littleEndian) { Array($0) })
        // Queue length: 3
        data.append(3)
        return data
    }

    /// Radio stats payload (12 bytes)
    static var radioStatsPayload: Data {
        var data = Data()
        // Noise floor: -110 dBm
        data.append(contentsOf: withUnsafeBytes(of: Int16(-110).littleEndian) { Array($0) })
        // Last RSSI: -70 dBm
        data.append(UInt8(bitPattern: Int8(-70)))
        // Last SNR: 6.5 dB = 26 raw
        data.append(26)
        // TX airtime: 1000 seconds
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1000).littleEndian) { Array($0) })
        // RX airtime: 5000 seconds
        data.append(contentsOf: withUnsafeBytes(of: UInt32(5000).littleEndian) { Array($0) })
        return data
    }

    /// Packet stats payload (24 bytes)
    static var packetStatsPayload: Data {
        var data = Data()
        // Received: 100
        data.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Array($0) })
        // Sent: 50
        data.append(contentsOf: withUnsafeBytes(of: UInt32(50).littleEndian) { Array($0) })
        // Flood TX: 20
        data.append(contentsOf: withUnsafeBytes(of: UInt32(20).littleEndian) { Array($0) })
        // Direct TX: 30
        data.append(contentsOf: withUnsafeBytes(of: UInt32(30).littleEndian) { Array($0) })
        // Flood RX: 60
        data.append(contentsOf: withUnsafeBytes(of: UInt32(60).littleEndian) { Array($0) })
        // Direct RX: 40
        data.append(contentsOf: withUnsafeBytes(of: UInt32(40).littleEndian) { Array($0) })
        return data
    }

    // MARK: - StatusResponse Fixture (58 bytes per Python parsing.py)

    static var statusResponsePayload: Data {
        var data = Data()
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4100).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(5).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(-110).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(-75).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1000).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(500).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3600).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(86400).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(200).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(300).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(600).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(400).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(10).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(34).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(5).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(7200).littleEndian) { Array($0) })
        return data
    }

    // MARK: - LoginFailed Fixture

    /// LoginFailed payload with reserved byte + public key prefix
    static var loginFailedPayload: Data {
        var data = Data()
        // Reserved byte (1 byte)
        data.append(0x00)
        // Public key prefix (6 bytes)
        data.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
        return data
    }

    /// LoginFailed payload minimal (just reserved byte)
    static var loginFailedMinimalPayload: Data {
        Data([0x00])
    }

    // MARK: - SignStart Fixture

    /// SignStart payload: 1 reserved + 4 bytes max_length
    static var signStartPayload: Data {
        var data = Data()
        // Reserved byte
        data.append(0x00)
        // Max length: 256
        data.append(contentsOf: withUnsafeBytes(of: UInt32(256).littleEndian) { Array($0) })
        return data
    }

    // MARK: - LoginSuccess Fixture

    static var loginSuccessPayload: Data {
        var data = Data()
        data.append(0x01)
        data.append(0x00)
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        return data
    }

    // MARK: - ChannelInfo Fixture

    /// ChannelInfo payload (49 bytes: 1 index + 32 name + 16 secret)
    static var channelInfoPayload: Data {
        var data = Data()
        // Channel index
        data.append(0x01)
        // Name (32 bytes) - "TestChannel" + null padding
        let nameBytes = "TestChannel".data(using: .utf8)!
        data.append(nameBytes)
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 32 - nameBytes.count))
        // Secret (16 bytes)
        data.append(contentsOf: [UInt8](repeating: 0xAB, count: 16))
        return data
    }

    // MARK: - TraceData Fixture

    static var traceDataPayload: Data {
        var data = Data()
        data.append(0x00)
        data.append(0x02)
        data.append(0x01)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(12345).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(67890).littleEndian) { Array($0) })
        data.append(0x11)
        data.append(0x22)
        data.append(20)
        data.append(UInt8(bitPattern: Int8(-16)))
        data.append(UInt8(bitPattern: Int8(12)))
        return data
    }

    // MARK: - ControlData Fixture

    /// ControlData payload (4+ bytes)
    static var controlDataPayload: Data {
        var data = Data()
        // SNR: 6.0 dB = 24 raw
        data.append(24)
        // RSSI: -80 dBm
        data.append(UInt8(bitPattern: Int8(-80)))
        // Path length
        data.append(0x02)
        // Payload type
        data.append(0x01)
        // Payload data
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        return data
    }

    // MARK: - PathDiscovery Fixture

    /// PathDiscovery response payload
    static var pathDiscoveryPayload: Data {
        var data = Data()
        // Public key prefix (6 bytes)
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        // Out path length
        data.append(0x02)
        // Out path
        data.append(contentsOf: [0x11, 0x22])
        // In path length
        data.append(0x03)
        // In path
        data.append(contentsOf: [0x33, 0x44, 0x55])
        return data
    }

    // MARK: - TelemetryResponse Fixture

    /// TelemetryResponse payload
    static var telemetryResponsePayload: Data {
        var data = Data()
        // Public key prefix (6 bytes)
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        // Tag (4 bytes)
        data.append(contentsOf: [0x01, 0x02, 0x03, 0x04])
        // Raw data (variable)
        data.append(contentsOf: [0xCA, 0xFE, 0xBA, 0xBE])
        return data
    }

    // MARK: - Acknowledgement Fixture

    /// Acknowledgement (ACK) payload
    static var acknowledgementPayload: Data {
        Data([0xDE, 0xAD, 0xBE, 0xEF])
    }

    // MARK: - MessageSent Fixture

    /// MessageSent response payload
    static var messageSentPayload: Data {
        var data = Data()
        // Type: 0x00
        data.append(0x00)
        // Expected ACK (4 bytes)
        data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        // Suggested timeout: 5000 ms
        data.append(contentsOf: withUnsafeBytes(of: UInt32(5000).littleEndian) { Array($0) })
        return data
    }
}

// MARK: - Mock Extensions for Testing

extension StatusResponse {
    static func mock(
        publicKeyPrefix: Data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
        battery: Int = 4200,
        txQueueLength: Int = 0,
        noiseFloor: Int = -100,
        lastRSSI: Int = -75
    ) -> StatusResponse {
        StatusResponse(
            publicKeyPrefix: publicKeyPrefix,
            battery: battery,
            txQueueLength: txQueueLength,
            noiseFloor: noiseFloor,
            lastRSSI: lastRSSI,
            packetsReceived: 0,
            packetsSent: 0,
            airtime: 0,
            uptime: 0,
            sentFlood: 0,
            sentDirect: 0,
            receivedFlood: 0,
            receivedDirect: 0,
            fullEvents: 0,
            lastSNR: 0,
            directDuplicates: 0,
            floodDuplicates: 0,
            rxAirtime: 0
        )
    }
}

extension MeshContact {
    static func mock(
        name: String = "TestNode",
        publicKey: Data = Data(repeating: 0xAB, count: 32)
    ) -> MeshContact {
        MeshContact(
            id: publicKey.hexString,
            publicKey: publicKey,
            type: 0x01,
            flags: 0x00,
            outPathLength: 2,
            outPath: Data(repeating: 0x00, count: 2),
            advertisedName: name,
            lastAdvertisement: Date(),
            latitude: 0.0,
            longitude: 0.0,
            lastModified: Date()
        )
    }
}
