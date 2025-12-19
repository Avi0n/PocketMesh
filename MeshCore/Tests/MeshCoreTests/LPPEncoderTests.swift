import Testing
@testable import MeshCore

@Suite("LPPEncoder Tests")
struct LPPEncoderTests {

    @Test("Temperature encoding")
    func temperatureEncoding() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 25.5)

        let data = encoder.encode()
        #expect(data.count == 4) // channel + type + 2 bytes
        #expect(data[0] == 1) // channel
        #expect(data[1] == LPPSensorType.temperature.rawValue)
        // 25.5 * 10 = 255 = 0x00FF little-endian
        #expect(data[2] == 0xFF) // Low byte first
        #expect(data[3] == 0x00) // High byte second
    }

    @Test("Negative temperature encoding")
    func negativeTemperatureEncoding() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: -10.5)

        let data = encoder.encode()
        // -10.5 * 10 = -105 = 0xFF97 little-endian (two's complement)
        #expect(data[2] == 0x97) // Low byte first
        #expect(data[3] == 0xFF) // High byte second
    }

    @Test("Humidity encoding")
    func humidityEncoding() {
        var encoder = LPPEncoder()
        encoder.addHumidity(channel: 2, percent: 65.5)

        let data = encoder.encode()
        #expect(data.count == 3) // channel + type + 1 byte
        // 65.5 * 2 = 131
        #expect(data[2] == 131)
    }

    @Test("GPS encoding")
    func gpsEncoding() {
        var encoder = LPPEncoder()
        encoder.addGPS(channel: 1, latitude: 37.7749, longitude: -122.4194, altitude: 10.5)

        let data = encoder.encode()
        #expect(data.count == 11) // channel + type + 9 bytes
        #expect(data[1] == LPPSensorType.gps.rawValue)
    }

    @Test("Round-trip temperature")
    func roundTripTemperature() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 5, celsius: 22.3)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        let point = decoded[0]
        #expect(point.channel == 5)
        #expect(point.type == .temperature)
        if case .float(let celsius) = point.value {
            #expect(abs(celsius - 22.3) < 0.1)
        } else {
            Issue.record("Expected .float value for temperature")
        }
    }

    @Test("Round-trip GPS")
    func roundTripGPS() {
        var encoder = LPPEncoder()
        encoder.addGPS(channel: 1, latitude: 37.7749, longitude: -122.4194, altitude: 25.0)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .gps(let lat, let lon, let alt) = decoded[0].value {
            #expect(abs(lat - 37.7749) < 0.001)
            #expect(abs(lon - (-122.4194)) < 0.001)
            #expect(abs(alt - 25.0) < 0.1)
        } else {
            Issue.record("Expected GPS value")
        }
    }

    @Test("Multiple sensors in one payload")
    func multipleSensors() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 20.0)
        encoder.addHumidity(channel: 2, percent: 50.0)
        encoder.addBarometer(channel: 3, hPa: 1013.25)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 3)
        #expect(decoded[0].channel == 1)
        #expect(decoded[1].channel == 2)
        #expect(decoded[2].channel == 3)
    }

    @Test("Reset clears buffer")
    func resetClearsBuffer() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 20.0)
        #expect(encoder.count == 4)

        encoder.reset()
        #expect(encoder.count == 0)
        #expect(encoder.encode().isEmpty)
    }

    @Test("Round-trip negative temperature")
    func roundTripNegativeTemperature() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: -15.5)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let celsius) = decoded[0].value {
            #expect(abs(celsius - (-15.5)) < 0.1)
        } else {
            Issue.record("Expected .float value for temperature")
        }
    }

    @Test("Round-trip negative GPS coordinates")
    func roundTripNegativeGPS() {
        var encoder = LPPEncoder()
        // Southern hemisphere, Western hemisphere
        encoder.addGPS(channel: 1, latitude: -33.8688, longitude: -70.6693, altitude: -5.0)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .gps(let lat, let lon, let alt) = decoded[0].value {
            #expect(abs(lat - (-33.8688)) < 0.001)
            #expect(abs(lon - (-70.6693)) < 0.001)
            #expect(abs(alt - (-5.0)) < 0.1)
        } else {
            Issue.record("Expected GPS value")
        }
    }

    @Test("Round-trip accelerometer vector")
    func roundTripAccelerometer() {
        var encoder = LPPEncoder()
        encoder.addAccelerometer(channel: 1, x: 0.5, y: -1.0, z: 9.8)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .vector3(let x, let y, let z) = decoded[0].value {
            #expect(abs(x - 0.5) < 0.01)
            #expect(abs(y - (-1.0)) < 0.01)
            #expect(abs(z - 9.8) < 0.01)
        } else {
            Issue.record("Expected vector3 value")
        }
    }

    @Test("Round-trip gyrometer vector")
    func roundTripGyrometer() {
        var encoder = LPPEncoder()
        encoder.addGyrometer(channel: 2, x: -45.5, y: 90.0, z: 0.25)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .vector3(let x, let y, let z) = decoded[0].value {
            #expect(abs(x - (-45.5)) < 0.1)
            #expect(abs(y - 90.0) < 0.1)
            #expect(abs(z - 0.25) < 0.1)
        } else {
            Issue.record("Expected vector3 value")
        }
    }

    @Test("Round-trip voltage")
    func roundTripVoltage() {
        var encoder = LPPEncoder()
        encoder.addVoltage(channel: 1, volts: 3.8657)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let volts) = decoded[0].value {
            #expect(abs(volts - 3.8657) < 0.0001)
        } else {
            Issue.record("Expected float value for voltage")
        }
    }

    @Test("Round-trip humidity")
    func roundTripHumidity() {
        var encoder = LPPEncoder()
        encoder.addHumidity(channel: 1, percent: 65.5)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let humidity) = decoded[0].value {
            #expect(abs(humidity - 65.5) < 0.5)
        } else {
            Issue.record("Expected float value for humidity")
        }
    }

    @Test("Round-trip barometer")
    func roundTripBarometer() {
        var encoder = LPPEncoder()
        encoder.addBarometer(channel: 1, hPa: 1013.25)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let pressure) = decoded[0].value {
            #expect(abs(pressure - 1013.2) < 0.2) // 0.1 resolution
        } else {
            Issue.record("Expected float value for barometer")
        }
    }

    @Test("Round-trip digital input")
    func roundTripDigitalInput() {
        var encoder = LPPEncoder()
        encoder.addDigitalInput(channel: 1, value: 1)
        encoder.addDigitalInput(channel: 2, value: 0)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 2)
        if case .digital(let value1) = decoded[0].value {
            #expect(value1 == true)
        } else {
            Issue.record("Expected digital value")
        }
        if case .digital(let value2) = decoded[1].value {
            #expect(value2 == false)
        } else {
            Issue.record("Expected digital value")
        }
    }

    @Test("Round-trip analog input")
    func roundTripAnalogInput() {
        var encoder = LPPEncoder()
        encoder.addAnalogInput(channel: 1, value: 2.56)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let value) = decoded[0].value {
            #expect(abs(value - 2.56) < 0.01)
        } else {
            Issue.record("Expected float value for analog input")
        }
    }

    @Test("Round-trip illuminance")
    func roundTripIlluminance() {
        var encoder = LPPEncoder()
        encoder.addIlluminance(channel: 1, lux: 500)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .integer(let lux) = decoded[0].value {
            #expect(lux == 500)
        } else {
            Issue.record("Expected integer value for illuminance")
        }
    }

    @Test("Round-trip current")
    func roundTripCurrent() {
        var encoder = LPPEncoder()
        encoder.addCurrent(channel: 1, milliamps: 1500)

        let encoded = encoder.encode()
        let decoded = LPPDecoder.decode(encoded)

        #expect(decoded.count == 1)
        if case .float(let amps) = decoded[0].value {
            #expect(abs(amps - 1.5) < 0.001) // 1500mA = 1.5A
        } else {
            Issue.record("Expected float value for current")
        }
    }
}
