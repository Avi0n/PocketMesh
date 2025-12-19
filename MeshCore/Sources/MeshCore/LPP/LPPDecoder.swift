import Foundation

// MARK: - LPP Sensor Types

/// Cayenne Low Power Payload (LPP) sensor types.
///
/// LPP is a compact binary format for transmitting sensor data over low-bandwidth
/// networks like LoRa. Each sensor type has a defined data size and encoding.
///
/// For the full specification, see:
/// [Cayenne LPP Documentation](https://developers.mydevices.com/cayenne/docs/lora/#lora-cayenne-low-power-payload)
public enum LPPSensorType: UInt8, Sendable, CaseIterable {
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
    case unixTime = 133
    case gyrometer = 134
    case colour = 135
    case gps = 136
    case switchValue = 142

    /// Size in bytes for this sensor type's data payload
    public var dataSize: Int {
        switch self {
        // 1-byte types
        case .digitalInput, .digitalOutput, .presence, .humidity, .percentage, .switchValue:
            1
        // 2-byte types
        case .analogInput, .analogOutput, .illuminance, .temperature, .barometer,
             .voltage, .current, .altitude, .load, .concentration, .power, .direction:
            2
        // 3-byte types
        case .colour:
            3
        // 4-byte types
        case .genericSensor, .frequency, .distance, .energy, .unixTime:
            4
        // 6-byte types (3 x 2-byte values)
        case .accelerometer, .gyrometer:
            6
        // 9-byte types (3 x 3-byte values)
        case .gps:
            9
        }
    }

    /// Human-readable name for the sensor type
    public var name: String {
        switch self {
        case .digitalInput: "Digital Input"
        case .digitalOutput: "Digital Output"
        case .analogInput: "Analog Input"
        case .analogOutput: "Analog Output"
        case .genericSensor: "Sensor"
        case .illuminance: "Illuminance"
        case .presence: "Presence"
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .accelerometer: "Accelerometer"
        case .barometer: "Barometer"
        case .voltage: "Voltage"
        case .current: "Current"
        case .frequency: "Frequency"
        case .percentage: "Percentage"
        case .altitude: "Altitude"
        case .load: "Load"
        case .concentration: "Concentration"
        case .power: "Power"
        case .distance: "Distance"
        case .energy: "Energy"
        case .direction: "Direction"
        case .unixTime: "Time"
        case .gyrometer: "Gyrometer"
        case .colour: "Colour"
        case .gps: "GPS"
        case .switchValue: "Switch"
        }
    }
}

// MARK: - LPP Values

/// A decoded LPP sensor value.
///
/// `LPPValue` represents the decoded data from a sensor reading. The specific
/// case indicates the value type, which depends on the sensor.
public enum LPPValue: Sendable, Equatable {
    /// Boolean value (digital input/output, presence, switch)
    case digital(Bool)

    /// Integer value (illuminance in lux, percentage, direction in degrees)
    case integer(Int)

    /// Floating-point value with unit context
    case float(Double)

    /// 3D vector (accelerometer in g, gyrometer in degrees/s)
    case vector3(x: Double, y: Double, z: Double)

    /// GPS coordinates
    case gps(latitude: Double, longitude: Double, altitude: Double)

    /// RGB colour
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    /// Unix timestamp
    case timestamp(Date)
}

// MARK: - LPP Data Point

/// A single decoded LPP data point
public struct LPPDataPoint: Sendable, Equatable {
    /// Channel identifier (application-specific)
    public let channel: UInt8

    /// Sensor type
    public let type: LPPSensorType

    /// Decoded value
    public let value: LPPValue

    public init(channel: UInt8, type: LPPSensorType, value: LPPValue) {
        self.channel = channel
        self.type = type
        self.value = value
    }
}

// MARK: - LPP Decoder

/// Decodes Cayenne Low Power Payload (LPP) format sensor data.
///
/// `LPPDecoder` parses binary LPP frames into structured ``LPPDataPoint`` values.
/// LPP is commonly used for transmitting sensor telemetry over LoRa networks.
///
/// ## Frame Format
///
/// Each LPP frame consists of multiple sensor readings:
/// - **Channel** (1 byte): Identifies the sensor instance (0-255)
/// - **Type** (1 byte): Sensor type from ``LPPSensorType``
/// - **Value** (N bytes): Type-specific encoded value
///
/// ## Usage
///
/// ```swift
/// // Decode telemetry response from a MeshCore device
/// let response = try await session.getSelfTelemetry()
/// let dataPoints = LPPDecoder.decode(response.rawData)
///
/// for point in dataPoints {
///     print("Channel \(point.channel) \(point.type.name):")
///     switch point.value {
///     case .float(let value):
///         print("  \(value)")
///     case .gps(let lat, let lon, let alt):
///         print("  \(lat), \(lon) @ \(alt)m")
///     default:
///         print("  \(point.value)")
///     }
/// }
/// ```
///
/// ## Supported Sensors
///
/// The decoder supports all standard Cayenne LPP sensor types including:
/// - Environmental: Temperature, humidity, barometer
/// - Motion: Accelerometer, gyrometer
/// - Location: GPS coordinates
/// - Electrical: Voltage, current, power
/// - Generic: Digital/analog I/O, percentages
public enum LPPDecoder {

    /// Decodes LPP data from raw bytes.
    ///
    /// - Parameter data: Raw LPP-encoded data bytes.
    /// - Returns: Array of decoded data points. Returns an empty array if
    ///            the data is empty or cannot be parsed.
    public static func decode(_ data: Data) -> [LPPDataPoint] {
        var result: [LPPDataPoint] = []
        var offset = 0

        while offset < data.count {
            guard offset + 2 <= data.count else { break }

            let channel = data[offset]
            let typeCode = data[offset + 1]
            offset += 2

            guard let sensorType = LPPSensorType(rawValue: typeCode) else {
                break
            }

            // Check we have enough data for this sensor type
            guard offset + sensorType.dataSize <= data.count else { break }

            let valueData = data.subdata(in: offset..<(offset + sensorType.dataSize))
            offset += sensorType.dataSize

            if let value = decodeValue(type: sensorType, data: valueData) {
                result.append(LPPDataPoint(channel: channel, type: sensorType, value: value))
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private static func decodeValue(type: LPPSensorType, data: Data) -> LPPValue? {
        switch type {
        case .digitalInput, .digitalOutput, .presence, .switchValue:
            return .digital(data[0] != 0)

        case .percentage:
            return .integer(Int(data[0]))

        case .humidity:
            return .float(Double(data[0]) * 0.5)

        case .temperature:
            let raw = readInt16LE(data)
            return .float(Double(raw) / 10.0)

        case .barometer:
            let raw = readUInt16LE(data)
            return .float(Double(raw) / 10.0)

        case .voltage:
            // MeshCore firmware: 0.1mV units (38657 = 3.8657V)
            let raw = readUInt16LE(data)
            return .float(Double(raw) / 10000.0)

        case .current:
            let raw = readUInt16LE(data)
            return .float(Double(raw) / 1000.0)

        case .illuminance:
            let raw = readUInt16LE(data)
            return .integer(Int(raw))

        case .altitude:
            let raw = readInt16LE(data)
            return .float(Double(raw))

        case .load:
            let raw = readUInt16LE(data)
            return .float(Double(raw) / 100.0)

        case .concentration:
            let raw = readUInt16LE(data)
            return .integer(Int(raw))

        case .power:
            let raw = readUInt16LE(data)
            return .integer(Int(raw))

        case .direction:
            let raw = readUInt16LE(data)
            return .integer(Int(raw))

        case .analogInput, .analogOutput:
            let raw = readInt16LE(data)
            return .float(Double(raw) / 100.0)

        case .genericSensor:
            let raw = readInt32LE(data)
            return .integer(Int(raw))

        case .frequency:
            let raw = readUInt32LE(data)
            return .integer(Int(raw))

        case .distance:
            let raw = readUInt32LE(data)
            return .float(Double(raw) / 1000.0)

        case .energy:
            let raw = readUInt32LE(data)
            return .float(Double(raw) / 1000.0)

        case .unixTime:
            let raw = readUInt32LE(data)
            return .timestamp(Date(timeIntervalSince1970: TimeInterval(raw)))

        case .accelerometer:
            let x = readInt16LE(data, offset: 0)
            let y = readInt16LE(data, offset: 2)
            let z = readInt16LE(data, offset: 4)
            return .vector3(
                x: Double(x) / 1000.0,
                y: Double(y) / 1000.0,
                z: Double(z) / 1000.0
            )

        case .gyrometer:
            let x = readInt16LE(data, offset: 0)
            let y = readInt16LE(data, offset: 2)
            let z = readInt16LE(data, offset: 4)
            return .vector3(
                x: Double(x) / 100.0,
                y: Double(y) / 100.0,
                z: Double(z) / 100.0
            )

        case .colour:
            return .rgb(red: data[0], green: data[1], blue: data[2])

        case .gps:
            // lat/lon: 0.0001° resolution, alt: 0.01m resolution
            let lat = readInt24LE(data, offset: 0)
            let lon = readInt24LE(data, offset: 3)
            let alt = readInt24LE(data, offset: 6)
            return .gps(
                latitude: Double(lat) / 10000.0,
                longitude: Double(lon) / 10000.0,
                altitude: Double(alt) / 100.0
            )
        }
    }

    // MARK: - Binary Reading Helpers

    private static func readInt16LE(_ data: Data, offset: Int = 0) -> Int16 {
        data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: Int16.self).littleEndian
        }
    }

    private static func readUInt16LE(_ data: Data, offset: Int = 0) -> UInt16 {
        data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private static func readInt32LE(_ data: Data, offset: Int = 0) -> Int32 {
        data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: Int32.self).littleEndian
        }
    }

    private static func readUInt32LE(_ data: Data, offset: Int = 0) -> UInt32 {
        data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    /// Read a 24-bit signed integer (little-endian)
    private static func readInt24LE(_ data: Data, offset: Int) -> Int32 {
        guard offset + 3 <= data.count else { return 0 }
        var value: Int32 = Int32(data[offset])
            | (Int32(data[offset + 1]) << 8)
            | (Int32(data[offset + 2]) << 16)
        // Sign extend if negative (bit 23 is set)
        if value & 0x800000 != 0 {
            value |= Int32(bitPattern: 0xFF000000)
        }
        return value
    }
}
