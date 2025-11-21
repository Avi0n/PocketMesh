import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "TelemetryStatus")

// MARK: - Status Data Types

public struct StatusData: Sendable {
    public let publicKeyPrefix: Data
    public let uptime: TimeInterval // Seconds since boot
    public let freeMemory: UInt32 // KB
    public let batteryPercent: UInt8
    public let radioConfig: String

    static func decode(from data: Data) throws -> StatusData {
        guard data.count >= 20 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key prefix (6 bytes)
        let publicKeyPrefix = data.subdata(in: offset ..< offset + 6)
        offset += 6

        // Uptime (uint32 seconds)
        let uptime = TimeInterval(data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        })
        offset += 4

        // Free memory (uint32 KB)
        let freeMemory = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4

        // Battery percent (uint8)
        let batteryPercent = data[offset]
        offset += 1

        // Radio config string (rest of payload, null-terminated)
        let radioConfigData = data.subdata(in: offset ..< data.count)
        let radioConfig = String(data: radioConfigData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? "Unknown"

        return StatusData(
            publicKeyPrefix: publicKeyPrefix,
            uptime: uptime,
            freeMemory: freeMemory,
            batteryPercent: batteryPercent,
            radioConfig: radioConfig,
        )
    }
}

public struct NeighbourEntry: Sendable, Identifiable {
    public let id = UUID()
    public let publicKeyPrefix: Data // Full public key or prefix
    public let lastSeen: Date // Seconds ago
    public let snr: Double // dB
    public let rssi: Int16 // dBm

    static func decode(from data: Data) throws -> NeighbourEntry {
        guard data.count >= 12 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key prefix (6 bytes minimum)
        let publicKeyPrefix = data.subdata(in: offset ..< offset + 6)
        offset += 6

        // Last seen (uint32 seconds ago)
        let secsAgo = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        let lastSeen = Date().addingTimeInterval(-TimeInterval(secsAgo))
        offset += 4

        // SNR (int8 * 4)
        let snrRaw = Int8(bitPattern: data[offset])
        let snr = Double(snrRaw) / 4.0
        offset += 1

        // RSSI (int16)
        let rssi = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Int16.self)
        }

        return NeighbourEntry(
            publicKeyPrefix: publicKeyPrefix,
            lastSeen: lastSeen,
            snr: snr,
            rssi: rssi,
        )
    }
}
