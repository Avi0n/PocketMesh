import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "TelemetryMMA")

// MARK: - MMA Data Types

public struct MMAData: Sendable {
    public let publicKeyPrefix: Data
    public let fromTime: Date
    public let toTime: Date
    public let sampleCount: UInt32

    public let minTemperature: Double?
    public let maxTemperature: Double?
    public let avgTemperature: Double?

    public let minHumidity: Double?
    public let maxHumidity: Double?
    public let avgHumidity: Double?

    static func decode(from data: Data) throws -> MMAData {
        guard data.count >= 27 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key prefix (6 bytes)
        let publicKeyPrefix = data.subdata(in: offset ..< offset + 6)
        offset += 6

        // Time range (uint32 timestamps)
        let fromTimestamp = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        let fromTime = Date(timeIntervalSince1970: TimeInterval(fromTimestamp))
        offset += 4

        let toTimestamp = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        let toTime = Date(timeIntervalSince1970: TimeInterval(toTimestamp))
        offset += 4

        // Sample count
        let sampleCount = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4

        // Temperature stats (int16 * 10)
        let minTempRaw = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Int16.self)
        }
        let minTemperature = Double(minTempRaw) / 10.0
        offset += 2

        let maxTempRaw = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Int16.self)
        }
        let maxTemperature = Double(maxTempRaw) / 10.0
        offset += 2

        let avgTempRaw = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: Int16.self)
        }
        let avgTemperature = Double(avgTempRaw) / 10.0
        offset += 2

        // Humidity stats (uint8 * 2)
        let minHumRaw = data[offset]
        let minHumidity = Double(minHumRaw) / 2.0
        offset += 1

        let maxHumRaw = data[offset]
        let maxHumidity = Double(maxHumRaw) / 2.0
        offset += 1

        let avgHumRaw = data[offset]
        let avgHumidity = Double(avgHumRaw) / 2.0

        return MMAData(
            publicKeyPrefix: publicKeyPrefix,
            fromTime: fromTime,
            toTime: toTime,
            sampleCount: sampleCount,
            minTemperature: minTemperature,
            maxTemperature: maxTemperature,
            avgTemperature: avgTemperature,
            minHumidity: minHumidity,
            maxHumidity: maxHumidity,
            avgHumidity: avgHumidity,
        )
    }
}
