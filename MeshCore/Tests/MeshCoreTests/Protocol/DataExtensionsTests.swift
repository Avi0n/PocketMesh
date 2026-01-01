import XCTest
@testable import MeshCore

final class DataExtensionsTests: XCTestCase {

    func test_paddedOrTruncated_padsShortData() {
        let data = Data([0x01, 0x02, 0x03])
        let result = data.paddedOrTruncated(to: 6)
        XCTAssertEqual(result, Data([0x01, 0x02, 0x03, 0x00, 0x00, 0x00]))
    }

    func test_paddedOrTruncated_truncatesLongData() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let result = data.paddedOrTruncated(to: 3)
        XCTAssertEqual(result, Data([0x01, 0x02, 0x03]))
    }

    func test_paddedOrTruncated_returnsExactSizeUnchanged() {
        let data = Data([0x01, 0x02, 0x03])
        let result = data.paddedOrTruncated(to: 3)
        XCTAssertEqual(result, data)
    }

    func test_paddedOrTruncated_returnsEmptyForNegativeLength() {
        let data = Data([0x01, 0x02, 0x03])
        let result = data.paddedOrTruncated(to: -1)
        XCTAssertEqual(result, Data())
    }

    func test_utf8PaddedOrTruncated_padsShortString() {
        let result = "Hi".utf8PaddedOrTruncated(to: 6)
        XCTAssertEqual(result, Data([0x48, 0x69, 0x00, 0x00, 0x00, 0x00]))
    }

    func test_utf8PaddedOrTruncated_truncatesLongString() {
        let result = "Hello World".utf8PaddedOrTruncated(to: 5)
        XCTAssertEqual(result, Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])) // "Hello"
    }

    func test_appendLittleEndianUInt32() {
        var data = Data()
        data.appendLittleEndian(UInt32(0x12345678))
        XCTAssertEqual(data, Data([0x78, 0x56, 0x34, 0x12]))
    }

    func test_appendLittleEndianInt32() {
        var data = Data()
        data.appendLittleEndian(Int32(-1))
        XCTAssertEqual(data, Data([0xFF, 0xFF, 0xFF, 0xFF]))
    }
}
