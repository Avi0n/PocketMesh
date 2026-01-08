import Testing
import Foundation
@testable import MeshCore

@Suite("WiFiTransport Tests")
struct WiFiTransportTests {

    @Test("Initial state is disconnected")
    func initialStateIsDisconnected() async {
        let transport = WiFiTransport()
        let isConnected = await transport.isConnected
        #expect(!isConnected)
    }

    @Test("Connect without configuration throws notConfigured")
    func connectWithoutConfigurationThrows() async {
        let transport = WiFiTransport()

        await #expect(throws: WiFiTransportError.notConfigured) {
            try await transport.connect()
        }
    }

    @Test("Connection to invalid host fails")
    func connectionToInvalidHostFails() async {
        let transport = WiFiTransport()
        await transport.setConnectionInfo(host: "999.999.999.999", port: 5000)

        await #expect(throws: WiFiTransportError.self) {
            try await transport.connect()
        }
    }

    @Test("Send without connection throws notConnected")
    func sendWithoutConnectionThrows() async {
        let transport = WiFiTransport()

        await #expect(throws: WiFiTransportError.notConnected) {
            try await transport.send(Data([0x01, 0x02, 0x03]))
        }
    }

    @Test("Disconnect when not connected is safe")
    func disconnectWhenNotConnectedIsSafe() async {
        let transport = WiFiTransport()
        await transport.disconnect()
        // Should not throw or crash
        let isConnected = await transport.isConnected
        #expect(!isConnected)
    }

    @Test("Configuration can be updated before connect")
    func configurationCanBeUpdated() async {
        let transport = WiFiTransport()
        await transport.setConnectionInfo(host: "192.168.1.1", port: 4000)
        await transport.setConnectionInfo(host: "192.168.1.2", port: 5000)
        // No crash expected; configuration should be updated
        let isConnected = await transport.isConnected
        #expect(!isConnected)
    }
}
