import XCTest
@testable import MeshCore

/// Tests that verify protocol bugs stay fixed.
/// These tests encode the specific byte-level expectations from firmware/Python.
final class ProtocolBugFixTests: XCTestCase {

    // MARK: - Bug A: appStart Alignment

    func test_appStart_clientIdStartsAtByte8() {
        let packet = PacketBuilder.appStart(clientId: "Test")

        // Bytes 0-1: command + subtype
        XCTAssertEqual(packet[0], 0x01, "Byte 0 should be command code 0x01")
        XCTAssertEqual(packet[1], 0x03, "Byte 1 should be subtype 0x03")

        // Bytes 2-7: reserved (spaces = 0x20)
        XCTAssertEqual(packet[2], 0x20, "Byte 2 should be space (reserved)")
        XCTAssertEqual(packet[3], 0x20, "Byte 3 should be space (reserved)")
        XCTAssertEqual(packet[4], 0x20, "Byte 4 should be space (reserved)")
        XCTAssertEqual(packet[5], 0x20, "Byte 5 should be space (reserved)")
        XCTAssertEqual(packet[6], 0x20, "Byte 6 should be space (reserved)")
        XCTAssertEqual(packet[7], 0x20, "Byte 7 should be space (reserved)")

        // Bytes 8+: client ID
        let clientIdBytes = Data(packet[8...])
        let clientId = String(data: clientIdBytes, encoding: .utf8)
        XCTAssertEqual(clientId, "Test", "Client ID should start at byte 8")
    }

    func test_appStart_truncatesLongClientId() {
        // Client IDs longer than 5 chars should be truncated
        let packet = PacketBuilder.appStart(clientId: "LongClientName")

        // Should only have first 5 characters
        let clientIdBytes = Data(packet[8...])
        let clientId = String(data: clientIdBytes, encoding: .utf8)
        XCTAssertEqual(clientId, "LongC", "Client ID should be truncated to 5 chars")
        XCTAssertEqual(packet.count, 13, "Packet should be 2 + 6 + 5 = 13 bytes")
    }

    func test_appStart_defaultClientId() {
        // Default should be "MCore"
        let packet = PacketBuilder.appStart()

        let clientIdBytes = Data(packet[8...])
        let clientId = String(data: clientIdBytes, encoding: .utf8)
        XCTAssertEqual(clientId, "MCore", "Default client ID should be 'MCore'")
    }

    // MARK: - Bug C: StatusResponse Offset

    func test_statusResponse_skipsReservedByte() {
        // Build a StatusResponse payload as firmware would send it (after response code stripped)
        // Format: reserved(1) + pubkey(6) + fields(52) = 59 bytes total
        var payload = Data()
        payload.append(0x00)  // Reserved byte
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])  // Pubkey prefix (6)
        payload.append(contentsOf: [0xE8, 0x03])  // Battery: 1000mV (little-endian)
        payload.append(contentsOf: [0x05, 0x00])  // txQueue: 5
        payload.append(contentsOf: [0x92, 0xFF])  // noiseFloor: -110 (signed)
        payload.append(contentsOf: [0xAB, 0xFF])  // lastRSSI: -85 (signed)
        // Add remaining fields: recv(4)+sent(4)+airtime(4)+uptime(4)+flood_tx(4)+direct_tx(4)+
        // flood_rx(4)+direct_rx(4)+full_evts(2)+snr(2)+direct_dups(2)+flood_dups(2)+rx_air(4) = 44 bytes
        payload.append(Data(repeating: 0, count: 44))

        XCTAssertEqual(payload.count, 59, "Payload should be 59 bytes total")

        let event = Parsers.StatusResponse.parse(payload)

        guard case .statusResponse(let status) = event else {
            XCTFail("Expected statusResponse event, got \(event)")
            return
        }

        // Verify pubkey starts at byte 1, not byte 0
        XCTAssertEqual(status.publicKeyPrefix.hexString, "aabbccddeeff",
            "Pubkey should be read from bytes 1-6, not 0-5")

        // Verify battery is read from correct offset
        XCTAssertEqual(status.battery, 1000,
            "Battery should be 1000mV, not corrupted by offset error")

        // Verify other fields
        XCTAssertEqual(status.txQueueLength, 5, "txQueue should be 5")
        XCTAssertEqual(status.noiseFloor, -110, "noiseFloor should be -110")
        XCTAssertEqual(status.lastRSSI, -85, "lastRSSI should be -85")
    }

    func test_statusResponse_rejectsShortPayload() {
        // Payload too short should return parseFailure
        let shortPayload = Data(repeating: 0, count: 50)

        let event = Parsers.StatusResponse.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload, got \(event)")
            return
        }
    }

    func test_statusResponse_handlesMaxValues() {
        // Test with maximum realistic values (59 bytes total)
        var payload = Data()
        payload.append(0x00)  // Reserved byte
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])  // Pubkey prefix (6)
        payload.append(contentsOf: [0xDC, 0x05])  // Battery: 1500mV
        payload.append(contentsOf: [0x00, 0x00])  // txQueue: 0
        payload.append(contentsOf: [0x88, 0xFF])  // noiseFloor: -120
        payload.append(contentsOf: [0xD6, 0xFF])  // lastRSSI: -42
        payload.append(Data(repeating: 0, count: 44))  // Remaining 44 bytes

        let event = Parsers.StatusResponse.parse(payload)

        guard case .statusResponse(let status) = event else {
            XCTFail("Expected statusResponse event")
            return
        }

        XCTAssertEqual(status.battery, 1500)
        XCTAssertEqual(status.noiseFloor, -120)
        XCTAssertEqual(status.lastRSSI, -42)
    }

    // MARK: - Binary Response Status Parsing (Format 2)

    func test_statusResponse_parseFromBinaryResponse_validPayload() {
        // Binary response format: fields start at offset 0 (no reserved byte, no pubkey)
        // Total: 52 bytes minimum
        var payload = Data()
        payload.append(contentsOf: [0xE8, 0x03])  // Battery: 1000mV (little-endian)
        payload.append(contentsOf: [0x05, 0x00])  // txQueue: 5
        payload.append(contentsOf: [0x92, 0xFF])  // noiseFloor: -110 (signed)
        payload.append(contentsOf: [0xAB, 0xFF])  // lastRSSI: -85 (signed)
        payload.append(contentsOf: [0x64, 0x00, 0x00, 0x00])  // packetsRecv: 100
        payload.append(contentsOf: [0xC8, 0x00, 0x00, 0x00])  // packetsSent: 200
        payload.append(contentsOf: [0x10, 0x27, 0x00, 0x00])  // airtime: 10000
        payload.append(contentsOf: [0x58, 0x02, 0x00, 0x00])  // uptime: 600
        payload.append(contentsOf: [0x0A, 0x00, 0x00, 0x00])  // sentFlood: 10
        payload.append(contentsOf: [0x14, 0x00, 0x00, 0x00])  // sentDirect: 20
        payload.append(contentsOf: [0x1E, 0x00, 0x00, 0x00])  // recvFlood: 30
        payload.append(contentsOf: [0x28, 0x00, 0x00, 0x00])  // recvDirect: 40
        payload.append(contentsOf: [0x03, 0x00])  // fullEvents: 3
        payload.append(contentsOf: [0x28, 0x00])  // lastSNR: 40/4 = 10.0
        payload.append(contentsOf: [0x02, 0x00])  // directDups: 2
        payload.append(contentsOf: [0x01, 0x00])  // floodDups: 1
        payload.append(contentsOf: [0x20, 0x4E, 0x00, 0x00])  // rxAirtime: 20000

        let pubkeyPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])

        let status = Parsers.StatusResponse.parseFromBinaryResponse(payload, publicKeyPrefix: pubkeyPrefix)

        guard let status = status else {
            XCTFail("Should successfully parse valid binary response")
            return
        }

        XCTAssertEqual(status.publicKeyPrefix.hexString, "aabbccddeeff")
        XCTAssertEqual(status.battery, 1000)
        XCTAssertEqual(status.txQueueLength, 5)
        XCTAssertEqual(status.noiseFloor, -110)
        XCTAssertEqual(status.lastRSSI, -85)
        XCTAssertEqual(status.packetsReceived, 100)
        XCTAssertEqual(status.packetsSent, 200)
        XCTAssertEqual(status.airtime, 10000)
        XCTAssertEqual(status.uptime, 600)
        XCTAssertEqual(status.sentFlood, 10)
        XCTAssertEqual(status.sentDirect, 20)
        XCTAssertEqual(status.receivedFlood, 30)
        XCTAssertEqual(status.receivedDirect, 40)
        XCTAssertEqual(status.fullEvents, 3)
        XCTAssertEqual(status.lastSNR, 10.0, accuracy: 0.001)
        XCTAssertEqual(status.directDuplicates, 2)
        XCTAssertEqual(status.floodDuplicates, 1)
        XCTAssertEqual(status.rxAirtime, 20000)
    }

    func test_statusResponse_parseFromBinaryResponse_rejectsShortPayload() {
        let shortPayload = Data(repeating: 0, count: 47)  // Less than 48 bytes
        let pubkeyPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])

        let status = Parsers.StatusResponse.parseFromBinaryResponse(shortPayload, publicKeyPrefix: pubkeyPrefix)

        XCTAssertNil(status, "Should return nil for payload shorter than 48 bytes")
    }

    func test_statusResponse_parseFromBinaryResponse_handlesMinimalPayload() {
        // Exactly 48 bytes (no rxAirtime field)
        var payload = Data(repeating: 0, count: 48)
        // Set battery to non-zero so we can verify parsing
        payload[0] = 0xE8
        payload[1] = 0x03  // Battery: 1000mV

        let pubkeyPrefix = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])

        let status = Parsers.StatusResponse.parseFromBinaryResponse(payload, publicKeyPrefix: pubkeyPrefix)

        guard let status = status else {
            XCTFail("Should parse minimal payload")
            return
        }

        XCTAssertEqual(status.battery, 1000)
        XCTAssertEqual(status.rxAirtime, 0, "rxAirtime should default to 0 when not present")
    }

    func test_statusResponse_parseFromBinaryResponse_rejectsIncompletePayload() {
        for size in [49, 50, 51] {
            let payload = Data(repeating: 0, count: size)
            let pubkeyPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
            let status = Parsers.StatusResponse.parseFromBinaryResponse(payload, publicKeyPrefix: pubkeyPrefix)
            XCTAssertNil(status, "Should reject \(size)-byte payload")
        }
    }

    func test_statusResponse_parseFromBinaryResponse_handlesExtraData() {
        var payload = Data(repeating: 0, count: 56)  // 52 + 4 extra bytes
        payload[0] = 0xE8
        payload[1] = 0x03  // Battery: 1000mV
        let pubkeyPrefix = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
        let status = Parsers.StatusResponse.parseFromBinaryResponse(payload, publicKeyPrefix: pubkeyPrefix)
        XCTAssertNotNil(status, "Should parse payload with extra data")
        XCTAssertEqual(status?.battery, 1000)
    }

    // MARK: - Bug B & D: Binary Response Routing & Neighbours Parser

    func test_neighboursParser_parsesValidResponse() {
        // Build a neighbours response as firmware would send it
        // Format: total_count(2) + results_count(2) + entries(N * (prefix + secs_ago + snr))
        var payload = Data()
        payload.append(contentsOf: [0x03, 0x00])  // total_count: 3 (little-endian)
        payload.append(contentsOf: [0x02, 0x00])  // results_count: 2

        // Entry 1: pubkey_prefix(4) + secs_ago(4) + snr(1)
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44])  // pubkey prefix
        payload.append(contentsOf: [0x3C, 0x00, 0x00, 0x00])  // secs_ago: 60
        payload.append(0x28)  // snr: 40/4 = 10.0

        // Entry 2
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])  // pubkey prefix
        payload.append(contentsOf: [0x78, 0x00, 0x00, 0x00])  // secs_ago: 120
        payload.append(0xF0)  // snr: -16/4 = -4.0 (signed)

        let response = NeighboursParser.parse(
            payload,
            publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
            tag: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            prefixLength: 4
        )

        XCTAssertEqual(response.totalCount, 3, "Total count should be 3")
        XCTAssertEqual(response.neighbours.count, 2, "Should have 2 neighbour entries")

        // Verify first neighbour
        XCTAssertEqual(response.neighbours[0].publicKeyPrefix.hexString, "11223344")
        XCTAssertEqual(response.neighbours[0].secondsAgo, 60)
        XCTAssertEqual(response.neighbours[0].snr, 10.0, accuracy: 0.001)

        // Verify second neighbour
        XCTAssertEqual(response.neighbours[1].publicKeyPrefix.hexString, "aabbccdd")
        XCTAssertEqual(response.neighbours[1].secondsAgo, 120)
        XCTAssertEqual(response.neighbours[1].snr, -4.0, accuracy: 0.001)
    }

    func test_neighboursParser_handlesEmptyResponse() {
        // Empty response with 0 results
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00])  // total_count: 0
        payload.append(contentsOf: [0x00, 0x00])  // results_count: 0

        let response = NeighboursParser.parse(
            payload,
            publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
            tag: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            prefixLength: 4
        )

        XCTAssertEqual(response.totalCount, 0)
        XCTAssertEqual(response.neighbours.count, 0)
    }

    func test_neighboursParser_handlesShortPayload() {
        // Payload too short should return empty response
        let shortPayload = Data([0x01, 0x00])  // Only 2 bytes

        let response = NeighboursParser.parse(
            shortPayload,
            publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
            tag: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            prefixLength: 4
        )

        XCTAssertEqual(response.totalCount, 0)
        XCTAssertEqual(response.neighbours.count, 0)
    }

    func test_neighboursParser_handles6BytePrefixLength() {
        // Test with longer prefix length (6 bytes)
        var payload = Data()
        payload.append(contentsOf: [0x01, 0x00])  // total_count: 1
        payload.append(contentsOf: [0x01, 0x00])  // results_count: 1

        // Entry with 6-byte prefix
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])  // pubkey prefix (6)
        payload.append(contentsOf: [0x1E, 0x00, 0x00, 0x00])  // secs_ago: 30
        payload.append(0x14)  // snr: 20/4 = 5.0

        let response = NeighboursParser.parse(
            payload,
            publicKeyPrefix: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
            tag: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            prefixLength: 6
        )

        XCTAssertEqual(response.neighbours.count, 1)
        XCTAssertEqual(response.neighbours[0].publicKeyPrefix.hexString, "112233445566")
        XCTAssertEqual(response.neighbours[0].secondsAgo, 30)
        XCTAssertEqual(response.neighbours[0].snr, 5.0, accuracy: 0.001)
    }

    func test_aclParser_parsesValidResponse() {
        // Build an ACL response: [pubkey_prefix:6][permissions:1] per entry
        var payload = Data()

        // Entry 1
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])  // pubkey prefix (6)
        payload.append(0x01)  // permissions

        // Entry 2
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])  // pubkey prefix (6)
        payload.append(0x03)  // permissions

        let entries = ACLParser.parse(payload)

        XCTAssertEqual(entries.count, 2, "Should have 2 ACL entries")
        XCTAssertEqual(entries[0].keyPrefix.hexString, "112233445566")
        XCTAssertEqual(entries[0].permissions, 0x01)
        XCTAssertEqual(entries[1].keyPrefix.hexString, "aabbccddeeff")
        XCTAssertEqual(entries[1].permissions, 0x03)
    }

    func test_aclParser_skipsNullEntries() {
        // ACL parser should skip entries with all-zero key prefix
        var payload = Data()

        // Entry 1 (valid)
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
        payload.append(0x01)

        // Entry 2 (null - should be skipped)
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        payload.append(0x00)

        // Entry 3 (valid)
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        payload.append(0x02)

        let entries = ACLParser.parse(payload)

        XCTAssertEqual(entries.count, 2, "Should have 2 entries (null entry skipped)")
        XCTAssertEqual(entries[0].keyPrefix.hexString, "112233445566")
        XCTAssertEqual(entries[1].keyPrefix.hexString, "aabbccddeeff")
    }

    func test_mmaParser_parsesTemperatureEntry() {
        // Build an MMA response with temperature entries (type 0x67)
        // Format: [channel:1][type:1][min:2][max:2][avg:2]
        var payload = Data()

        // Temperature entry: channel 1, type 0x67
        payload.append(0x01)  // channel
        payload.append(0x67)  // type: temperature
        // Values are big-endian, scaled by 10
        payload.append(contentsOf: [0x00, 0xC8])  // min: 200 = 20.0°C
        payload.append(contentsOf: [0x01, 0x2C])  // max: 300 = 30.0°C
        payload.append(contentsOf: [0x00, 0xFA])  // avg: 250 = 25.0°C

        let entries = MMAParser.parse(payload)

        XCTAssertEqual(entries.count, 1, "Should have 1 MMA entry")
        XCTAssertEqual(entries[0].channel, 1)
        XCTAssertEqual(entries[0].type, "Temperature")
        XCTAssertEqual(entries[0].min, 20.0, accuracy: 0.001)
        XCTAssertEqual(entries[0].max, 30.0, accuracy: 0.001)
        XCTAssertEqual(entries[0].avg, 25.0, accuracy: 0.001)
    }

    func test_mmaParser_parsesHumidityEntry() {
        // Humidity entry: type 0x68, values scaled by 0.5
        var payload = Data()

        payload.append(0x02)  // channel
        payload.append(0x68)  // type: humidity
        // Values are 1 byte each, scaled by 0.5
        payload.append(0x64)  // min: 100 * 0.5 = 50%
        payload.append(0x96)  // max: 150 * 0.5 = 75%
        payload.append(0x82)  // avg: 130 * 0.5 = 65%

        let entries = MMAParser.parse(payload)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].type, "Humidity")
        XCTAssertEqual(entries[0].min, 50.0, accuracy: 0.001)
        XCTAssertEqual(entries[0].max, 75.0, accuracy: 0.001)
        XCTAssertEqual(entries[0].avg, 65.0, accuracy: 0.001)
    }

    // MARK: - Binary Response Telemetry Parsing (Format 2)

    func test_telemetryResponse_parseFromBinaryResponse_validPayload() {
        // Binary response format: raw LPP data starts at offset 0
        // LPP format: [channel:1][type:1][value:N]
        var payload = Data()
        // Temperature reading: channel 1, type 0x67
        payload.append(0x01)  // channel
        payload.append(0x67)  // type: temperature
        payload.append(contentsOf: [0x00, 0xFA])  // 250 = 25.0°C (big-endian, /10)

        let pubkeyPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])

        let response = Parsers.TelemetryResponse.parseFromBinaryResponse(payload, publicKeyPrefix: pubkeyPrefix)

        XCTAssertEqual(response.publicKeyPrefix.hexString, "aabbccddeeff")
        XCTAssertEqual(response.rawData, payload)
        XCTAssertEqual(response.dataPoints.count, 1)
        XCTAssertEqual(response.dataPoints.first?.channel, 1)
    }

    func test_telemetryResponse_parseFromBinaryResponse_emptyPayload() {
        let emptyPayload = Data()
        let pubkeyPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])

        let response = Parsers.TelemetryResponse.parseFromBinaryResponse(emptyPayload, publicKeyPrefix: pubkeyPrefix)

        // Empty payload is valid (just no data points)
        XCTAssertEqual(response.dataPoints.count, 0)
    }

    func test_requestStatus_throwsDeviceErrorWhenErrorResponseReceived() async throws {
        let transport = MockTransport()
        let session = MeshCoreSession(
            transport: transport,
            configuration: SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "Test")
        )

        let startTask = Task {
            try await session.start()
        }

        for _ in 0..<50 {
            if (await transport.sentData).count >= 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        var selfInfoPayload = Data()
        selfInfoPayload.append(0)
        selfInfoPayload.append(0)
        selfInfoPayload.append(0)
        selfInfoPayload.append(Data(repeating: 0x01, count: 32))
        selfInfoPayload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
        selfInfoPayload.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian) { Array($0) })
        selfInfoPayload.append(0)
        selfInfoPayload.append(0)
        selfInfoPayload.append(0)
        selfInfoPayload.append(0)
        selfInfoPayload.append(contentsOf: withUnsafeBytes(of: UInt32(915_000).littleEndian) { Array($0) })
        selfInfoPayload.append(contentsOf: withUnsafeBytes(of: UInt32(125_000).littleEndian) { Array($0) })
        selfInfoPayload.append(7)
        selfInfoPayload.append(5)
        selfInfoPayload.append(contentsOf: "Test".utf8)

        var selfInfoPacket = Data([ResponseCode.selfInfo.rawValue])
        selfInfoPacket.append(selfInfoPayload)
        await transport.simulateReceive(selfInfoPacket)

        try await startTask.value

        let publicKey = Data(repeating: 0x31, count: 32)
        let statusTask = Task {
            try await session.requestStatus(from: publicKey)
        }

        for _ in 0..<50 {
            if (await transport.sentData).count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await transport.simulateError(code: 10)

        do {
            _ = try await statusTask.value
            XCTFail("Expected requestStatus(from:) to throw")
        } catch let error as MeshCoreError {
            guard case .deviceError(let code) = error else {
                XCTFail("Expected MeshCoreError.deviceError, got \(error)")
                return
            }
            XCTAssertEqual(code, 10)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await session.stop()
    }
}
