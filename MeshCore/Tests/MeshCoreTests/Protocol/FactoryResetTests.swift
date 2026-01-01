import XCTest
@testable import MeshCore

final class FactoryResetTests: XCTestCase {

    func test_factoryReset_includesGuardString() {
        let packet = PacketBuilder.factoryReset()

        // Firmware requires: [0x33]['r']['e']['s']['e']['t']
        XCTAssertEqual(packet.count, 6, "Should be 6 bytes: command + 'reset'")
        XCTAssertEqual(packet[0], 0x33, "Byte 0 should be command code 0x33")

        let guardString = String(data: Data(packet[1...]), encoding: .utf8)
        XCTAssertEqual(guardString, "reset", "Bytes 1-5 should be 'reset'")
    }

    func test_factoryReset_exactBytes() {
        let packet = PacketBuilder.factoryReset()

        let expected = Data([0x33, 0x72, 0x65, 0x73, 0x65, 0x74])  // 0x33 + "reset"
        XCTAssertEqual(packet, expected)
    }
}
