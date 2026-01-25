import Foundation
import Testing
@testable import PocketMeshServices

@Suite("BLEStateMachine Tests")
struct BLEStateMachineTests {

    // MARK: - Initial State Tests

    @Test("initializes in idle phase")
    func initializesInIdlePhase() async {
        let sm = BLEStateMachine()
        let phase = await sm.currentPhase
        #expect(phase.name == "idle")
    }

    @Test("isConnected returns false when idle")
    func isConnectedReturnsFalseWhenIdle() async {
        let sm = BLEStateMachine()
        let connected = await sm.isConnected
        #expect(connected == false)
    }

    @Test("connectedDeviceID returns nil when idle")
    func connectedDeviceIDReturnsNilWhenIdle() async {
        let sm = BLEStateMachine()
        let deviceID = await sm.connectedDeviceID
        #expect(deviceID == nil)
    }

    @Test("isAutoReconnecting returns false when idle")
    func isAutoReconnectingReturnsFalseWhenIdle() async {
        let sm = BLEStateMachine()
        let reconnecting = await sm.isAutoReconnecting
        #expect(reconnecting == false)
    }

    @Test("currentPhaseName returns idle when idle")
    func currentPhaseNameReturnsIdleWhenIdle() async {
        let sm = BLEStateMachine()
        let name = await sm.currentPhaseName
        #expect(name == "idle")
    }

    // MARK: - Handler Registration Tests

    @Test("setDisconnectionHandler can be registered")
    func setDisconnectionHandlerCanBeRegistered() async {
        let sm = BLEStateMachine()

        await sm.setDisconnectionHandler { _, _ in }

        #expect(await sm.currentPhase.name == "idle")
    }

    @Test("setReconnectionHandler can be registered")
    func setReconnectionHandlerCanBeRegistered() async {
        let sm = BLEStateMachine()

        await sm.setReconnectionHandler { _, _ in }

        #expect(await sm.currentPhase.name == "idle")
    }

    @Test("setBluetoothStateChangeHandler can be registered")
    func setBluetoothStateChangeHandlerCanBeRegistered() async {
        let sm = BLEStateMachine()

        await sm.setBluetoothStateChangeHandler { _ in }

        #expect(await sm.currentPhase.name == "idle")
    }

    @Test("setAutoReconnectingHandler can be registered")
    func setAutoReconnectingHandlerCanBeRegistered() async {
        let sm = BLEStateMachine()

        await sm.setAutoReconnectingHandler { _ in }

        #expect(await sm.currentPhase.name == "idle")
    }

    // MARK: - Disconnect Tests

    @Test("disconnect returns immediately when idle")
    func disconnectReturnsImmediatelyWhenIdle() async {
        let sm = BLEStateMachine()

        await sm.disconnect()

        #expect(await sm.currentPhase.name == "idle")
        #expect(await sm.isConnected == false)
    }

    // MARK: - Connection Error Tests

    @Test("connect throws appropriate error for unknown UUID")
    func connectThrowsAppropriateErrorForUnknownUUID() async throws {
        let sm = BLEStateMachine()
        let unknownID = UUID()

        // Wait for central manager to initialize
        try? await Task.sleep(for: .milliseconds(100))

        await #expect(throws: BLEError.self) {
            _ = try await sm.connect(to: unknownID)
        }
    }

    @Test("send throws notConnected when idle")
    func sendThrowsNotConnectedWhenIdle() async throws {
        let sm = BLEStateMachine()
        let testData = Data([0x01, 0x02, 0x03])

        do {
            try await sm.send(testData)
            Issue.record("Expected notConnected error")
        } catch let error as BLEError {
            if case .notConnected = error {
                // Expected
            } else {
                Issue.record("Expected notConnected error, got \(error)")
            }
        }
    }

    // MARK: - Idempotency Tests

    @Test("disconnect is idempotent")
    func disconnectIsIdempotent() async {
        let sm = BLEStateMachine()

        // Multiple disconnects should not crash
        await sm.disconnect()
        await sm.disconnect()
        await sm.disconnect()

        #expect(await sm.currentPhase.name == "idle")
    }

    @Test("handler replacement works correctly")
    func handlerReplacementWorksCorrectly() async {
        let sm = BLEStateMachine()

        await sm.setDisconnectionHandler { _, _ in }
        await sm.setDisconnectionHandler { _, _ in }

        // Multiple handler registrations should not crash
        #expect(await sm.currentPhase.name == "idle")
    }
}
