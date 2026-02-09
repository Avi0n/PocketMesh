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

    // MARK: - utf8Prefix(maxBytes:)

    func test_utf8Prefix_asciiUnchangedWhenUnderLimit() {
        let result = "Hello".utf8Prefix(maxBytes: 10)
        XCTAssertEqual(result, "Hello")
    }

    func test_utf8Prefix_asciiTruncatedAtExactLimit() {
        let result = "Hello".utf8Prefix(maxBytes: 3)
        XCTAssertEqual(result, "Hel")
    }

    func test_utf8Prefix_cjkNeverSplitsThreeByteCharacters() {
        // Each CJK character is 3 UTF-8 bytes
        let cjk = "你好世界" // 12 bytes total
        let result = cjk.utf8Prefix(maxBytes: 7) // room for 2 chars (6 bytes), not 3 (9 bytes)
        XCTAssertEqual(result, "你好")
        XCTAssertEqual(result.utf8.count, 6)
    }

    func test_utf8Prefix_emojiNeverSplitsFourByteCharacters() {
        // Each emoji is 4 UTF-8 bytes
        let emoji = "😀🎉🔥"
        let result = emoji.utf8Prefix(maxBytes: 5) // room for 1 emoji (4 bytes), not 2 (8 bytes)
        XCTAssertEqual(result, "😀")
        XCTAssertEqual(result.utf8.count, 4)
    }

    func test_utf8Prefix_exactBoundaryIncludesCharacter() {
        let cjk = "你好" // 6 bytes total
        let result = cjk.utf8Prefix(maxBytes: 6)
        XCTAssertEqual(result, "你好")
    }

    func test_utf8Prefix_emptyStringReturnsEmpty() {
        let result = "".utf8Prefix(maxBytes: 10)
        XCTAssertEqual(result, "")
    }

    func test_utf8Prefix_zeroBytesReturnsEmpty() {
        let result = "Hello".utf8Prefix(maxBytes: 0)
        XCTAssertEqual(result, "")
    }

    func test_utf8Prefix_negativeBytesReturnsEmpty() {
        let result = "Hello".utf8Prefix(maxBytes: -1)
        XCTAssertEqual(result, "")
    }

    func test_utf8Prefix_mixedAsciiAndMultibyte() {
        let mixed = "Hi你" // 2 + 3 = 5 bytes
        let result = mixed.utf8Prefix(maxBytes: 4) // room for "Hi" (2) but not "Hi你" (5)
        XCTAssertEqual(result, "Hi")
    }

    // MARK: - utf8PaddedOrTruncated with multi-byte characters

    func test_utf8PaddedOrTruncated_doesNotSplitCJKCharacters() {
        let cjk = "你好世界" // 12 bytes
        let result = cjk.utf8PaddedOrTruncated(to: 8)
        // Should include "你好" (6 bytes) + 2 zero-padding bytes
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(result[6], 0x00)
        XCTAssertEqual(result[7], 0x00)
        // Verify the text portion decodes correctly
        let textPortion = String(decoding: result.prefix(6), as: UTF8.self)
        XCTAssertEqual(textPortion, "你好")
    }

    func test_utf8PaddedOrTruncated_doesNotSplitEmoji() {
        let emoji = "😀🎉" // 8 bytes
        let result = emoji.utf8PaddedOrTruncated(to: 6)
        // Should include "😀" (4 bytes) + 2 zero-padding bytes
        XCTAssertEqual(result.count, 6)
        let textPortion = String(decoding: result.prefix(4), as: UTF8.self)
        XCTAssertEqual(textPortion, "😀")
    }
}
