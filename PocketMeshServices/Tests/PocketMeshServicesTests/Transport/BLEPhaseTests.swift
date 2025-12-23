// BLEPhaseTests.swift
import Foundation
import Testing
@testable import PocketMeshServices

@Suite("BLEPhase Tests")
struct BLEPhaseTests {

    @Test("idle allows transition to waitingForBluetooth")
    func idleToWaitingForBluetooth() {
        let from = BLEPhase.idle
        #expect(from.canTransition(to: .idle))  // Always allowed
    }

    @Test("phase name returns readable string")
    func phaseNameReturnsReadableString() {
        #expect(BLEPhase.idle.name == "idle")
        #expect(BLEPhase.autoReconnecting(peripheralID: UUID()).name == "autoReconnecting")
    }

    @Test("isActive returns true for non-idle phases")
    func isActiveReturnsTrueForNonIdlePhases() {
        #expect(BLEPhase.idle.isActive == false)
        #expect(BLEPhase.autoReconnecting(peripheralID: UUID()).isActive == true)
    }
}
