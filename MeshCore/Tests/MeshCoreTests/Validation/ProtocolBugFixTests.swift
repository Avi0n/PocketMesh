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
}
