import XCTest
@testable import PocketMeshKit

final class ProtocolTests: XCTestCase {

    func testFrameEncoding() {
        let frame = ProtocolFrame(code: 1, payload: Data([0x01, 0x02, 0x03]))
        let encoded = frame.encode()

        XCTAssertEqual(encoded.count, 4)
        XCTAssertEqual(encoded[0], 1)
        XCTAssertEqual(encoded[1], 0x01)
    }

    func testFrameDecoding() throws {
        let data = Data([0x05, 0xAA, 0xBB, 0xCC])
        let frame = try ProtocolFrame.decode(data)

        XCTAssertEqual(frame.code, 0x05)
        XCTAssertEqual(frame.payload, Data([0xAA, 0xBB, 0xCC]))
    }

    func testDeviceInfoDecoding() throws {
        var data = Data()
        data.append(contentsOf: [1, 0, 0, 0]) // Firmware version (4 bytes)
        data.append(contentsOf: [0xFF, 0x00]) // Max contacts (2 bytes) = 255
        data.append(8) // Max channels (1 byte)
        data.append(contentsOf: [0x40, 0xE2, 0x01, 0x00]) // BLE PIN (4 bytes) = 123456
        // Total so far: 11 bytes, need at least 20, pad with zeros
        data.append(contentsOf: Data(repeating: 0, count: 9))

        let deviceInfo = try DeviceInfo.decode(from: data)

        XCTAssertEqual(deviceInfo.firmwareVersion, "1.0.0.0")
        XCTAssertEqual(deviceInfo.maxContacts, 255)
        XCTAssertEqual(deviceInfo.maxChannels, 8)
        XCTAssertEqual(deviceInfo.blePin, 123456)
    }

    func testCoordinateEncoding() {
        let lat = 37.7749
        let lon = -122.4194

        let latInt = Int32(lat * 1_000_000)
        let lonInt = Int32(lon * 1_000_000)

        XCTAssertEqual(latInt, 37_774_900)
        XCTAssertEqual(lonInt, -122_419_400)

        // Decode back
        let decodedLat = Double(latInt) / 1_000_000
        let decodedLon = Double(lonInt) / 1_000_000

        XCTAssertEqual(decodedLat, lat, accuracy: 0.000001)
        XCTAssertEqual(decodedLon, lon, accuracy: 0.000001)
    }

    func testEmptyPayloadFrame() throws {
        let frame = ProtocolFrame(code: 0x05)
        let encoded = frame.encode()

        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0], 0x05)

        let decoded = try ProtocolFrame.decode(encoded)
        XCTAssertEqual(decoded.code, 0x05)
        XCTAssertTrue(decoded.payload.isEmpty)
    }

    func testInvalidFrameDecoding() {
        let emptyData = Data()

        XCTAssertThrowsError(try ProtocolFrame.decode(emptyData)) { error in
            XCTAssertTrue(error is ProtocolError)
        }
    }
}
