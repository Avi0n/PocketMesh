import XCTest
@testable import MeshCore

final class TelemetryParsingTests: XCTestCase {

    func test_telemetryResponse_skipsReservedByte() {
        // Firmware format: [reserved:1][pubkey_prefix:6][lpp_data...]
        var payload = Data()
        payload.append(0x00)  // Reserved byte (should be skipped)
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])  // Pubkey prefix
        payload.append(contentsOf: [0x01, 0x67, 0x00, 0xFA])  // LPP: channel 1, temp, 25.0C

        let event = Parsers.TelemetryResponse.parse(payload)

        guard case .telemetryResponse(let response) = event else {
            XCTFail("Expected telemetryResponse, got \(event)")
            return
        }

        XCTAssertEqual(response.publicKeyPrefix.hexString, "aabbccddeeff",
            "Pubkey should start at byte 1, not byte 0")
        XCTAssertNil(response.tag, "Push telemetry should have no tag")
        XCTAssertEqual(response.rawData, Data([0x01, 0x67, 0x00, 0xFA]),
            "LPP data should start at byte 7")
    }

    func test_telemetryResponse_rejectsShortPayload() {
        let shortPayload = Data([0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE])  // Only 6 bytes

        let event = Parsers.TelemetryResponse.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }

    func test_telemetryResponse_handlesEmptyLPPData() {
        // Minimum valid: reserved + pubkey = 7 bytes, no LPP data
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])  // Pubkey

        let event = Parsers.TelemetryResponse.parse(payload)

        guard case .telemetryResponse(let response) = event else {
            XCTFail("Expected telemetryResponse")
            return
        }

        XCTAssertEqual(response.rawData.count, 0, "Should have empty LPP data")
    }
}
