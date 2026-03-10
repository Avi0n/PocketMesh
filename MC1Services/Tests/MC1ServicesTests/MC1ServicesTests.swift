import Testing
@testable import MC1Services

@Suite("MC1Services Basic Tests")
struct MC1ServicesTests {

    @Test("Version is accessible")
    func versionAccessible() {
        #expect(MC1ServicesVersion.version == "0.1.0")
    }

    @Test("MeshCore types are re-exported")
    func meshCoreReExported() {
        // Verify MeshCore types are accessible without explicit import
        let _: MeshEvent.Type = MeshEvent.self
        let _: PacketBuilder.Type = PacketBuilder.self
        let _: PacketParser.Type = PacketParser.self
    }
}
