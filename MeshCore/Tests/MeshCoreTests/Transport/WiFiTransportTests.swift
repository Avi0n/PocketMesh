import Testing
import Foundation
import MeshCoreTestSupport
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

    @Test("Disconnection handler can be set and cleared")
    func disconnectionHandlerCanBeSetAndCleared() async {
        let transport = WiFiTransport()
        let callTracker = CallTracker()

        await transport.setDisconnectionHandler { _ in
            callTracker.markCalled()
        }

        // Handler is set but not called yet (no disconnection)
        #expect(!callTracker.wasCalled)

        // Clear handler should work without crash
        await transport.clearDisconnectionHandler()
    }

    @Test("connectionInfo returns configured host and port")
    func connectionInfoReturnsConfiguredValues() async {
        let transport = WiFiTransport()

        // Initially nil
        let initialInfo = await transport.connectionInfo
        #expect(initialInfo == nil)

        // After configuration
        await transport.setConnectionInfo(host: "192.168.1.50", port: 5000)
        let info = await transport.connectionInfo
        #expect(info?.host == "192.168.1.50")
        #expect(info?.port == 5000)
    }

    @Test("Disconnection handler not called on user-initiated disconnect")
    func disconnectionHandlerNotCalledOnUserDisconnect() async {
        let transport = WiFiTransport()
        let callTracker = CallTracker()

        await transport.setDisconnectionHandler { _ in
            callTracker.markCalled()
        }

        // User-initiated disconnect should NOT trigger handler
        await transport.disconnect()

        // Give any async callbacks time to fire
        try? await Task.sleep(for: .milliseconds(100))

        #expect(!callTracker.wasCalled, "Handler should not be called on user disconnect")
    }

    @Test("Disconnection handler not called on initial connect failure")
    func disconnectionHandlerNotCalledOnInitialConnectFailure() async {
        let transport = WiFiTransport()
        let callTracker = CallTracker()

        await transport.setDisconnectionHandler { _ in
            callTracker.markCalled()
        }

        // Configure to invalid host
        await transport.setConnectionInfo(host: "999.999.999.999", port: 5000)

        // Initial connect failure should NOT trigger disconnection handler
        do {
            try await transport.connect()
        } catch {
            // Expected to fail
        }

        try? await Task.sleep(for: .milliseconds(100))

        #expect(!callTracker.wasCalled, "Handler should not be called on initial connect failure")
    }
}
