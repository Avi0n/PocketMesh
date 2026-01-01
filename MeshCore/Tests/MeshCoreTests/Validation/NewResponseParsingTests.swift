import XCTest
@testable import MeshCore

final class NewResponseParsingTests: XCTestCase {

    func test_advertPathResponse_parse() {
        var payload = Data()
        payload.appendLittleEndian(UInt32(1704067200))  // timestamp
        payload.append(0x03)  // path length
        payload.append(contentsOf: [0x11, 0x22, 0x33])  // path

        let event = Parsers.AdvertPathResponse.parse(payload)

        guard case .advertPathResponse(let response) = event else {
            XCTFail("Expected advertPathResponse, got \(event)")
            return
        }

        XCTAssertEqual(response.recvTimestamp, 1704067200)
        XCTAssertEqual(response.pathLength, 3)
        XCTAssertEqual(response.path, Data([0x11, 0x22, 0x33]))
    }

    func test_advertPathResponse_emptyPath() {
        var payload = Data()
        payload.appendLittleEndian(UInt32(1000))
        payload.append(0x00)  // path length = 0

        let event = Parsers.AdvertPathResponse.parse(payload)

        guard case .advertPathResponse(let response) = event else {
            XCTFail("Expected advertPathResponse")
            return
        }

        XCTAssertEqual(response.pathLength, 0)
        XCTAssertEqual(response.path.count, 0)
    }

    func test_advertPathResponse_tooShort() {
        // Less than 5 bytes should fail
        let shortPayload = Data([0x01, 0x02, 0x03, 0x04])

        let event = Parsers.AdvertPathResponse.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }

    func test_tuningParamsResponse_parse() {
        var payload = Data()
        // rx_delay_base * 1000 = 1500 (1.5ms)
        payload.appendLittleEndian(UInt32(1500))
        // airtime_factor * 1000 = 2500 (2.5)
        payload.appendLittleEndian(UInt32(2500))

        let event = Parsers.TuningParamsResponse.parse(payload)

        guard case .tuningParamsResponse(let response) = event else {
            XCTFail("Expected tuningParamsResponse, got \(event)")
            return
        }

        XCTAssertEqual(response.rxDelayBase, 1.5, accuracy: 0.001)
        XCTAssertEqual(response.airtimeFactor, 2.5, accuracy: 0.001)
    }

    func test_tuningParamsResponse_tooShort() {
        // Less than 8 bytes should fail
        let shortPayload = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])

        let event = Parsers.TuningParamsResponse.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }

    func test_tuningParamsResponse_zeroValues() {
        var payload = Data()
        payload.appendLittleEndian(UInt32(0))
        payload.appendLittleEndian(UInt32(0))

        let event = Parsers.TuningParamsResponse.parse(payload)

        guard case .tuningParamsResponse(let response) = event else {
            XCTFail("Expected tuningParamsResponse")
            return
        }

        XCTAssertEqual(response.rxDelayBase, 0.0, accuracy: 0.001)
        XCTAssertEqual(response.airtimeFactor, 0.0, accuracy: 0.001)
    }
}
