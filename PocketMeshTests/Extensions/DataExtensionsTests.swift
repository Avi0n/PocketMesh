import XCTest
@testable import PocketMeshKit

final class DataExtensionsTests: XCTestCase {

    // MARK: - hexString() Tests

    func testHexStringEmpty() {
        let data = Data()
        XCTAssertEqual(data.hexString(), "")
    }

    func testHexStringNoSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        XCTAssertEqual(data.hexString(), "AABBCCDD")
    }

    func testHexStringWithSpaceSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        XCTAssertEqual(data.hexString(separator: " "), "AA BB CC DD")
    }

    func testHexStringWithCustomSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC])
        XCTAssertEqual(data.hexString(separator: ":"), "AA:BB:CC")
    }

    func testHexStringSingleByte() {
        let data = Data([0x0F])
        XCTAssertEqual(data.hexString(), "0F")
    }

    func testHexStringLeadingZero() {
        let data = Data([0x00, 0x01, 0x02])
        XCTAssertEqual(data.hexString(), "000102")
    }

    // MARK: - init?(hexString:) Tests

    func testInitFromHexStringValid() {
        let data = Data(hexString: "AABBCCDD")
        XCTAssertEqual(data, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    func testInitFromHexStringWithSpaces() {
        let data = Data(hexString: "AA BB CC DD")
        XCTAssertEqual(data, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    func testInitFromHexStringLowercase() {
        let data = Data(hexString: "aabbccdd")
        XCTAssertEqual(data, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    func testInitFromHexStringMixedCase() {
        let data = Data(hexString: "AaBbCcDd")
        XCTAssertEqual(data, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    func testInitFromHexStringEmpty() {
        let data = Data(hexString: "")
        XCTAssertEqual(data, Data())
    }

    func testInitFromHexStringOddLength() {
        let data = Data(hexString: "ABC")
        XCTAssertNil(data)
    }

    func testInitFromHexStringWithNonHexCharacters() {
        // Should filter out non-hex characters
        let data = Data(hexString: "AA-BB-CC")
        XCTAssertEqual(data, Data([0xAA, 0xBB, 0xCC]))
    }

    // MARK: - Round-trip Tests

    func testRoundTrip() {
        let original = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let hexString = original.hexString()
        let restored = Data(hexString: hexString)
        XCTAssertEqual(restored, original)
    }

    func testRoundTripWithSpaces() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let hexString = original.hexString(separator: " ")
        let restored = Data(hexString: hexString)
        XCTAssertEqual(restored, original)
    }
}
