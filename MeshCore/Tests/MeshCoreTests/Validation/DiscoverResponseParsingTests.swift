import XCTest
@testable import MeshCore

final class DiscoverResponseParsingTests: XCTestCase {

    func test_controlData_parsesDiscoverResponse() {
        // Control data format: [snr:1][rssi:1][pathLen:1][payloadType:1][payload...]
        // DISCOVER_RESP payload: [snr_in:1][tag:4][pubkey:8 or 32]
        var payload = Data()
        payload.append(0x28)  // SNR: 10.0 (40 / 4.0)
        payload.append(0xAB)  // RSSI: -85 (signed)
        payload.append(0x02)  // path length
        payload.append(0x95)  // payloadType: 0x90 | 0x05 (DISCOVER_RESP, nodeType=5)
        // DISCOVER_RESP inner payload
        payload.append(0x14)  // snr_in: 5.0 (20 / 4.0)
        payload.appendLittleEndian(UInt32(12345))  // tag
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])  // 8-byte prefix

        let event = Parsers.ControlData.parse(payload)

        guard case .discoverResponse(let response) = event else {
            XCTFail("Expected discoverResponse, got \(event)")
            return
        }

        XCTAssertEqual(response.nodeType, 5)
        XCTAssertEqual(response.snrIn, 5.0, accuracy: 0.001)
        XCTAssertEqual(response.snr, 10.0, accuracy: 0.001)
        XCTAssertEqual(response.rssi, -85)
        XCTAssertEqual(response.pathLength, 2)
        XCTAssertEqual(response.tag, Data([0x39, 0x30, 0x00, 0x00]))  // 12345 in LE
        XCTAssertEqual(response.publicKey.hexString, "1122334455667788")
    }

    func test_controlData_parsesFullPubkey() {
        var payload = Data()
        payload.append(0x28)  // SNR
        payload.append(0xAB)  // RSSI
        payload.append(0x01)  // path length
        payload.append(0x91)  // DISCOVER_RESP, nodeType=1
        payload.append(0x28)  // snr_in
        payload.appendLittleEndian(UInt32(999))  // tag
        payload.append(Data(repeating: 0xAA, count: 32))  // full 32-byte pubkey

        let event = Parsers.ControlData.parse(payload)

        guard case .discoverResponse(let response) = event else {
            XCTFail("Expected discoverResponse")
            return
        }

        XCTAssertEqual(response.publicKey.count, 32)
        XCTAssertEqual(response.publicKey, Data(repeating: 0xAA, count: 32))
    }

    func test_controlData_nonDiscoverReturnsRaw() {
        var payload = Data()
        payload.append(0x28)  // SNR
        payload.append(0xAB)  // RSSI
        payload.append(0x01)  // path length
        payload.append(0x80)  // payloadType: NODE_DISCOVER_REQ (not RESP)
        payload.append(contentsOf: [0x01, 0x02, 0x03])  // some payload

        let event = Parsers.ControlData.parse(payload)

        guard case .controlData(let info) = event else {
            XCTFail("Expected controlData, got \(event)")
            return
        }

        XCTAssertEqual(info.payloadType, 0x80)
        XCTAssertEqual(info.payload, Data([0x01, 0x02, 0x03]))
    }

    func test_controlData_discoverRespTooShortFallsBackToControlData() {
        // DISCOVER_RESP with insufficient payload (less than 5 bytes for inner payload)
        var payload = Data()
        payload.append(0x28)  // SNR
        payload.append(0xAB)  // RSSI
        payload.append(0x01)  // path length
        payload.append(0x91)  // DISCOVER_RESP
        payload.append(contentsOf: [0x01, 0x02, 0x03, 0x04])  // Only 4 bytes (need at least 5)

        let event = Parsers.ControlData.parse(payload)

        // Should fall back to controlData since inner payload is too short
        guard case .controlData(let info) = event else {
            XCTFail("Expected controlData for short DISCOVER_RESP payload, got \(event)")
            return
        }

        XCTAssertEqual(info.payloadType, 0x91)
    }
}
