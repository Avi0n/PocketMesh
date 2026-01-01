import XCTest
@testable import MeshCore

final class RawDataParsingTests: XCTestCase {

    func test_rawData_skipsReservedByte() {
        // Firmware format: [snr:1][rssi:1][reserved:1][payload...]
        var payload = Data()
        payload.append(0x28)  // SNR: 40/4 = 10.0
        payload.append(0xAB)  // RSSI: -85 (signed)
        payload.append(0xFF)  // Reserved byte (should be skipped)
        payload.append(contentsOf: [0x01, 0x02, 0x03, 0x04])  // Actual payload

        let event = Parsers.RawData.parse(payload)

        guard case .rawData(let info) = event else {
            XCTFail("Expected rawData, got \(event)")
            return
        }

        XCTAssertEqual(info.snr, 10.0, accuracy: 0.001)
        XCTAssertEqual(info.rssi, -85)
        XCTAssertEqual(info.payload, Data([0x01, 0x02, 0x03, 0x04]),
            "Payload should not include reserved byte 0xFF")
    }

    func test_rawData_rejectsShortPayload() {
        let shortPayload = Data([0x28, 0xAB])  // Only 2 bytes, need 3

        let event = Parsers.RawData.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }

    func test_rawData_handlesEmptyPayload() {
        // Minimum valid: snr + rssi + reserved = 3 bytes, no actual payload
        let payload = Data([0x28, 0xAB, 0xFF])

        let event = Parsers.RawData.parse(payload)

        guard case .rawData(let info) = event else {
            XCTFail("Expected rawData")
            return
        }

        XCTAssertEqual(info.payload.count, 0, "Should have empty payload")
    }
}
