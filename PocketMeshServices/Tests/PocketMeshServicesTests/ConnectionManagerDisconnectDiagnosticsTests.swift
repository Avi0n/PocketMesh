import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ConnectionManager Disconnect Diagnostics Tests", .serialized)
@MainActor
struct ConnectionManagerDisconnectDiagnosticsTests {
    private static let lastDisconnectDiagnosticKey = "com.pocketmesh.lastDisconnectDiagnostic"

    private func createTestManager() throws -> (ConnectionManager, MockBLEStateMachine) {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let mock = MockBLEStateMachine()
        let manager = ConnectionManager(modelContainer: container, stateMachine: mock)
        return (manager, mock)
    }

    private func clearLastDisconnectDiagnostic() {
        UserDefaults.standard.removeObject(forKey: Self.lastDisconnectDiagnosticKey)
    }

    @Test("auto-reconnect entry persists disconnect diagnostic with error info")
    func autoReconnectEntryPersistsDisconnectDiagnostic() async throws {
        clearLastDisconnectDiagnostic()
        defer { clearLastDisconnectDiagnostic() }

        let (manager, mock) = try createTestManager()
        let deviceID = UUID()
        manager.setTestState(
            connectionState: .ready,
            currentTransportType: .bluetooth,
            connectionIntent: .wantsConnection()
        )

        // Yield to let handler wiring task from ConnectionManager init complete
        await Task.yield()
        await mock.simulateAutoReconnecting(
            deviceID: deviceID,
            errorInfo: "domain=CBErrorDomain, code=15, desc=Failed to encrypt"
        )

        // Wait for auto-reconnect handler to propagate state
        try await waitUntil("connectionState should transition to .connecting") {
            manager.connectionState == .connecting
        }

        let diagnostic = manager.lastDisconnectDiagnostic ?? ""
        #expect(
            diagnostic.localizedStandardContains("source=bleStateMachine.autoReconnectingHandler")
        )
        #expect(diagnostic.localizedStandardContains("code=15"))
        #expect(manager.connectionState == .connecting)
    }

    @Test("health check preserves intent and persists diagnostic when other app is connected")
    func healthCheckPersistsDiagnosticWhenOtherAppConnected() async throws {
        clearLastDisconnectDiagnostic()
        defer { clearLastDisconnectDiagnostic() }

        let (manager, mock) = try createTestManager()
        let deviceID = UUID()

        await mock.setStubbedIsConnected(false)
        await mock.setStubbedIsAutoReconnecting(false)
        await mock.setStubbedIsDeviceConnectedToSystem(true)

        manager.setTestState(
            connectionState: .disconnected,
            currentTransportType: .bluetooth,
            connectionIntent: .wantsConnection()
        )
        manager.testLastConnectedDeviceID = deviceID

        await manager.checkBLEConnectionHealth()

        let diagnostic = manager.lastDisconnectDiagnostic ?? ""
        #expect(
            diagnostic.localizedStandardContains("source=checkBLEConnectionHealth.otherAppConnected")
        )
        #expect(manager.connectionIntent.wantsConnection)
        #expect(manager.isReconnectionWatchdogRunning)

        await manager.appDidEnterBackground()
    }
}
