import Testing
@testable import MeshCore

@Suite("MeshCore Tests")
struct MeshCoreTests {

    @Test("Package compiles")
    func packageCompiles() {
        // Verify basic types are accessible
        let commandCode = CommandCode.appStart
        #expect(commandCode.rawValue == 0x01)

        let responseCode = ResponseCode.ok
        #expect(responseCode.rawValue == 0x00)
    }
}
