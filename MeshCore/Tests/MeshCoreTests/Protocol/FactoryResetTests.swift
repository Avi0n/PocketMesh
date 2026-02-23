import Foundation
import Testing
@testable import MeshCore

@Suite("FactoryReset")
struct FactoryResetTests {

    @Test("factoryReset includes guard string")
    func factoryResetIncludesGuardString() {
        let packet = PacketBuilder.factoryReset()

        // Firmware requires: [0x33]['r']['e']['s']['e']['t']
        #expect(packet.count == 6, "Should be 6 bytes: command + 'reset'")
        #expect(packet[0] == 0x33, "Byte 0 should be command code 0x33")

        let guardString = String(data: Data(packet[1...]), encoding: .utf8)
        #expect(guardString == "reset", "Bytes 1-5 should be 'reset'")
    }

    @Test("factoryReset exact bytes")
    func factoryResetExactBytes() {
        let packet = PacketBuilder.factoryReset()

        let expected = Data([0x33, 0x72, 0x65, 0x73, 0x65, 0x74])  // 0x33 + "reset"
        #expect(packet == expected)
    }
}
