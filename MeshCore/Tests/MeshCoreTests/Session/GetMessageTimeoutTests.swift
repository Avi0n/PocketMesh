import Testing
@testable import MeshCore

@Suite("MeshCoreSession getMessage timeout")
struct GetMessageTimeoutTests {
    @Test("getMessage times out when no response arrives")
    func getMessageTimesOutWhenNoResponseArrives() async {
        let transport = MockTransport()
        try? await transport.connect()

        let configuration = SessionConfiguration(defaultTimeout: 0.02, clientIdentifier: "MeshCore-Tests")
        let session = MeshCoreSession(transport: transport, configuration: configuration)

        await #expect(throws: MeshCoreError.self) {
            _ = try await session.getMessage()
        }
    }
}
