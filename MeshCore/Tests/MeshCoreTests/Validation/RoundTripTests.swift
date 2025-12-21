import XCTest
@testable import MeshCore

/// Tests that verify Build → Parse → fields match (round-trip consistency)
///
/// These tests construct binary payloads, parse them using the Swift parsers,
/// and verify the parsed values match the original inputs.
final class RoundTripTests: XCTestCase {

    // MARK: - Contact Round-Trip

    func test_contact_roundTrip() {
        // Build a 147-byte contact response packet
        var data = Data()
        let publicKey = Data(repeating: 0xAA, count: 32)
        let type: UInt8 = 1
        let flags: UInt8 = 0x02
        let pathLen: Int8 = 3
        let pathBytes = Data([0x11, 0x22, 0x33]) + Data(repeating: 0, count: 61) // 64 bytes total
        let nameBytes = "TestContact".data(using: .utf8)!.prefix(32)
        let namePadded = nameBytes + Data(repeating: 0, count: 32 - nameBytes.count)
        let lastAdvert: UInt32 = 1704067200
        let lat: Int32 = 37_774_900  // 37.7749 * 1e6
        let lon: Int32 = -122_419_400  // -122.4194 * 1e6
        let lastMod: UInt32 = 1704067200

        data.append(publicKey)
        data.append(type)
        data.append(flags)
        data.append(UInt8(bitPattern: pathLen))
        data.append(pathBytes)
        data.append(namePadded)
        data.append(contentsOf: withUnsafeBytes(of: lastAdvert.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lat.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lon.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lastMod.littleEndian) { Data($0) })

        XCTAssertEqual(data.count, 147, "Contact payload should be 147 bytes")

        // Parse using Parsers.Contact
        let event = Parsers.Contact.parse(data)

        guard case .contact(let contact) = event else {
            XCTFail("Expected .contact event, got \(event)")
            return
        }

        // Verify round-trip
        XCTAssertEqual(contact.publicKey, publicKey)
        XCTAssertEqual(contact.type, type)
        XCTAssertEqual(contact.flags, flags)
        XCTAssertEqual(contact.outPathLength, pathLen)
        XCTAssertEqual(contact.outPath, Data([0x11, 0x22, 0x33]))
        XCTAssertEqual(contact.advertisedName, "TestContact")
        XCTAssertEqual(contact.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(contact.longitude, -122.4194, accuracy: 0.0001)
    }

    // MARK: - SelfInfo Round-Trip

    func test_selfInfo_roundTrip() {
        var data = Data()
        let advType: UInt8 = 1
        let txPower: UInt8 = 20
        let maxTxPower: UInt8 = 30
        let publicKey = Data(repeating: 0xBB, count: 32)
        let lat: Int32 = 37_774_900
        let lon: Int32 = -122_419_400
        let multiAcks: UInt8 = 1
        let advLocPolicy: UInt8 = 2
        // Telemetry mode: env=0 (bits 5-4), loc=1 (bits 3-2), base=2 (bits 1-0)
        let telemetryMode: UInt8 = ((0 & 0b11) << 4) | ((1 & 0b11) << 2) | (2 & 0b11)
        let manualAdd: UInt8 = 1
        let radioFreq: UInt32 = 906_875  // 906.875 MHz * 1000
        let radioBW: UInt32 = 250_000    // 250 kHz * 1000
        let radioSF: UInt8 = 11
        let radioCR: UInt8 = 8
        let name = "MyNode"

        data.append(advType)
        data.append(txPower)
        data.append(maxTxPower)
        data.append(publicKey)
        data.append(contentsOf: withUnsafeBytes(of: lat.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lon.littleEndian) { Data($0) })
        data.append(multiAcks)
        data.append(advLocPolicy)
        data.append(telemetryMode)
        data.append(manualAdd)
        data.append(contentsOf: withUnsafeBytes(of: radioFreq.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: radioBW.littleEndian) { Data($0) })
        data.append(radioSF)
        data.append(radioCR)
        data.append(name.data(using: .utf8)!)

        let event = Parsers.SelfInfo.parse(data)

        guard case .selfInfo(let info) = event else {
            XCTFail("Expected .selfInfo event, got \(event)")
            return
        }

        XCTAssertEqual(info.advertisementType, advType)
        XCTAssertEqual(info.txPower, txPower)
        XCTAssertEqual(info.maxTxPower, maxTxPower)
        XCTAssertEqual(info.publicKey, publicKey)
        XCTAssertEqual(info.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(info.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(info.multiAcks, multiAcks)
        XCTAssertEqual(info.advertisementLocationPolicy, advLocPolicy)
        XCTAssertEqual(info.telemetryModeEnvironment, 0)
        XCTAssertEqual(info.telemetryModeLocation, 1)
        XCTAssertEqual(info.telemetryModeBase, 2)
        XCTAssertEqual(info.manualAddContacts, true)
        XCTAssertEqual(info.radioFrequency, 906.875, accuracy: 0.001)
        XCTAssertEqual(info.radioBandwidth, 250.0, accuracy: 0.001)
        XCTAssertEqual(info.radioSpreadingFactor, radioSF)
        XCTAssertEqual(info.radioCodingRate, radioCR)
        XCTAssertEqual(info.name, "MyNode")
    }

    // MARK: - Message Round-Trip

    func test_contactMessage_v3_roundTrip() {
        var data = Data()
        let snrRaw: Int8 = 24  // 6.0 dB * 4
        let reserved: UInt16 = 0
        let pubkeyPrefix = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
        let pathLen: UInt8 = 2
        let txtType: UInt8 = 0  // plain text
        let timestamp: UInt32 = 1704067200
        let text = "Hello World"

        data.append(UInt8(bitPattern: snrRaw))
        data.append(contentsOf: withUnsafeBytes(of: reserved.littleEndian) { Data($0) })
        data.append(pubkeyPrefix)
        data.append(pathLen)
        data.append(txtType)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Data($0) })
        data.append(text.data(using: .utf8)!)

        let event = Parsers.ContactMessage.parse(data, version: .v3)

        guard case .contactMessageReceived(let msg) = event else {
            XCTFail("Expected .contactMessageReceived event, got \(event)")
            return
        }

        XCTAssertEqual(msg.snr ?? 0, 6.0, accuracy: 0.01)
        XCTAssertEqual(msg.senderPublicKeyPrefix, pubkeyPrefix)
        XCTAssertEqual(msg.pathLength, pathLen)
        XCTAssertEqual(msg.textType, txtType)
        XCTAssertEqual(msg.text, "Hello World")
    }

    func test_channelMessage_v3_roundTrip() {
        var data = Data()
        let snrRaw: Int8 = -20  // -5.0 dB * 4
        let reserved: UInt16 = 0
        let channel: UInt8 = 2
        let pathLen: UInt8 = 0
        let txtType: UInt8 = 0
        let timestamp: UInt32 = 1704067200
        let text = "Broadcast message"

        data.append(UInt8(bitPattern: snrRaw))
        data.append(contentsOf: withUnsafeBytes(of: reserved.littleEndian) { Data($0) })
        data.append(channel)
        data.append(pathLen)
        data.append(txtType)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Data($0) })
        data.append(text.data(using: .utf8)!)

        let event = Parsers.ChannelMessage.parse(data, version: .v3)

        guard case .channelMessageReceived(let msg) = event else {
            XCTFail("Expected .channelMessageReceived event, got \(event)")
            return
        }

        XCTAssertEqual(msg.snr ?? 0, -5.0, accuracy: 0.01)
        XCTAssertEqual(msg.channelIndex, channel)
        XCTAssertEqual(msg.pathLength, pathLen)
        XCTAssertEqual(msg.text, "Broadcast message")
    }

    // MARK: - StatusResponse Round-Trip

    func test_statusResponse_roundTrip() {
        var data = Data()
        let pubkeyPrefix = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
        let battery: UInt16 = 3800
        let txQueue: UInt16 = 5
        let noiseFloor: Int16 = -110
        let lastRSSI: Int16 = -85
        let packetsRecv: UInt32 = 1000
        let packetsSent: UInt32 = 500
        let airtime: UInt32 = 3600
        let uptime: UInt32 = 86400
        let sentFlood: UInt32 = 100
        let sentDirect: UInt32 = 400
        let recvFlood: UInt32 = 200
        let recvDirect: UInt32 = 800
        let fullEvents: UInt16 = 10
        let lastSNRRaw: Int16 = 24  // 6.0 * 4
        let directDups: UInt16 = 5
        let floodDups: UInt16 = 15
        let rxAirtime: UInt32 = 1800

        data.append(0x00)  // Reserved byte (per firmware format)
        data.append(pubkeyPrefix)
        data.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: txQueue.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: noiseFloor.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lastRSSI.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: packetsRecv.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: packetsSent.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: airtime.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: sentFlood.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: sentDirect.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: recvFlood.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: recvDirect.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: fullEvents.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: lastSNRRaw.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: directDups.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: floodDups.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: rxAirtime.littleEndian) { Data($0) })

        let event = Parsers.StatusResponse.parse(data)

        guard case .statusResponse(let status) = event else {
            XCTFail("Expected .statusResponse event, got \(event)")
            return
        }

        XCTAssertEqual(status.publicKeyPrefix, pubkeyPrefix)
        XCTAssertEqual(status.battery, Int(battery))
        XCTAssertEqual(status.txQueueLength, Int(txQueue))
        XCTAssertEqual(status.noiseFloor, Int(noiseFloor))
        XCTAssertEqual(status.lastRSSI, Int(lastRSSI))
        XCTAssertEqual(status.packetsReceived, packetsRecv)
        XCTAssertEqual(status.packetsSent, packetsSent)
        XCTAssertEqual(status.airtime, airtime)
        XCTAssertEqual(status.uptime, uptime)
        XCTAssertEqual(status.sentFlood, sentFlood)
        XCTAssertEqual(status.sentDirect, sentDirect)
        XCTAssertEqual(status.receivedFlood, recvFlood)
        XCTAssertEqual(status.receivedDirect, recvDirect)
        XCTAssertEqual(status.fullEvents, Int(fullEvents))
        XCTAssertEqual(status.lastSNR, 6.0, accuracy: 0.01)
        XCTAssertEqual(status.directDuplicates, Int(directDups))
        XCTAssertEqual(status.floodDuplicates, Int(floodDups))
        XCTAssertEqual(status.rxAirtime, rxAirtime)
    }

    // MARK: - Stats Round-Trip

    func test_coreStats_roundTrip() {
        var data = Data()
        let batteryMV: UInt16 = 3750
        let uptime: UInt32 = 86400
        let errors: UInt16 = 3
        let queueLen: UInt8 = 5

        data.append(contentsOf: withUnsafeBytes(of: batteryMV.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: errors.littleEndian) { Data($0) })
        data.append(queueLen)

        let event = Parsers.CoreStats.parse(data)

        guard case .statsCore(let stats) = event else {
            XCTFail("Expected .statsCore event, got \(event)")
            return
        }

        XCTAssertEqual(stats.batteryMV, batteryMV)
        XCTAssertEqual(stats.uptimeSeconds, uptime)
        XCTAssertEqual(stats.errors, errors)
        XCTAssertEqual(stats.queueLength, queueLen)
    }

    func test_radioStats_roundTrip() {
        var data = Data()
        let noiseFloor: Int16 = -115
        let lastRSSI: Int8 = -90
        let lastSNRRaw: Int8 = 28  // 7.0 * 4
        let txAir: UInt32 = 1000
        let rxAir: UInt32 = 2000

        data.append(contentsOf: withUnsafeBytes(of: noiseFloor.littleEndian) { Data($0) })
        data.append(UInt8(bitPattern: lastRSSI))
        data.append(UInt8(bitPattern: lastSNRRaw))
        data.append(contentsOf: withUnsafeBytes(of: txAir.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: rxAir.littleEndian) { Data($0) })

        let event = Parsers.RadioStats.parse(data)

        guard case .statsRadio(let stats) = event else {
            XCTFail("Expected .statsRadio event, got \(event)")
            return
        }

        XCTAssertEqual(stats.noiseFloor, noiseFloor)
        XCTAssertEqual(stats.lastRSSI, lastRSSI)
        XCTAssertEqual(stats.lastSNR, 7.0, accuracy: 0.01)
        XCTAssertEqual(stats.txAirtimeSeconds, txAir)
        XCTAssertEqual(stats.rxAirtimeSeconds, rxAir)
    }

    func test_packetStats_roundTrip() {
        var data = Data()
        let received: UInt32 = 1000
        let sent: UInt32 = 500
        let floodTx: UInt32 = 100
        let directTx: UInt32 = 400
        let floodRx: UInt32 = 200
        let directRx: UInt32 = 800

        data.append(contentsOf: withUnsafeBytes(of: received.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: sent.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: floodTx.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: directTx.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: floodRx.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: directRx.littleEndian) { Data($0) })

        let event = Parsers.PacketStats.parse(data)

        guard case .statsPackets(let stats) = event else {
            XCTFail("Expected .statsPackets event, got \(event)")
            return
        }

        XCTAssertEqual(stats.received, received)
        XCTAssertEqual(stats.sent, sent)
        XCTAssertEqual(stats.floodTx, floodTx)
        XCTAssertEqual(stats.directTx, directTx)
        XCTAssertEqual(stats.floodRx, floodRx)
        XCTAssertEqual(stats.directRx, directRx)
    }

    // MARK: - ChannelInfo Round-Trip

    func test_channelInfo_roundTrip() {
        var data = Data()
        let index: UInt8 = 1
        let name = "TestChannel"
        let nameBytes = name.data(using: .utf8)!.prefix(32)
        let namePadded = nameBytes + Data(repeating: 0, count: 32 - nameBytes.count)
        let secret = Data(0..<16)

        data.append(index)
        data.append(namePadded)
        data.append(secret)

        let event = Parsers.ChannelInfo.parse(data)

        guard case .channelInfo(let info) = event else {
            XCTFail("Expected .channelInfo event, got \(event)")
            return
        }

        XCTAssertEqual(info.index, index)
        XCTAssertEqual(info.name, "TestChannel")
        XCTAssertEqual(info.secret, secret)
    }

    func test_channelInfo_handlesGarbageBytesAfterNull() {
        // Firmware uses strcpy which leaves uninitialized garbage after the null terminator.
        // This test verifies we correctly parse only up to the null byte.
        var data = Data()
        let index: UInt8 = 2
        let name = "Primary"
        let nameBytes = name.data(using: .utf8)!
        var namePadded = nameBytes
        namePadded.append(0) // Null terminator
        // Append garbage bytes (invalid UTF-8 sequences) to simulate uninitialized memory
        let garbageBytes = Data([0xFF, 0xFE, 0x80, 0x81, 0xC0, 0xC1])
        namePadded.append(garbageBytes)
        // Pad to 32 bytes total
        namePadded.append(Data(repeating: 0xAB, count: 32 - namePadded.count))
        let secret = Data(repeating: 0xCC, count: 16)

        data.append(index)
        data.append(namePadded)
        data.append(secret)

        let event = Parsers.ChannelInfo.parse(data)

        guard case .channelInfo(let info) = event else {
            XCTFail("Expected .channelInfo event, got \(event)")
            return
        }

        XCTAssertEqual(info.index, index)
        XCTAssertEqual(info.name, "Primary", "Name should be parsed up to null terminator, ignoring garbage bytes")
        XCTAssertEqual(info.secret, secret)
    }

    // MARK: - CustomVars Round-Trip

    func test_customVars_roundTrip() {
        let varString = "key1:value1,key2:value2,mode:auto"
        let data = varString.data(using: .utf8)!

        let event = Parsers.CustomVars.parse(data)

        guard case .customVars(let vars) = event else {
            XCTFail("Expected .customVars event, got \(event)")
            return
        }

        XCTAssertEqual(vars["key1"], "value1")
        XCTAssertEqual(vars["key2"], "value2")
        XCTAssertEqual(vars["mode"], "auto")
    }

    // MARK: - LPP Round-Trip

    func test_lppEncoder_decoder_temperature_roundTrip() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 22.5)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].channel, 1)
        XCTAssertEqual(decoded[0].type, .temperature)

        if case .float(let value) = decoded[0].value {
            XCTAssertEqual(value, 22.5, accuracy: 0.1)
        } else {
            XCTFail("Expected float value")
        }
    }

    func test_lppEncoder_decoder_gps_roundTrip() {
        var encoder = LPPEncoder()
        encoder.addGPS(channel: 3, latitude: 37.7749, longitude: -122.4194, altitude: 50.0)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].channel, 3)
        XCTAssertEqual(decoded[0].type, .gps)

        if case .gps(let lat, let lon, let alt) = decoded[0].value {
            XCTAssertEqual(lat, 37.7749, accuracy: 0.0001)
            XCTAssertEqual(lon, -122.4194, accuracy: 0.0001)
            XCTAssertEqual(alt, 50.0, accuracy: 0.01)
        } else {
            XCTFail("Expected GPS value")
        }
    }

    func test_lppEncoder_decoder_multiSensor_roundTrip() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: 25.0)
        encoder.addHumidity(channel: 2, percent: 60.0)
        encoder.addVoltage(channel: 3, volts: 3.7)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 3)

        XCTAssertEqual(decoded[0].channel, 1)
        XCTAssertEqual(decoded[0].type, .temperature)
        if case .float(let temp) = decoded[0].value {
            XCTAssertEqual(temp, 25.0, accuracy: 0.1)
        }

        XCTAssertEqual(decoded[1].channel, 2)
        XCTAssertEqual(decoded[1].type, .humidity)
        if case .float(let humidity) = decoded[1].value {
            XCTAssertEqual(humidity, 60.0, accuracy: 0.5)
        }

        XCTAssertEqual(decoded[2].channel, 3)
        XCTAssertEqual(decoded[2].type, .voltage)
        if case .float(let volts) = decoded[2].value {
            XCTAssertEqual(volts, 3.7, accuracy: 0.01)
        }
    }

    func test_lppEncoder_decoder_negativeTemperature_roundTrip() {
        var encoder = LPPEncoder()
        encoder.addTemperature(channel: 1, celsius: -15.5)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)

        if case .float(let temp) = decoded[0].value {
            XCTAssertEqual(temp, -15.5, accuracy: 0.1)
        } else {
            XCTFail("Expected float value for temperature")
        }
    }

    func test_lppEncoder_decoder_accelerometer_roundTrip() {
        var encoder = LPPEncoder()
        encoder.addAccelerometer(channel: 5, x: -0.5, y: 0.25, z: 1.0)
        let encoded = encoder.encode()

        let decoded = LPPDecoder.decode(encoded)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].type, .accelerometer)

        if case .vector3(let x, let y, let z) = decoded[0].value {
            XCTAssertEqual(x, -0.5, accuracy: 0.001)
            XCTAssertEqual(y, 0.25, accuracy: 0.001)
            XCTAssertEqual(z, 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected vector3 value for accelerometer")
        }
    }
}
