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

    @Test("getMessage timeout override can be shorter than the session default")
    func getMessageRespectsShortTimeoutOverride() async {
        let transport = MockTransport()
        try? await transport.connect()

        let configuration = SessionConfiguration(defaultTimeout: 0.2, clientIdentifier: "MeshCore-Tests")
        let session = MeshCoreSession(transport: transport, configuration: configuration)
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: MeshCoreError.self) {
            _ = try await session.getMessage(timeout: 0.02)
        }

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .milliseconds(100))
    }

    @Test("getMessage timeout override can extend beyond the session default")
    func getMessageRespectsLongTimeoutOverride() async {
        let transport = MockTransport()
        try? await transport.connect()

        let configuration = SessionConfiguration(defaultTimeout: 0.02, clientIdentifier: "MeshCore-Tests")
        let session = MeshCoreSession(transport: transport, configuration: configuration)
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: MeshCoreError.self) {
            _ = try await session.getMessage(timeout: 0.12)
        }

        let elapsed = start.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(80))
    }
}
