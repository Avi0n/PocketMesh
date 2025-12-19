import Foundation
import Testing
@testable import MeshCore

@Suite("LPP Decoder Tests")
struct LPPDecoderTests {

    // MARK: - Sensor Type Properties

    @Test("Sensor type data sizes are correct")
    func sensorTypeDataSizes() {
        #expect(LPPSensorType.digitalInput.dataSize == 1)
        #expect(LPPSensorType.digitalOutput.dataSize == 1)
        #expect(LPPSensorType.presence.dataSize == 1)
        #expect(LPPSensorType.humidity.dataSize == 1)
        #expect(LPPSensorType.percentage.dataSize == 1)
        #expect(LPPSensorType.switchValue.dataSize == 1)

        #expect(LPPSensorType.temperature.dataSize == 2)
        #expect(LPPSensorType.barometer.dataSize == 2)
        #expect(LPPSensorType.voltage.dataSize == 2)
        #expect(LPPSensorType.current.dataSize == 2)
        #expect(LPPSensorType.illuminance.dataSize == 2)
        #expect(LPPSensorType.altitude.dataSize == 2)

        #expect(LPPSensorType.colour.dataSize == 3)

        #expect(LPPSensorType.genericSensor.dataSize == 4)
        #expect(LPPSensorType.frequency.dataSize == 4)
        #expect(LPPSensorType.distance.dataSize == 4)
        #expect(LPPSensorType.energy.dataSize == 4)
        #expect(LPPSensorType.unixTime.dataSize == 4)

        #expect(LPPSensorType.accelerometer.dataSize == 6)
        #expect(LPPSensorType.gyrometer.dataSize == 6)

        #expect(LPPSensorType.gps.dataSize == 9)
    }

    @Test("Sensor type names are human readable")
    func sensorTypeNames() {
        #expect(LPPSensorType.temperature.name == "Temperature")
        #expect(LPPSensorType.gps.name == "GPS")
        #expect(LPPSensorType.voltage.name == "Voltage")
    }

    // MARK: - Digital Types (1 byte)

    @Test("Decode digital input")
    func decodeDigitalInput() {
        let data = Data([0x01, 0x00, 0x01])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 1)
        #expect(result[0].channel == 1)
        #expect(result[0].type == .digitalInput)
        #expect(result[0].value == .digital(true))

        let offData = Data([0x02, 0x00, 0x00])
        let offResult = LPPDecoder.decode(offData)
        #expect(offResult[0].value == .digital(false))
    }

    @Test("Decode percentage")
    func decodePercentage() {
        let data = Data([0x01, 0x78, 0x64])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 1)
        #expect(result[0].type == .percentage)
        #expect(result[0].value == .integer(100))
    }

    @Test("Decode humidity")
    func decodeHumidity() {
        let data = Data([0x01, 0x68, 0x64])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 1)
        #expect(result[0].type == .humidity)
        if case .float(let val) = result[0].value {
            #expect(abs(val - 50.0) < 0.1)
        } else {
            Issue.record("Expected float value for humidity")
        }
    }

    // MARK: - 2-Byte Types

    @Test("Decode temperature")
    func decodeTemperature() {
        let data = Data([0x01, 0x67, 0x11, 0x01])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 1)
        #expect(result[0].type == .temperature)
        if case .float(let val) = result[0].value {
            #expect(abs(val - 27.3) < 0.1)
        } else {
            Issue.record("Expected float value for temperature")
        }
    }

    @Test("Decode negative temperature")
    func decodeNegativeTemperature() {
        let raw: Int16 = -100
        let bytes = withUnsafeBytes(of: raw.littleEndian) { Array($0) }
        let data = Data([0x01, 0x67] + bytes)
        let result = LPPDecoder.decode(data)
        if case .float(let val) = result[0].value {
            #expect(abs(val - (-10.0)) < 0.1)
        } else {
            Issue.record("Expected float value for negative temperature")
        }
    }

    @Test("Decode voltage")
    func decodeVoltage() {
        let raw: UInt16 = 38657
        let bytes = withUnsafeBytes(of: raw.littleEndian) { Array($0) }
        let data = Data([0x01, 0x74] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result.count == 1)
        #expect(result[0].type == .voltage)
        if case .float(let val) = result[0].value {
            #expect(abs(val - 3.8657) < 0.0001)
        } else {
            Issue.record("Expected float value for voltage")
        }
    }

    @Test("Decode illuminance")
    func decodeIlluminance() {
        let raw: UInt16 = 1000
        let bytes = withUnsafeBytes(of: raw.littleEndian) { Array($0) }
        let data = Data([0x01, 0x65] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .illuminance)
        #expect(result[0].value == .integer(1000))
    }

    // MARK: - 4-Byte Types

    @Test("Decode unix time")
    func decodeUnixTime() {
        let timestamp: UInt32 = 1702828800
        let bytes = withUnsafeBytes(of: timestamp.littleEndian) { Array($0) }
        let data = Data([0x01, 0x85] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .unixTime)
        if case .timestamp(let date) = result[0].value {
            #expect(date.timeIntervalSince1970 == Double(timestamp))
        } else {
            Issue.record("Expected timestamp value")
        }
    }

    @Test("Decode frequency")
    func decodeFrequency() {
        let freq: UInt32 = 915000000
        let bytes = withUnsafeBytes(of: freq.littleEndian) { Array($0) }
        let data = Data([0x01, 0x76] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .frequency)
        #expect(result[0].value == .integer(915000000))
    }

    // MARK: - 6-Byte Vector Types

    @Test("Decode accelerometer")
    func decodeAccelerometer() {
        let x: Int16 = 100
        let y: Int16 = -200
        let z: Int16 = 1000
        var bytes: [UInt8] = []
        bytes += withUnsafeBytes(of: x.littleEndian) { Array($0) }
        bytes += withUnsafeBytes(of: y.littleEndian) { Array($0) }
        bytes += withUnsafeBytes(of: z.littleEndian) { Array($0) }
        let data = Data([0x01, 0x71] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .accelerometer)
        if case .vector3(let vx, let vy, let vz) = result[0].value {
            #expect(abs(vx - 0.1) < 0.001)
            #expect(abs(vy - (-0.2)) < 0.001)
            #expect(abs(vz - 1.0) < 0.001)
        } else {
            Issue.record("Expected vector3 value")
        }
    }

    // MARK: - GPS (9 bytes)

    @Test("Decode GPS coordinates")
    func decodeGPS() {
        func encode24BitLE(_ value: Int32) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF)]
        }

        let lat: Int32 = 378600
        let lon: Int32 = -1224000
        let alt: Int32 = 10000
        var bytes: [UInt8] = []
        bytes += encode24BitLE(lat)
        bytes += encode24BitLE(lon)
        bytes += encode24BitLE(alt)
        let data = Data([0x01, 0x88] + bytes)
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .gps)
        if case .gps(let latitude, let longitude, let altitude) = result[0].value {
            #expect(abs(latitude - 37.86) < 0.01)
            #expect(abs(longitude - (-122.4)) < 0.01)
            #expect(abs(altitude - 100.0) < 0.1)
        } else {
            Issue.record("Expected gps value")
        }
    }

    // MARK: - Colour (3 bytes)

    @Test("Decode colour")
    func decodeColour() {
        let data = Data([0x01, 0x87, 0xFF, 0x80, 0x00])
        let result = LPPDecoder.decode(data)
        #expect(result[0].type == .colour)
        #expect(result[0].value == .rgb(red: 255, green: 128, blue: 0))
    }

    // MARK: - Multiple Readings

    @Test("Decode multiple readings in single frame")
    func decodeMultipleReadings() {
        var data = Data()
        data.append(contentsOf: [0x01, 0x67, 0x11, 0x01])
        data.append(contentsOf: [0x02, 0x68, 0x64])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 2)
        #expect(result[0].channel == 1)
        #expect(result[0].type == .temperature)
        #expect(result[1].channel == 2)
        #expect(result[1].type == .humidity)
    }

    // MARK: - Edge Cases

    @Test("Empty data returns empty array")
    func decodeEmptyData() {
        let result = LPPDecoder.decode(Data())
        #expect(result.isEmpty)
    }

    @Test("Truncated data stops parsing")
    func decodeTruncatedData() {
        let data = Data([0x01, 0x67, 0x01])
        let result = LPPDecoder.decode(data)
        #expect(result.isEmpty)
    }

    @Test("Digital input type (0x00) is parsed correctly")
    func decodeDigitalInputType() {
        var data = Data([0x01, 0x67, 0x11, 0x01])
        data.append(contentsOf: [0x02, 0x00, 0x01])
        let result = LPPDecoder.decode(data)
        #expect(result.count == 2)
        #expect(result[1].type == .digitalInput)
    }

    @Test("Unknown sensor type stops parsing")
    func decodeUnknownType() {
        let data = Data([0x01, 0xFF, 0x00, 0x00])
        let result = LPPDecoder.decode(data)
        #expect(result.isEmpty)
    }

    // MARK: - Display Extension

    @Test("Battery percentage from voltage")
    func batteryPercentage() {
        let fullBattery = LPPDataPoint(channel: 1, type: .voltage, value: .float(4.2))
        #expect(fullBattery.batteryPercentage == 100)

        let emptyBattery = LPPDataPoint(channel: 1, type: .voltage, value: .float(3.0))
        #expect(emptyBattery.batteryPercentage == 0)

        let halfBattery = LPPDataPoint(channel: 1, type: .voltage, value: .float(3.6))
        #expect(halfBattery.batteryPercentage == 50)

        let notVoltage = LPPDataPoint(channel: 1, type: .temperature, value: .float(25.0))
        #expect(notVoltage.batteryPercentage == nil)
    }

    @Test("Formatted values are correct")
    func formattedValues() {
        let temp = LPPDataPoint(channel: 1, type: .temperature, value: .float(25.5))
        #expect(temp.formattedValue.contains("25.5"))
        #expect(temp.formattedValue.contains("C"))

        let digital = LPPDataPoint(channel: 1, type: .digitalInput, value: .digital(true))
        #expect(digital.formattedValue == "On")

        let percent = LPPDataPoint(channel: 1, type: .percentage, value: .integer(75))
        #expect(percent.formattedValue == "75%")
    }
}
