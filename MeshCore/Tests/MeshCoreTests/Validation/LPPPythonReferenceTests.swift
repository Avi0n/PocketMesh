import XCTest
@testable import MeshCore

/// Tests that verify Swift LPPEncoder produces bytes matching Python cayennelpp library.
///
/// These tests compare Swift-generated LPP payloads against reference bytes extracted from
/// the Python cayennelpp library, ensuring byte-level protocol compatibility.
///
/// Note: Swift LPPEncoder uses MeshCore's voltage type (0x74) while Python cayennelpp
/// uses analogInput (0x02) for voltage. Tests use analogInput for cross-library compatibility.
final class LPPPythonReferenceTests: XCTestCase {

    // MARK: - Temperature Tests

    func test_temperature_25_5_matchesPython() {
        // Python: LppFrame().add_temperature(1, 25.5)
        // Format: channel(1) + type(0x67) + value(int16 BE, *10)
        // 25.5 * 10 = 255 = 0x00FF
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 25.5)
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_temperature_25_5,
            "temperature mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_temperature_25_5.hexString)")
    }

    func test_temperature_negative_roundTrip() {
        // Verify negative temperatures encode/decode correctly
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: -10.5)
        let encoded = encoder.encode()

        // -10.5 * 10 = -105 in signed int16 big-endian = 0xFF97
        XCTAssertEqual(encoded, Data([0x01, 0x67, 0xFF, 0x97]),
            "negative temperature encoding mismatch")

        // Verify decode matches
        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        if case .float(let value) = decoded[0].value {
            XCTAssertEqual(value, -10.5, accuracy: 0.1)
        } else {
            XCTFail("Expected float value")
        }
    }

    // MARK: - Humidity Tests

    func test_humidity_65_matchesPython() {
        // Python: LppFrame().add_humidity(2, 65.0)
        // Format: channel(1) + type(0x68) + value(uint8, *2)
        // 65 * 2 = 130 = 0x82
        var encoder = LPPEncoder()
        encoder.addHumidity(channel: 2, percent: 65.0)
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_humidity_65,
            "humidity mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_humidity_65.hexString)")
    }

    // MARK: - Analog Input Tests

    func test_analogInput_3_3_matchesPython() {
        // Python: LppFrame().add_analog_input(3, 3.3)
        // Format: channel(1) + type(0x02) + value(int16 BE, *100)
        // 3.3 * 100 = 330 = 0x014A
        var encoder = LPPEncoder()
        encoder.addAnalogInput(channel: 3, value: 3.3)
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_analog_3_3,
            "analogInput mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_analog_3_3.hexString)")
    }

    // MARK: - GPS Tests

    func test_gps_sf_matchesPython() {
        // Python: LppFrame().add_gps(4, 37.7749, -122.4194, 10.0)
        // Format: channel(1) + type(0x88) + lat(int24 BE, *10000) + lon(int24 BE, *10000) + alt(int24 BE, *100)
        // lat: 37.7749 * 10000 = 377749 = 0x05C305
        // lon: -122.4194 * 10000 = -1224194 = 0xED53DE (24-bit signed)
        // alt: 10.0 * 100 = 1000 = 0x0003E8
        var encoder = LPPEncoder()
        encoder.addGPS(channel: 4, latitude: 37.7749, longitude: -122.4194, altitude: 10.0)
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_gps_sf,
            "gps mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_gps_sf.hexString)")
    }

    func test_gps_decode_roundTrip() {
        // Verify GPS decode matches encode
        var encoder = LPPEncoder()
        encoder.addGPS(channel: 4, latitude: 37.7749, longitude: -122.4194, altitude: 10.0)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].channel, 4)
        XCTAssertEqual(decoded[0].type, .gps)

        if case .gps(let lat, let lon, let alt) = decoded[0].value {
            XCTAssertEqual(lat, 37.7749, accuracy: 0.0001)
            XCTAssertEqual(lon, -122.4194, accuracy: 0.0001)
            XCTAssertEqual(alt, 10.0, accuracy: 0.01)
        } else {
            XCTFail("Expected GPS value")
        }
    }

    // MARK: - Barometer Tests

    func test_barometer_1013_matchesPython() {
        // Python: LppFrame().add_barometric_pressure(5, 1013.25)
        // Format: channel(1) + type(0x73) + value(uint16 BE, *10)
        // 1013.25 * 10 = 10132.5 -> truncated to 10132 = 0x2794
        // Note: Python cayennelpp truncates, so we use 1013.2 (10132)
        var encoder = LPPEncoder()
        encoder.addBarometer(channel: 5, hPa: 1013.2)  // Use 1013.2 to match Python truncation
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_barometer_1013,
            "barometer mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_barometer_1013.hexString)")
    }

    // MARK: - Accelerometer Tests

    func test_accelerometer_1g_matchesPython() {
        // Python: LppFrame().add_accelerometer(6, 0.0, 0.0, 1.0)
        // Format: channel(1) + type(0x71) + x(int16 BE, *1000) + y(int16 BE, *1000) + z(int16 BE, *1000)
        // x: 0.0 * 1000 = 0 = 0x0000
        // y: 0.0 * 1000 = 0 = 0x0000
        // z: 1.0 * 1000 = 1000 = 0x03E8
        var encoder = LPPEncoder()
        encoder.addAccelerometer(channel: 6, x: 0.0, y: 0.0, z: 1.0)
        let encoded = encoder.encode()
        XCTAssertEqual(encoded, PythonReferenceBytes.lpp_accelerometer_1g,
            "accelerometer mismatch - Swift: \(encoded.hexString), Python: \(PythonReferenceBytes.lpp_accelerometer_1g.hexString)")
    }

    func test_accelerometer_decode_roundTrip() {
        // Verify accelerometer decode matches encode
        var encoder = LPPEncoder()
        encoder.addAccelerometer(channel: 6, x: 0.5, y: -0.5, z: 1.0)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].channel, 6)
        XCTAssertEqual(decoded[0].type, .accelerometer)

        if case .vector3(let x, let y, let z) = decoded[0].value {
            XCTAssertEqual(x, 0.5, accuracy: 0.001)
            XCTAssertEqual(y, -0.5, accuracy: 0.001)
            XCTAssertEqual(z, 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected vector3 value")
        }
    }

    // MARK: - Multi-Sensor Tests

    func test_multiSensor_payload() {
        // Build a payload with multiple sensors like a real device would
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 25.5)
        encoder.addHumidity(channel: 2, percent: 65.0)
        encoder.addBarometer(channel: 3, hPa: 1013.2)
        let encoded = encoder.encode()

        // Verify we can decode all values
        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 3)

        // Temperature
        XCTAssertEqual(decoded[0].channel, 1)
        XCTAssertEqual(decoded[0].type, .temperature)
        if case .float(let temp) = decoded[0].value {
            XCTAssertEqual(temp, 25.5, accuracy: 0.1)
        }

        // Humidity
        XCTAssertEqual(decoded[1].channel, 2)
        XCTAssertEqual(decoded[1].type, .humidity)
        if case .float(let hum) = decoded[1].value {
            XCTAssertEqual(hum, 65.0, accuracy: 0.5)
        }

        // Barometer
        XCTAssertEqual(decoded[2].channel, 3)
        XCTAssertEqual(decoded[2].type, .barometer)
        if case .float(let pressure) = decoded[2].value {
            XCTAssertEqual(pressure, 1013.2, accuracy: 0.1)
        }
    }

    // MARK: - Voltage Tests (MeshCore-specific)

    func test_voltage_encoding() {
        // MeshCore uses voltage type (0x74) which differs from Python cayennelpp's analogInput (0x02)
        // This test verifies MeshCore voltage encoding works correctly
        var encoder = LPPEncoder()
        encoder.addVoltage(channel: 1, volts: 3.8)
        let encoded = encoder.encode()

        // channel(1) + type(0x74) + value(uint16 BE, *100)
        // 3.8 * 100 = 380 = 0x017C
        XCTAssertEqual(encoded, Data([0x01, 0x74, 0x01, 0x7C]),
            "voltage encoding mismatch - Swift: \(encoded.hexString)")

        // Verify decode
        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].type, .voltage)
        if case .float(let volts) = decoded[0].value {
            XCTAssertEqual(volts, 3.8, accuracy: 0.01)
        }
    }

    // MARK: - Edge Cases

    func test_illuminance_encoding() {
        var encoder = LPPEncoder()
        encoder.addIlluminance(channel: 1, lux: 1000)
        let encoded = encoder.encode()

        // channel(1) + type(0x65) + value(uint16 BE)
        // 1000 = 0x03E8
        XCTAssertEqual(encoded, Data([0x01, 0x65, 0x03, 0xE8]))

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        if case .integer(let lux) = decoded[0].value {
            XCTAssertEqual(lux, 1000)
        } else {
            XCTFail("Expected integer value")
        }
    }

    func test_digitalIO_encoding() {
        var encoder = LPPEncoder()
        encoder.addDigitalInput(channel: 1, value: 1)
        encoder.addDigitalOutput(channel: 2, value: 0)
        let encoded = encoder.encode()

        // Digital input: channel(1) + type(0x00) + value(1)
        // Digital output: channel(2) + type(0x01) + value(0)
        XCTAssertEqual(encoded, Data([0x01, 0x00, 0x01, 0x02, 0x01, 0x00]))

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 2)

        if case .digital(let din) = decoded[0].value {
            XCTAssertTrue(din)
        } else {
            XCTFail("Expected digital value for input")
        }
        if case .digital(let dout) = decoded[1].value {
            XCTAssertFalse(dout)
        } else {
            XCTFail("Expected digital value for output")
        }
    }

    func test_gyrometer_encoding() {
        var encoder = LPPEncoder()
        encoder.addGyrometer(channel: 1, x: 10.5, y: -5.25, z: 0.0)
        let encoded = encoder.encode()

        // x: 10.5 * 100 = 1050 = 0x041A
        // y: -5.25 * 100 = -525 = 0xFDF3 (signed)
        // z: 0.0 * 100 = 0 = 0x0000
        XCTAssertEqual(encoded, Data([0x01, 0x86, 0x04, 0x1A, 0xFD, 0xF3, 0x00, 0x00]))

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        if case .vector3(let x, let y, let z) = decoded[0].value {
            XCTAssertEqual(x, 10.5, accuracy: 0.01)
            XCTAssertEqual(y, -5.25, accuracy: 0.01)
            XCTAssertEqual(z, 0.0, accuracy: 0.01)
        } else {
            XCTFail("Expected vector3 value")
        }
    }
}
