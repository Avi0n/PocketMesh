import Foundation
import Testing
@testable import PocketMeshServices

@Suite("Data Extensions Tests")
struct DataExtensionsTests {

    // MARK: - hexString() Tests

    @Test("Empty data returns empty string")
    func hexStringEmpty() {
        let data = Data()
        #expect(data.hexString() == "")
    }

    @Test("Hex string with no separator")
    func hexStringNoSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        #expect(data.hexString() == "AABBCCDD")
    }

    @Test("Hex string with space separator")
    func hexStringWithSpaceSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        #expect(data.hexString(separator: " ") == "AA BB CC DD")
    }

    @Test("Hex string with custom separator")
    func hexStringWithCustomSeparator() {
        let data = Data([0xAA, 0xBB, 0xCC])
        #expect(data.hexString(separator: ":") == "AA:BB:CC")
    }

    @Test("Hex string for single byte")
    func hexStringSingleByte() {
        let data = Data([0x0F])
        #expect(data.hexString() == "0F")
    }

    @Test("Hex string preserves leading zeros")
    func hexStringLeadingZero() {
        let data = Data([0x00, 0x01, 0x02])
        #expect(data.hexString() == "000102")
    }

    // MARK: - init?(hexString:) Tests

    @Test("Init from valid hex string")
    func initFromHexStringValid() {
        let data = Data(hexString: "AABBCCDD")
        #expect(data == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    @Test("Init from hex string with spaces")
    func initFromHexStringWithSpaces() {
        let data = Data(hexString: "AA BB CC DD")
        #expect(data == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    @Test("Init from lowercase hex string")
    func initFromHexStringLowercase() {
        let data = Data(hexString: "aabbccdd")
        #expect(data == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    @Test("Init from mixed case hex string")
    func initFromHexStringMixedCase() {
        let data = Data(hexString: "AaBbCcDd")
        #expect(data == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    @Test("Init from empty hex string")
    func initFromHexStringEmpty() {
        let data = Data(hexString: "")
        #expect(data == Data())
    }

    @Test("Init from odd-length hex string returns nil")
    func initFromHexStringOddLength() {
        let data = Data(hexString: "ABC")
        #expect(data == nil)
    }

    @Test("Init filters out non-hex characters")
    func initFromHexStringWithNonHexCharacters() {
        let data = Data(hexString: "AA-BB-CC")
        #expect(data == Data([0xAA, 0xBB, 0xCC]))
    }

    // MARK: - Round-trip Tests

    @Test("Round-trip preserves data")
    func roundTrip() {
        let original = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let hexString = original.hexString()
        let restored = Data(hexString: hexString)
        #expect(restored == original)
    }

    @Test("Round-trip with spaces preserves data")
    func roundTripWithSpaces() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let hexString = original.hexString(separator: " ")
        let restored = Data(hexString: hexString)
        #expect(restored == original)
    }
}
