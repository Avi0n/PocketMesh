import XCTest
@testable import MeshCore

final class NewCommandsTests: XCTestCase {

    func test_sendRawData_format() {
        let path = Data([0x11, 0x22])
        let payload = Data([0xAA, 0xBB, 0xCC])

        let packet = PacketBuilder.sendRawData(path: path, payload: payload)

        XCTAssertEqual(packet[0], 0x19, "Command code")
        XCTAssertEqual(packet[1], 0x02, "Path length")
        XCTAssertEqual(Data(packet[2..<4]), path, "Path data")
        XCTAssertEqual(Data(packet[4...]), payload, "Payload")
    }

    func test_sendRawData_emptyPath() {
        let packet = PacketBuilder.sendRawData(path: Data(), payload: Data([0xAA]))
        XCTAssertEqual(packet[1], 0x00, "Empty path length")
        XCTAssertEqual(packet.count, 3, "command + pathLen + payload")
    }

    func test_hasConnection_format() {
        let pubkey = Data(repeating: 0xAA, count: 32)

        let packet = PacketBuilder.hasConnection(publicKey: pubkey)

        XCTAssertEqual(packet.count, 33, "1 + 32 bytes")
        XCTAssertEqual(packet[0], 0x1C, "Command code")
        XCTAssertEqual(Data(packet[1...]), pubkey, "Public key")
    }

    func test_getContactByKey_format() {
        let pubkey = Data(repeating: 0xBB, count: 32)

        let packet = PacketBuilder.getContactByKey(publicKey: pubkey)

        XCTAssertEqual(packet.count, 33, "1 + 32 bytes")
        XCTAssertEqual(packet[0], 0x1E, "Command code")
        XCTAssertEqual(Data(packet[1...]), pubkey, "Public key")
    }

    func test_getAdvertPath_format() {
        let pubkey = Data(repeating: 0xCC, count: 32)

        let packet = PacketBuilder.getAdvertPath(publicKey: pubkey)

        XCTAssertEqual(packet.count, 34, "1 + 1 + 32 bytes")
        XCTAssertEqual(packet[0], 0x2A, "Command code")
        XCTAssertEqual(packet[1], 0x00, "Reserved byte")
        XCTAssertEqual(Data(packet[2...]), pubkey, "Public key")
    }

    func test_getTuningParams_format() {
        let packet = PacketBuilder.getTuningParams()

        XCTAssertEqual(packet.count, 1)
        XCTAssertEqual(packet[0], 0x2B, "Command code")
    }
}
