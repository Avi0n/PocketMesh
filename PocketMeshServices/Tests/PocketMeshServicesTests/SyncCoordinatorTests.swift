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

    @Test("notifyConversationsChanged calls callback")
    @MainActor
    func notifyConversationsChangedCallsCallback() async {
        let coordinator = SyncCoordinator()
        let tracker = CallbackTracker()

        await coordinator.setConversationsChangedCallback {
            await tracker.markStarted()
        }

        await coordinator.notifyConversationsChanged()

        let callbackCalled = await tracker.started
        #expect(callbackCalled, "Callback should have been called")
    }

    @Test("Multiple contact notifications increment correctly")
    @MainActor
    func multipleContactNotificationsIncrementCorrectly() async {
        let coordinator = SyncCoordinator()

        await coordinator.notifyContactsChanged()
        await coordinator.notifyContactsChanged()

        #expect(coordinator.contactsVersion == 2)
    }

    @Test("Sync activity callbacks fire during full sync")
    @MainActor
    func syncActivityCallbacksFire() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { await tracker.markStarted() },
            onEnded: { await tracker.markEnded() }
        )

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService
        )

        let started = await tracker.started
        let ended = await tracker.ended
        #expect(started, "onSyncActivityStarted should have been called")
        #expect(ended, "onSyncActivityEnded should have been called")
    }

    @Test("Sync activity callbacks not double called on error")
    @MainActor
    func syncActivityCallbacksNotDoubleCalledOnError() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { },
            onEnded: { await tracker.incrementEndedCount() }
        )

        // Configure mock to throw error during contacts sync
        await mockContactService.setStubbedSyncContactsResult(.failure(SyncCoordinatorError.syncFailed("Test error")))

        do {
            try await coordinator.performFullSync(
                deviceID: testDeviceID,
                contactService: mockContactService,
                channelService: mockChannelService,
                messagePollingService: mockMessagePollingService
            )
            Issue.record("Should have thrown error")
        } catch {
            // Expected
        }

        let endedCount = await tracker.endedCount
        #expect(endedCount == 1, "onSyncActivityEnded should be called exactly once on error")
    }

    @Test("Sync activity ends before messages phase")
    @MainActor
    func syncActivityEndsBeforeMessagesPhase() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let orderTracker = OrderTrackingMessagePollingService()
        let testDeviceID = UUID()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { },
            onEnded: {
                // Record when activity ended
                await orderTracker.recordActivityEnded()
            }
        )

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: orderTracker
        )

        // Verify that activity ended BEFORE message polling started
        let activityEndedBeforeMessages = await orderTracker.activityEndedBeforeMessagePoll
        #expect(activityEndedBeforeMessages, "Activity should end before message polling starts")
    }
}

// MARK: - Test Helpers

/// Actor to safely track callback invocations from concurrent closures
actor CallbackTracker {
    var started = false
    var ended = false
    var endedCount = 0

    func markStarted() {
        started = true
    }

    func markEnded() {
        ended = true
    }

    func incrementEndedCount() {
        endedCount += 1
    }
}

/// Mock that tracks the order of activity ended callback vs message polling
actor OrderTrackingMessagePollingService: MessagePollingServiceProtocol {
    private var activityEndedTime: Date?
    private var messagePollTime: Date?

    /// Records when the activity ended callback was invoked
    func recordActivityEnded() {
        activityEndedTime = Date()
    }

    /// Whether activity ended before message polling started
    var activityEndedBeforeMessagePoll: Bool {
        guard let ended = activityEndedTime, let poll = messagePollTime else {
            return false
        }
        return ended < poll
    }

    // MARK: - MessagePollingServiceProtocol

    func pollAllMessages() async throws -> Int {
        messagePollTime = Date()
        return 0
    }
}
