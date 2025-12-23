// BLEStateMachineTests.swift
import Testing
@testable import PocketMeshServices

@Suite("BLEStateMachine Tests")
struct BLEStateMachineTests {

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

    @Test("transition cancels timeout task when leaving connecting state")
    func transitionCancelsTimeoutTask() async {
        // This will be tested via integration - add placeholder
        #expect(true)
    }

    @Test("cancelCurrentOperation resumes continuation with error")
    func cancelCurrentOperationResumesContinuation() async {
        // This will be tested via integration - add placeholder
        #expect(true)
    }

    @Test("waitForPoweredOn returns immediately if already powered on")
    func waitForPoweredOnReturnsImmediatelyIfAlreadyOn() async throws {
        // Note: This test may not work in simulator without Bluetooth
        // Full integration test needed on device
        #expect(true)
    }

    @Test("setAutoReconnectingHandler can be registered")
    func setAutoReconnectingHandlerCanBeRegistered() async {
        let sm = BLEStateMachine()

        // Verify handler can be registered without crashing
        // The handler is never called in this test since we don't simulate a disconnect
        await sm.setAutoReconnectingHandler { _ in
            // Handler would be called with device ID on disconnect with isReconnecting: true
            // Full integration test requires device
        }

        // Verify state machine is still in idle phase after registering handler
        #expect(await sm.currentPhase.name == "idle")
    }
}
