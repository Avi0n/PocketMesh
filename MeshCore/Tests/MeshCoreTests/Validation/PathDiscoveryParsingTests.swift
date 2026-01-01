import XCTest
@testable import MeshCore

final class PathDiscoveryParsingTests: XCTestCase {

    func test_pathDiscoveryResponse_skipsReservedByte() {
        // Firmware format: [reserved:1][pubkey:6][out_len:1][out_path...][in_len:1][in_path...]
        var payload = Data()
        payload.append(0x00)  // Reserved byte (should be skipped)
        payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])  // Pubkey prefix
        payload.append(0x02)  // out_path_len = 2
        payload.append(contentsOf: [0x11, 0x22])  // out_path
        payload.append(0x03)  // in_path_len = 3
        payload.append(contentsOf: [0x33, 0x44, 0x55])  // in_path

        let event = Parsers.PathDiscoveryResponse.parse(payload)

        guard case .pathResponse(let pathInfo) = event else {
            XCTFail("Expected pathResponse, got \(event)")
            return
        }

        XCTAssertEqual(pathInfo.publicKeyPrefix.hexString, "aabbccddeeff",
            "Pubkey should start at byte 1")
        XCTAssertEqual(pathInfo.outPath, Data([0x11, 0x22]),
            "Out path should be [0x11, 0x22]")
        XCTAssertEqual(pathInfo.inPath, Data([0x33, 0x44, 0x55]),
            "In path should be [0x33, 0x44, 0x55]")
    }

    func test_pathDiscoveryResponse_handlesEmptyPaths() {
        var payload = Data()
        payload.append(0x00)  // Reserved
        payload.append(contentsOf: [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])  // Pubkey
        payload.append(0x00)  // out_path_len = 0
        payload.append(0x00)  // in_path_len = 0

        let event = Parsers.PathDiscoveryResponse.parse(payload)

        guard case .pathResponse(let pathInfo) = event else {
            XCTFail("Expected pathResponse")
            return
        }

        XCTAssertEqual(pathInfo.outPath.count, 0)
        XCTAssertEqual(pathInfo.inPath.count, 0)
    }

    func test_pathDiscoveryResponse_rejectsShortPayload() {
        let shortPayload = Data([0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE])  // Only 6 bytes

        let event = Parsers.PathDiscoveryResponse.parse(shortPayload)

        guard case .parseFailure = event else {
            XCTFail("Expected parseFailure for short payload")
            return
        }
    }
}
