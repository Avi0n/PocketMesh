import Foundation

/// Cayenne Low Power Payload (LPP) sensor types
public enum LPPType: UInt8, Sendable {
    case digitalInput = 0
    case digitalOutput = 1
    case analogInput = 2
    case analogOutput = 3
    case genericSensor = 100
    case illuminance = 101
    case presence = 102
    case temperature = 103
    case humidity = 104
    case accelerometer = 113
    case barometer = 115
    case voltage = 116
    case current = 117
    case frequency = 118
    case percentage = 120
    case altitude = 121
    case load = 122
    case concentration = 125
    case power = 128
    case distance = 130
    case energy = 131
    case direction = 132
    case time = 133
    case gyrometer = 134
    case colour = 135
    case gps = 136
    case switchValue = 142

    /// Size in bytes for this sensor type
    public var dataSize: Int {
        switch self {
        case .digitalInput, .digitalOutput, .presence, .percentage, .switchValue:
            return 1
        case .analogInput, .analogOutput, .illuminance, .humidity, .barometer,
             .voltage, .current, .frequency, .altitude, .load, .concentration,
             .power, .distance, .energy, .direction, .time, .temperature:
            return 2
        case .genericSensor:
            return 4
        case .accelerometer, .gyrometer:
            return 6
        case .colour:
            return 3
        case .gps:
            return 9
        }
    }
}

/// A single LPP data point
public struct LPPDataPoint: Sendable, Equatable {
    public let channel: UInt8
    public let type: LPPType
    public let value: LPPValue

    public init(channel: UInt8, type: LPPType, value: LPPValue) {
        self.channel = channel
        self.type = type
        self.value = value
    }
}

/// LPP value types
public enum LPPValue: Sendable, Equatable {
    case integer(Int)
    case float(Float)
    case vector3(x: Float, y: Float, z: Float)
    case gps(latitude: Float, longitude: Float, altitude: Float)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

/// LPP frame decoder
public enum LPPDecoder {

    /// Decode LPP data from raw bytes
    /// - Parameter data: Raw LPP-encoded data
    /// - Returns: Array of decoded data points
    public static func decode(_ data: Data) -> [LPPDataPoint] {
        var result: [LPPDataPoint] = []
        var offset = 0

        while offset < data.count && data[offset] != 0 {
            guard offset + 2 <= data.count else { break }

            let channel = data[offset]
            offset += 1

            guard let type = LPPType(rawValue: data[offset]) else {
                // Unknown type, skip
                offset += 1
                continue
            }
            offset += 1

            guard offset + type.dataSize <= data.count else { break }

            let valueData = data.subdata(in: offset..<(offset + type.dataSize))
            offset += type.dataSize

            if let value = decodeValue(type: type, data: valueData) {
                result.append(LPPDataPoint(channel: channel, type: type, value: value))
            }
        }

        return result
    }

    private static func decodeValue(type: LPPType, data: Data) -> LPPValue? {
        switch type {
        case .digitalInput, .digitalOutput, .presence, .switchValue:
            return .integer(Int(data[0]))

        case .percentage:
            return .integer(Int(data[0]))

        case .temperature:
            let raw = data.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            return .float(Float(raw) / 10.0)

        case .humidity:
            let raw = data.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            return .float(Float(raw) / 2.0)

        case .barometer:
            let raw = data.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            return .float(Float(raw) / 10.0)

        case .voltage:
            let raw = data.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            return .float(Float(raw) / 100.0)

        case .illuminance:
            let raw = data.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            return .integer(Int(raw))

        case .altitude:
            let raw = data.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            return .float(Float(raw))

        case .accelerometer, .gyrometer:
            let x = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            let y = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            let z = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            return .vector3(
                x: Float(x) / 1000.0,
                y: Float(y) / 1000.0,
                z: Float(z) / 1000.0
            )

        case .gps:
            let lat = decodeGps24BitValue(data.subdata(in: 0..<3))
            let lon = decodeGps24BitValue(data.subdata(in: 3..<6))
            let alt = decodeGps24BitValue(data.subdata(in: 6..<9))
            return .gps(
                latitude: Float(lat) / 10000.0,
                longitude: Float(lon) / 10000.0,
                altitude: Float(alt) / 100.0
            )

        case .colour:
            return .rgb(red: data[0], green: data[1], blue: data[2])

        case .analogInput, .analogOutput, .current, .frequency, .load, .concentration,
             .power, .distance, .energy, .direction, .time:
            // For other 2-byte types, return raw integer
            let raw = data.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
            return .integer(Int(raw))

        case .genericSensor:
            let raw = data.withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
            return .integer(Int(raw))
        }
    }

    /// Decode a 24-bit signed value (used for GPS coordinates)
    private static func decodeGps24BitValue(_ data: Data) -> Int32 {
        guard data.count >= 3 else { return 0 }
        var value: Int32 = Int32(data[0]) | (Int32(data[1]) << 8) | (Int32(data[2]) << 16)
        // Sign extend if negative (bit 23 is set)
        if value & 0x800000 != 0 {
            value |= Int32(bitPattern: 0xFF000000)
        }
        return value
    }
}
