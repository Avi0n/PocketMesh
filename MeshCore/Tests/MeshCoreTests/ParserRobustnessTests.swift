import Foundation
import Testing
@testable import MeshCore

// MARK: - Malformed Packet Tests

@Suite("Malformed Packet Tests")
struct MalformedPacketTests {

    @Test("Parser handles truncated contact packet")
    func truncatedContact() {
        // Contact should be 147 bytes, send only 50
        var data = Data([ResponseCode.contact.rawValue])
        data.append(Data(repeating: 0xAB, count: 50))
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated contact, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated selfInfo packet")
    func truncatedSelfInfo() {
        // SelfInfo should be 55+ bytes, send only 30
        var data = Data([ResponseCode.selfInfo.rawValue])
        data.append(Data(repeating: 0x00, count: 30))
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated selfInfo, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated battery packet")
    func truncatedBattery() {
        // Battery needs at least 2 bytes for level
        let data = Data([ResponseCode.battery.rawValue, 0x42])
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated battery, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated currentTime packet")
    func truncatedCurrentTime() {
        // CurrentTime needs 4 bytes for timestamp
        var data = Data([ResponseCode.currentTime.rawValue])
        data.append(contentsOf: [0x00, 0x00]) // Only 2 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated currentTime, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated messageSent packet")
    func truncatedMessageSent() {
        // MessageSent needs 9 bytes
        var data = Data([ResponseCode.messageSent.rawValue])
        data.append(contentsOf: [0x00, 0x01, 0x02]) // Only 3 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated messageSent, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated acknowledgement packet")
    func truncatedAck() {
        // ACK needs 4 bytes for ack code
        let data = Data([ResponseCode.ack.rawValue, 0xDE, 0xAD]) // Only 2 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated ack, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated contactsStart packet")
    func truncatedContactsStart() {
        // ContactsStart needs 2 bytes for count
        let data = Data([ResponseCode.contactStart.rawValue, 0x0A]) // Only 1 byte
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated contactsStart, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated signStart packet")
    func truncatedSignStart() {
        // SignStart needs 5 bytes (1 reserved + 4 max_length)
        let data = Data([ResponseCode.signStart.rawValue, 0x00, 0x00]) // Only 2 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated signStart, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated contactMessage v1")
    func truncatedContactMessageV1() {
        // ContactMessage v1 needs 12 bytes minimum
        var data = Data([ResponseCode.contactMessageReceived.rawValue])
        data.append(Data(repeating: 0x00, count: 8)) // Only 8 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated contactMessage v1, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated contactMessage v3")
    func truncatedContactMessageV3() {
        // ContactMessage v3 needs 15 bytes minimum
        var data = Data([ResponseCode.contactMessageReceivedV3.rawValue])
        data.append(Data(repeating: 0x00, count: 10)) // Only 10 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated contactMessage v3, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated statusResponse packet")
    func truncatedStatusResponse() {
        // StatusResponse needs 47 bytes
        var data = Data([ResponseCode.statusResponse.rawValue])
        data.append(Data(repeating: 0x00, count: 20)) // Only 20 bytes
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated statusResponse, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated coreStats packet")
    func truncatedCoreStats() {
        // CoreStats needs 9 bytes
        var data = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
        data.append(Data(repeating: 0x00, count: 5)) // Only 5 bytes after type
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated coreStats, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated radioStats packet")
    func truncatedRadioStats() {
        // RadioStats needs 12 bytes
        var data = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
        data.append(Data(repeating: 0x00, count: 8)) // Only 8 bytes after type
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated radioStats, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles truncated packetStats packet")
    func truncatedPacketStats() {
        // PacketStats needs 24 bytes
        var data = Data([ResponseCode.stats.rawValue, StatsType.packets.rawValue])
        data.append(Data(repeating: 0x00, count: 16)) // Only 16 bytes after type
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for truncated packetStats, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("Parser handles unknown stats type")
    func unknownStatsType() {
        var data = Data([ResponseCode.stats.rawValue, 0xFF]) // Unknown type
        data.append(Data(repeating: 0x00, count: 20))
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for unknown stats type, got \(event)")
            return
        }
        #expect(reason.contains("Unknown stats type"))
    }
}

// MARK: - Extended Parser Tests for New Fixtures

@Suite("Extended Parser Tests")
struct ExtendedParserTests {

    @Test("Parse statusResponse from full packet")
    func parseStatusResponse() {
        var data = Data([ResponseCode.statusResponse.rawValue])
        data.append(TestFixtures.statusResponsePayload)
        let event = PacketParser.parse(data)

        guard case .statusResponse(let response) = event else {
            Issue.record("Expected statusResponse event, got \(event)")
            return
        }
        #expect(response.publicKeyPrefix == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        #expect(response.battery == 4100)
        #expect(response.txQueueLength == 5)
        #expect(response.noiseFloor == -110)
        #expect(response.lastRSSI == -75)
        #expect(response.packetsReceived == 1000)
        #expect(response.packetsSent == 500)
        #expect(response.uptime == 86400)
        #expect(abs(response.lastSNR - 8.5) < 0.01)
    }

    @Test("Parse loginFailed with pubkey prefix")
    func parseLoginFailed() {
        var data = Data([ResponseCode.loginFailed.rawValue])
        data.append(TestFixtures.loginFailedPayload)
        let event = PacketParser.parse(data)

        guard case .loginFailed(let prefix) = event else {
            Issue.record("Expected loginFailed event, got \(event)")
            return
        }
        #expect(prefix == Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]))
    }

    @Test("Parse loginFailed minimal (no pubkey)")
    func parseLoginFailedMinimal() {
        var data = Data([ResponseCode.loginFailed.rawValue])
        data.append(TestFixtures.loginFailedMinimalPayload)
        let event = PacketParser.parse(data)

        guard case .loginFailed(let prefix) = event else {
            Issue.record("Expected loginFailed event, got \(event)")
            return
        }
        #expect(prefix == nil)
    }

    @Test("Parse signStart")
    func parseSignStart() {
        var data = Data([ResponseCode.signStart.rawValue])
        data.append(TestFixtures.signStartPayload)
        let event = PacketParser.parse(data)

        guard case .signStart(let maxLength) = event else {
            Issue.record("Expected signStart event, got \(event)")
            return
        }
        #expect(maxLength == 256)
    }

    @Test("Parse loginSuccess with admin flag")
    func parseLoginSuccess() {
        var data = Data([ResponseCode.loginSuccess.rawValue])
        data.append(TestFixtures.loginSuccessPayload)
        let event = PacketParser.parse(data)

        guard case .loginSuccess(let info) = event else {
            Issue.record("Expected loginSuccess event, got \(event)")
            return
        }
        #expect(info.isAdmin == true)
        #expect(info.permissions == 0x01)
        #expect(info.publicKeyPrefix == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
    }

    @Test("Parse channelInfo")
    func parseChannelInfo() {
        var data = Data([ResponseCode.channelInfo.rawValue])
        data.append(TestFixtures.channelInfoPayload)
        let event = PacketParser.parse(data)

        guard case .channelInfo(let info) = event else {
            Issue.record("Expected channelInfo event, got \(event)")
            return
        }
        #expect(info.index == 1)
        #expect(info.name == "TestChannel")
        #expect(info.secret.count == 16)
    }

    @Test("Parse traceData")
    func parseTraceData() {
        var data = Data([ResponseCode.traceData.rawValue])
        data.append(TestFixtures.traceDataPayload)
        let event = PacketParser.parse(data)

        guard case .traceData(let info) = event else {
            Issue.record("Expected traceData event, got \(event)")
            return
        }
        #expect(info.tag == 12345)
        #expect(info.authCode == 67890)
        #expect(info.flags == 0x01)
        #expect(info.pathLength == 2)
        #expect(info.path.count == 3)
        #expect(info.path[0].hash == 0x11)
        #expect(abs(info.path[0].snr - 5.0) < 0.01)
        #expect(info.path[1].hash == 0x22)
        #expect(abs(info.path[1].snr - (-4.0)) < 0.01)
        #expect(info.path[2].hash == nil)
        #expect(abs(info.path[2].snr - 3.0) < 0.01)
    }

    @Test("Parse controlData")
    func parseControlData() {
        var data = Data([ResponseCode.controlData.rawValue])
        data.append(TestFixtures.controlDataPayload)
        let event = PacketParser.parse(data)

        guard case .controlData(let info) = event else {
            Issue.record("Expected controlData event, got \(event)")
            return
        }
        #expect(abs(info.snr - 6.0) < 0.01)
        #expect(info.rssi == -80)
        #expect(info.pathLength == 2)
        #expect(info.payloadType == 1)
        #expect(info.payload == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("Parse pathDiscoveryResponse")
    func parsePathDiscovery() {
        var data = Data([ResponseCode.pathDiscoveryResponse.rawValue])
        data.append(TestFixtures.pathDiscoveryPayload)
        let event = PacketParser.parse(data)

        guard case .pathResponse(let info) = event else {
            Issue.record("Expected pathResponse event, got \(event)")
            return
        }
        #expect(info.publicKeyPrefix == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        #expect(info.outPath == Data([0x11, 0x22]))
        #expect(info.inPath == Data([0x33, 0x44, 0x55]))
    }

    @Test("Parse telemetryResponse")
    func parseTelemetryResponse() {
        var data = Data([ResponseCode.telemetryResponse.rawValue])
        data.append(TestFixtures.telemetryResponsePayload)
        let event = PacketParser.parse(data)

        guard case .telemetryResponse(let response) = event else {
            Issue.record("Expected telemetryResponse event, got \(event)")
            return
        }
        #expect(response.publicKeyPrefix == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        #expect(response.tag == Data([0x01, 0x02, 0x03, 0x04]))
        #expect(response.rawData == Data([0xCA, 0xFE, 0xBA, 0xBE]))
    }
}

// MARK: - Fuzz Testing

@Suite("Fuzz Testing")
struct FuzzTests {

    @Test("Parser never crashes on random data")
    func fuzzParser() {
        // Test with various random-like data sizes
        let sizes = [0, 1, 2, 5, 10, 50, 100, 200, 500, 1000]

        for size in sizes {
            // Generate deterministic "random" data for reproducibility
            var data = Data(count: size)
            for i in 0..<size {
                data[i] = UInt8((i * 31 + 17) % 256)
            }

            // Parser should never crash, always return a valid event
            let event = PacketParser.parse(data)

            // Should either successfully parse or return parseFailure
            switch event {
            case .parseFailure:
                // Expected for most random data
                break
            default:
                // Also acceptable if it happens to parse correctly
                break
            }
        }
    }

    @Test("Parser handles all possible first bytes")
    func fuzzFirstByte() {
        // Test every possible first byte value
        for firstByte: UInt8 in 0x00...0xFF {
            var data = Data([firstByte])
            // Add some payload
            data.append(Data(repeating: 0x00, count: 200))

            let event = PacketParser.parse(data)

            // Should never crash, always return valid event
            switch event {
            case .parseFailure:
                // Expected for unrecognized codes
                break
            default:
                // Valid parsing is fine too
                break
            }
        }
    }

    @Test("Parser handles data with only response code")
    func fuzzCodeOnly() {
        // Test each known response code with minimal/empty payload
        let knownCodes: [ResponseCode] = [
            .ok, .error, .selfInfo, .deviceInfo, .battery, .currentTime,
            .contactStart, .contact, .contactEnd, .messageSent, .ack,
            .loginSuccess, .loginFailed, .signStart
        ]

        for code in knownCodes {
            let data = Data([code.rawValue])
            let event = PacketParser.parse(data)

            // Should handle gracefully without crashing
            switch event {
            case .parseFailure:
                // Expected for most codes without payload
                break
            case .ok, .noMoreMessages, .messagesWaiting:
                // These can work without payload
                break
            default:
                break
            }
        }
    }

    @Test("Parser handles maximum size payloads")
    func fuzzLargePayload() {
        let largeSizes = [1024, 4096, 16384, 65536]

        for size in largeSizes {
            // Create a large payload with valid-looking structure
            var data = Data([ResponseCode.contact.rawValue])
            data.append(Data(repeating: 0x00, count: size))

            // Should handle without crashing
            _ = PacketParser.parse(data)
        }
    }
}

// MARK: - StatusResponse Offset Boundary Tests

@Suite("StatusResponse Offset Boundary Tests")
struct StatusResponseOffsetBoundaryTests {

    @Test("StatusResponse parses all 16 fields at correct offsets")
    func statusResponseOffsetBoundaries() {
        // Create a payload with known values at each field boundary
        var payload = Data(count: 58)
        var offset = 0

        // Field 1: pubkeyPrefix (6 bytes)
        let pubkeyPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        payload.replaceSubrange(offset..<offset+6, with: pubkeyPrefix); offset += 6

        // Field 2: battery (2 bytes LE) = 4200 (0x1068)
        payload[offset] = 0x68; payload[offset+1] = 0x10; offset += 2

        // Field 3: txQueueLength (2 bytes LE) = 5
        payload[offset] = 0x05; payload[offset+1] = 0x00; offset += 2

        // Field 4: noiseFloor (2 bytes LE signed) = -100
        let noiseFloor: Int16 = -100
        payload.replaceSubrange(offset..<offset+2, with: withUnsafeBytes(of: noiseFloor.littleEndian) { Data($0) }); offset += 2

        // Field 5: lastRSSI (2 bytes LE signed) = -75
        let lastRSSI: Int16 = -75
        payload.replaceSubrange(offset..<offset+2, with: withUnsafeBytes(of: lastRSSI.littleEndian) { Data($0) }); offset += 2

        // Field 6: packetsReceived (4 bytes LE) = 1000
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(1000).littleEndian) { Data($0) }); offset += 4

        // Field 7: packetsSent (4 bytes LE) = 500
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(500).littleEndian) { Data($0) }); offset += 4

        // Field 8: airtime (4 bytes LE) = 12345
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(12345).littleEndian) { Data($0) }); offset += 4

        // Field 9: uptime (4 bytes LE) = 86400
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(86400).littleEndian) { Data($0) }); offset += 4

        // Field 10: sentFlood (4 bytes LE) = 100
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(100).littleEndian) { Data($0) }); offset += 4

        // Field 11: sentDirect (4 bytes LE) = 400
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(400).littleEndian) { Data($0) }); offset += 4

        // Field 12: recvFlood (4 bytes LE) = 200
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(200).littleEndian) { Data($0) }); offset += 4

        // Field 13: recvDirect (4 bytes LE) = 800
        payload.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: UInt32(800).littleEndian) { Data($0) }); offset += 4

        // Field 14: fullEvents (2 bytes LE) = 10
        payload[offset] = 0x0A; payload[offset+1] = 0x00; offset += 2

        // Field 15: lastSNR (2 bytes LE signed, /4) = -8 (raw: -32)
        let lastSNR: Int16 = -32
        payload.replaceSubrange(offset..<offset+2, with: withUnsafeBytes(of: lastSNR.littleEndian) { Data($0) }); offset += 2

        // Field 16: directDups + floodDups (4 bytes) - leave as zero

        let packet = Data([ResponseCode.statusResponse.rawValue]) + payload
        let event = PacketParser.parse(packet)

        guard case .statusResponse(let status) = event else {
            Issue.record("Expected .statusResponse, got \(event)")
            return
        }

        #expect(status.publicKeyPrefix == pubkeyPrefix)
        #expect(status.battery == 4200)
        #expect(status.txQueueLength == 5)
        #expect(status.noiseFloor == -100)
        #expect(status.lastRSSI == -75)
        #expect(status.packetsReceived == 1000)
        #expect(status.packetsSent == 500)
        #expect(status.airtime == 12345)
        #expect(status.uptime == 86400)
        #expect(status.sentFlood == 100)
        #expect(status.sentDirect == 400)
        #expect(status.receivedFlood == 200)
        #expect(status.receivedDirect == 800)
        #expect(status.fullEvents == 10)
        #expect(status.lastSNR == -8.0) // -32 / 4
    }
}
