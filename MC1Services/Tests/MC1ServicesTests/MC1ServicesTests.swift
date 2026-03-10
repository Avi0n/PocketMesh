import Testing
@testable import PocketMeshServices

@Suite("PocketMeshServices Basic Tests")
struct PocketMeshServicesTests {

    @Test("Version is accessible")
    func versionAccessible() {
        #expect(PocketMeshServicesVersion.version == "0.1.0")
    }

    @Test("MeshCore types are re-exported")
    func meshCoreReExported() {
        // Verify MeshCore types are accessible without explicit import
        let _: MeshEvent.Type = MeshEvent.self
        let _: PacketBuilder.Type = PacketBuilder.self
        let _: PacketParser.Type = PacketParser.self
    }
}
