// SyncCoordinatorTests.swift
import Testing
import Foundation
import MeshCore
@testable import PocketMeshServices

@Suite("SyncCoordinator Tests")
struct SyncCoordinatorTests {

    /// Creates an in-memory persistence store with a test device
    private func createTestDataStore(
        deviceID: UUID,
        maxChannels: UInt8 = 8,
        lastContactSync: UInt32 = 0
    ) async throws -> PersistenceStore {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let device = DeviceDTO(from: Device(
            id: deviceID,
            publicKey: Data(repeating: 0x01, count: 32),
            nodeName: "TestDevice",
            firmwareVersion: 8,
            firmwareVersionString: "v1.0.0",
            manufacturerName: "TestMfg",
            buildDate: "01 Jan 2025",
            maxContacts: 100,
            maxChannels: maxChannels,
            frequency: 915_000,
            bandwidth: 250_000,
            spreadingFactor: 10,
            codingRate: 5,
            txPower: 20,
            maxTxPower: 20,
            latitude: 0,
            longitude: 0,
            blePin: 0,
            manualAddContacts: false,
            multiAcks: 0,
            telemetryModeBase: 0,
            telemetryModeLoc: 0,
            telemetryModeEnv: 0,
            advertLocationPolicy: 0,
            lastConnected: Date(),
            lastContactSync: lastContactSync,
            isActive: true
        ))
        try await store.saveDevice(device)
        return store
    }

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

    @Test("Sync activity callbacks fire during full sync")
    @MainActor
    func syncActivityCallbacksFire() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { await tracker.markStarted() },
            onEnded: { await tracker.markEnded() },
            onPhaseChanged: { _ in }
        )

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
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
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { },
            onEnded: { await tracker.incrementEndedCount() },
            onPhaseChanged: { _ in }
        )

        // Configure mock to throw error during contacts sync
        await mockContactService.setStubbedSyncContactsResult(.failure(SyncCoordinatorError.syncFailed("Test error")))

        do {
            try await coordinator.performFullSync(
                deviceID: testDeviceID,
                dataStore: dataStore,
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
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        await coordinator.setSyncActivityCallbacks(
            onStarted: { },
            onEnded: {
                // Record when activity ended
                await orderTracker.recordActivityEnded()
            },
            onPhaseChanged: { _ in }
        )

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: orderTracker
        )

        // Verify that activity ended BEFORE message polling started
        let activityEndedBeforeMessages = await orderTracker.activityEndedBeforeMessagePoll
        #expect(activityEndedBeforeMessages, "Activity should end before message polling starts")
    }

    @Test("onDisconnected clears notification suppression flag")
    @MainActor
    func onDisconnectedClearsSuppressionFlag() async throws {
        let coordinator = SyncCoordinator()

        // Create a test ServiceContainer
        let mockTransport = SimulatorMockTransport()
        let session = MeshCoreSession(transport: mockTransport)
        let services = try ServiceContainer.forTesting(session: session)

        // Manually set suppression flag to true (simulating mid-sync state)
        services.notificationService.isSuppressingNotifications = true
        #expect(services.notificationService.isSuppressingNotifications == true)

        // Call onDisconnected
        await coordinator.onDisconnected(services: services)

        // Verify flag is cleared
        #expect(services.notificationService.isSuppressingNotifications == false)
    }

    @Test("onDisconnected resets sync state to idle")
    @MainActor
    func onDisconnectedResetsSyncState() async throws {
        let coordinator = SyncCoordinator()

        // Create a test ServiceContainer
        let mockTransport = SimulatorMockTransport()
        let session = MeshCoreSession(transport: mockTransport)
        let services = try ServiceContainer.forTesting(session: session)

        // Call onDisconnected
        await coordinator.onDisconnected(services: services)

        // Verify state is idle
        #expect(coordinator.state == .idle)
    }

    @Test("onDisconnected calls onSyncActivityEnded when mid-sync in contacts phase")
    @MainActor
    func onDisconnectedCallsActivityEndedDuringContactsSync() async throws {
        let coordinator = SyncCoordinator()
        let delayingContactService = DelayingContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        // Create a test ServiceContainer
        let mockTransport = SimulatorMockTransport()
        let session = MeshCoreSession(transport: mockTransport)
        let services = try ServiceContainer.forTesting(session: session)

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { await tracker.markStarted() },
            onEnded: { await tracker.markEnded() },
            onPhaseChanged: { _ in }
        )

        // Start sync in background task - it will block during contacts phase
        let syncTask = Task {
            try await coordinator.performFullSync(
                deviceID: testDeviceID,
                dataStore: dataStore,
                contactService: delayingContactService,
                channelService: mockChannelService,
                messagePollingService: mockMessagePollingService
            )
        }

        // Wait for sync to start (activity started callback)
        try await Task.sleep(for: .milliseconds(50))
        let started = await tracker.started
        #expect(started, "Sync activity should have started")

        // Call onDisconnected while sync is in contacts phase
        await coordinator.onDisconnected(services: services)

        // Verify onSyncActivityEnded was called by onDisconnected
        let ended = await tracker.ended
        #expect(ended, "onSyncActivityEnded should be called when disconnecting mid-sync")

        // Cleanup: resume the sync so it doesn't hang
        await delayingContactService.completeSync()
        syncTask.cancel()
    }

    @Test("Background sync skips channel sync")
    @MainActor
    func backgroundSyncSkipsChannels() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let mockAppStateProvider = MockAppStateProvider(isInForeground: false)
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService,
            appStateProvider: mockAppStateProvider
        )

        // Channel sync should be skipped in background
        let channelInvocations = await mockChannelService.syncChannelsInvocations
        #expect(channelInvocations.isEmpty, "Channel sync should be skipped when in background")

        // Contact sync should still happen
        let contactInvocations = await mockContactService.syncContactsInvocations
        #expect(contactInvocations.count == 1, "Contact sync should still run in background")
    }

    @Test("Foreground sync includes channel sync")
    @MainActor
    func foregroundSyncIncludesChannels() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let mockAppStateProvider = MockAppStateProvider(isInForeground: true)
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService,
            appStateProvider: mockAppStateProvider
        )

        // Channel sync should run in foreground
        let channelInvocations = await mockChannelService.syncChannelsInvocations
        #expect(channelInvocations.count == 1, "Channel sync should run when in foreground")

        // Contact sync should also run
        let contactInvocations = await mockContactService.syncContactsInvocations
        #expect(contactInvocations.count == 1, "Contact sync should run in foreground")
    }

    @Test("Nil appStateProvider defaults to foreground behavior")
    @MainActor
    func nilAppStateProviderDefaultsToForeground() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService,
            appStateProvider: nil
        )

        // Should default to foreground (run channels)
        let channelInvocations = await mockChannelService.syncChannelsInvocations
        #expect(channelInvocations.count == 1, "Nil appStateProvider should default to foreground behavior")

        // Contact sync should also run
        let contactInvocations = await mockContactService.syncContactsInvocations
        #expect(contactInvocations.count == 1, "Contact sync should run with nil appStateProvider")
    }

    @Test("performFullSync ignores duplicate calls when already syncing")
    @MainActor
    func performFullSyncIgnoresDuplicateWhenSyncing() async throws {
        let coordinator = SyncCoordinator()
        let delayingContactService = DelayingContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: testDeviceID)

        let tracker = CallbackTracker()

        await coordinator.setSyncActivityCallbacks(
            onStarted: { await tracker.incrementEndedCount() }, // Reusing endedCount to track starts
            onEnded: { },
            onPhaseChanged: { _ in }
        )

        // Start first sync in background - it will block during contacts phase
        let firstSyncTask = Task {
            try await coordinator.performFullSync(
                deviceID: testDeviceID,
                dataStore: dataStore,
                contactService: delayingContactService,
                channelService: mockChannelService,
                messagePollingService: mockMessagePollingService
            )
        }

        // Wait for first sync to start
        try await Task.sleep(for: .milliseconds(50))

        // Try to start a second sync while first is still running
        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: delayingContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService
        )

        // Verify onSyncActivityStarted was only called once (not twice)
        let startCount = await tracker.endedCount
        #expect(startCount == 1, "onSyncActivityStarted should only be called once even with duplicate performFullSync calls")

        // Cleanup
        await delayingContactService.completeSync()
        firstSyncTask.cancel()
    }

    @Test("Contact sync passes lastContactSync timestamp from device")
    @MainActor
    func contactSyncPassesTimestamp() async throws {
        let coordinator = SyncCoordinator()
        let mockContactService = MockContactService()
        let mockChannelService = MockChannelService()
        let mockMessagePollingService = MockMessagePollingService()
        let testDeviceID = UUID()

        // Create device with a lastContactSync timestamp
        let lastSyncTimestamp: UInt32 = 1704067200 // 2024-01-01 00:00:00 UTC
        let dataStore = try await createTestDataStore(
            deviceID: testDeviceID,
            lastContactSync: lastSyncTimestamp
        )

        try await coordinator.performFullSync(
            deviceID: testDeviceID,
            dataStore: dataStore,
            contactService: mockContactService,
            channelService: mockChannelService,
            messagePollingService: mockMessagePollingService,
            appStateProvider: nil
        )

        let invocations = await mockContactService.syncContactsInvocations
        #expect(invocations.count == 1)

        // Verify the since parameter was passed
        let since = invocations[0].since
        let expectedDate = Date(timeIntervalSince1970: Double(lastSyncTimestamp))

        // Use try #require to safely unwrap and produce a clear failure message
        let actualSince = try #require(since, "Should pass lastContactSync as since parameter")
        #expect(actualSince == expectedDate, "Since date should match device lastContactSync")
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

    func waitForPendingHandlers(timeout: Duration) async -> Bool {
        true
    }
}

/// Mock contact service that delays and signals when sync has started
actor DelayingContactService: ContactServiceProtocol {
    private var continuation: CheckedContinuation<Void, Never>?

    /// Wait to be signaled that contacts sync has started
    func waitForSyncStart() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Allow the sync to complete
    func completeSync() {
        continuation?.resume()
        continuation = nil
    }

    func syncContacts(deviceID: UUID, since: Date?) async throws -> ContactSyncResult {
        // Signal that sync has started, then wait to be resumed
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task {
                // Store the continuation so completeSync can resume it
                self.continuation?.resume()
                self.continuation = cont
            }
        }
        return ContactSyncResult(contactsReceived: 0, lastSyncTimestamp: 0, isIncremental: false)
    }
}
