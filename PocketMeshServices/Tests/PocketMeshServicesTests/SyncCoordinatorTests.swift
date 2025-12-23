// SyncCoordinatorTests.swift
import Testing
import Foundation
@testable import PocketMeshServices

@Suite("SyncCoordinator Tests")
struct SyncCoordinatorTests {

    @Test("SyncState cases are distinct")
    func syncStateCasesDistinct() {
        let idle = SyncState.idle
        let syncing = SyncState.syncing(progress: SyncProgress(phase: .contacts, current: 0, total: 0))
        let synced = SyncState.synced
        let failed = SyncState.failed(SyncCoordinatorError.notConnected)

        // Verify they're not equal
        #expect(idle != syncing)
        #expect(syncing != synced)
        #expect(synced != failed)
    }

    @Test("SyncProgress initializes correctly")
    func syncProgressInitializes() {
        let progress = SyncProgress(phase: .contacts, current: 5, total: 10)
        #expect(progress.phase == .contacts)
        #expect(progress.current == 5)
        #expect(progress.total == 10)
    }

    @Test("SyncPhase has all expected cases")
    func syncPhaseHasAllCases() {
        let phases: [SyncPhase] = [.contacts, .channels, .messages]
        #expect(phases.count == 3)
    }

    @Test("SyncCoordinator initializes with idle state")
    @MainActor
    func syncCoordinatorInitializesIdle() async {
        let coordinator = SyncCoordinator()
        #expect(coordinator.state == .idle)
        #expect(coordinator.contactsVersion == 0)
        #expect(coordinator.conversationsVersion == 0)
        #expect(coordinator.lastSyncDate == nil)
    }

    @Test("notifyContactsChanged increments contactsVersion")
    @MainActor
    func notifyContactsChangedIncrementsVersion() async {
        let coordinator = SyncCoordinator()
        let initialVersion = coordinator.contactsVersion

        await coordinator.notifyContactsChanged()

        #expect(coordinator.contactsVersion == initialVersion + 1)
    }

    @Test("notifyConversationsChanged increments conversationsVersion")
    @MainActor
    func notifyConversationsChangedIncrementsVersion() async {
        let coordinator = SyncCoordinator()
        let initialVersion = coordinator.conversationsVersion

        await coordinator.notifyConversationsChanged()

        #expect(coordinator.conversationsVersion == initialVersion + 1)
    }

    @Test("Multiple notifications increment correctly")
    @MainActor
    func multipleNotificationsIncrementCorrectly() async {
        let coordinator = SyncCoordinator()

        await coordinator.notifyContactsChanged()
        await coordinator.notifyContactsChanged()
        await coordinator.notifyConversationsChanged()

        #expect(coordinator.contactsVersion == 2)
        #expect(coordinator.conversationsVersion == 1)
    }
}
