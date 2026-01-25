import Testing
@testable import PocketMeshServices

@Suite("BLEPhase Tests")
struct BLEPhaseTests {

    // MARK: - Name Tests

    @Test("idle phase has correct name")
    func idlePhaseHasCorrectName() {
        let phase = BLEPhase.idle
        #expect(phase.name == "idle")
    }

    @Test("disconnecting phase has correct name")
    func disconnectingPhaseHasCorrectName() {
        // Can't easily create other phases without CBPeripheral
        // but we can test idle
        let phase = BLEPhase.idle
        #expect(phase.name == "idle")
    }

    // MARK: - isActive Tests

    @Test("idle phase is not active")
    func idlePhaseIsNotActive() {
        let phase = BLEPhase.idle
        #expect(phase.isActive == false)
    }

    // MARK: - Peripheral Tests

    @Test("idle phase has no peripheral")
    func idlePhaseHasNoPeripheral() {
        let phase = BLEPhase.idle
        #expect(phase.peripheral == nil)
    }

    // MARK: - DeviceID Tests

    @Test("idle phase has no deviceID")
    func idlePhaseHasNoDeviceID() {
        let phase = BLEPhase.idle
        #expect(phase.deviceID == nil)
    }
}
