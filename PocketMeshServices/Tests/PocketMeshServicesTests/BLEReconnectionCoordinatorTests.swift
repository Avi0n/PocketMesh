import Foundation
import Testing
@testable import PocketMeshServices

@Suite("BLEReconnectionCoordinator Tests")
@MainActor
struct BLEReconnectionCoordinatorTests {

    // MARK: - Test Helpers

    private func createCoordinator(
        delegate: MockReconnectionDelegate? = nil,
        uiTimeoutDuration: TimeInterval = 10
    ) -> (BLEReconnectionCoordinator, MockReconnectionDelegate) {
        let coordinator = BLEReconnectionCoordinator(uiTimeoutDuration: uiTimeoutDuration)
        let mockDelegate = delegate ?? MockReconnectionDelegate()
        coordinator.delegate = mockDelegate
        return (coordinator, mockDelegate)
    }

    // MARK: - handleEnteringAutoReconnect Tests

    @Test("entering auto-reconnect sets state to .connecting when user wants connection")
    func enteringAutoReconnectSetsConnecting() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())

        #expect(delegate.connectionState == .connecting)
    }

    @Test("entering auto-reconnect tears down session")
    func enteringAutoReconnectTearsDownSession() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())

        #expect(delegate.teardownSessionCallCount == 1)
    }

    @Test("entering auto-reconnect is ignored when intent is .userDisconnected")
    func enteringAutoReconnectIgnoredForUserDisconnected() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .userDisconnected
        delegate.connectionState = .disconnected

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())

        #expect(delegate.connectionState == .disconnected, "State should not change when user disconnected")
        #expect(delegate.teardownSessionCallCount == 0, "Session should not be torn down")
        #expect(delegate.disconnectTransportCallCount == 1, "Transport should be disconnected")
    }

    @Test("entering auto-reconnect is ignored when intent is .none")
    func enteringAutoReconnectIgnoredForNone() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .none
        delegate.connectionState = .disconnected

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())

        #expect(delegate.connectionState == .disconnected)
        #expect(delegate.disconnectTransportCallCount == 1)
    }

    // MARK: - handleReconnectionComplete Tests

    @Test("reconnection complete sets state to .connecting from .disconnected")
    func reconnectionCompleteSetsConnectingFromDisconnected() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .disconnected

        await coordinator.handleReconnectionComplete(deviceID: UUID())

        #expect(delegate.connectionState == .connecting)
    }

    @Test("reconnection complete sets state to .connecting from .connecting")
    func reconnectionCompleteSetsConnectingFromConnecting() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .connecting

        await coordinator.handleReconnectionComplete(deviceID: UUID())

        #expect(delegate.connectionState == .connecting)
    }

    @Test("reconnection complete calls rebuildSession")
    func reconnectionCompleteCallsRebuild() async {
        let deviceID = UUID()
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .disconnected

        await coordinator.handleReconnectionComplete(deviceID: deviceID)

        #expect(delegate.rebuildSessionCalls.count == 1)
        #expect(delegate.rebuildSessionCalls.first == deviceID)
    }

    @Test("reconnection complete is ignored when intent is .userDisconnected")
    func reconnectionCompleteIgnoredForUserDisconnected() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .userDisconnected
        delegate.connectionState = .disconnected

        await coordinator.handleReconnectionComplete(deviceID: UUID())

        #expect(delegate.rebuildSessionCalls.isEmpty, "Should not rebuild when user disconnected")
        #expect(delegate.disconnectTransportCallCount == 1, "Should disconnect transport")
    }

    @Test("reconnection complete is ignored when already .ready")
    func reconnectionCompleteIgnoredWhenReady() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleReconnectionComplete(deviceID: UUID())

        #expect(delegate.connectionState == .ready, "Should not change state when already ready")
        #expect(delegate.rebuildSessionCalls.isEmpty, "Should not rebuild when already ready")
    }

    @Test("reconnection complete handles rebuild failure")
    func reconnectionCompleteHandlesRebuildFailure() async {
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .disconnected
        delegate.rebuildSessionShouldThrow = true

        await coordinator.handleReconnectionComplete(deviceID: UUID())

        #expect(delegate.handleReconnectionFailureCallCount == 1)
    }

    @Test("stale device completion does not cancel active timeout")
    func staleDeviceDoesNotCancelTimeout() async throws {
        let activeDevice = UUID()
        let staleDevice = UUID()
        let (coordinator, delegate) = createCoordinator(uiTimeoutDuration: 0.1)
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleEnteringAutoReconnect(deviceID: activeDevice)
        #expect(delegate.connectionState == .connecting)

        // Stale completion for a different device should be rejected
        await coordinator.handleReconnectionComplete(deviceID: staleDevice)

        // Timeout should still fire because it was not canceled
        try await Task.sleep(for: .milliseconds(250))

        #expect(delegate.connectionState == .disconnected, "Timeout should still fire after stale completion")
        #expect(delegate.rebuildSessionCalls.isEmpty, "Should not rebuild for stale device")
    }

    // MARK: - UI Timeout Tests

    @Test("UI timeout transitions to disconnected after duration")
    func uiTimeoutTransitionsToDisconnected() async throws {
        let (coordinator, delegate) = createCoordinator(uiTimeoutDuration: 0.1)
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())
        #expect(delegate.connectionState == .connecting)

        // Wait for timeout
        try await Task.sleep(for: .milliseconds(250))

        #expect(delegate.connectionState == .disconnected)
        #expect(delegate.connectedDeviceWasCleared == true)
        #expect(delegate.notifyConnectionLostCallCount == 1)
    }

    @Test("UI timeout is cancelled when reconnection completes")
    func uiTimeoutCancelledOnReconnection() async throws {
        let deviceID = UUID()
        let (coordinator, delegate) = createCoordinator(uiTimeoutDuration: 0.1)
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleEnteringAutoReconnect(deviceID: deviceID)
        #expect(delegate.connectionState == .connecting)

        // Complete reconnection before timeout (same device)
        await coordinator.handleReconnectionComplete(deviceID: deviceID)

        // Wait past timeout duration
        try await Task.sleep(for: .milliseconds(250))

        // Should be .connecting from reconnection complete, not .disconnected from timeout
        #expect(delegate.connectionState == .connecting)
        #expect(delegate.notifyConnectionLostCallCount == 0)
    }

    // MARK: - Stale Retry Tests

    @Test("stale rebuild retry is aborted when new reconnect cycle starts during delay")
    func staleRetryAbortedOnNewCycle() async throws {
        let deviceID = UUID()
        let (coordinator, delegate) = createCoordinator()
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .disconnected
        delegate.rebuildSessionShouldThrow = true

        // Start first reconnection — rebuild will fail, triggering 2s retry delay
        let firstReconnectTask = Task {
            await coordinator.handleReconnectionComplete(deviceID: deviceID)
        }

        // Wait for first rebuild to fail and enter the 2s sleep
        try await Task.sleep(for: .milliseconds(100))
        #expect(delegate.rebuildSessionCalls.count == 1, "First rebuild should have been attempted")

        // Start a new reconnect cycle during the delay — this bumps the generation counter
        delegate.rebuildSessionShouldThrow = false
        await coordinator.handleReconnectionComplete(deviceID: deviceID)

        // Wait for the first task's stale retry to wake and be aborted
        await firstReconnectTask.value

        // Should have exactly 2 rebuild calls: first (failed) + new cycle (succeeded).
        // The stale retry should have been aborted by the generation check.
        #expect(delegate.rebuildSessionCalls.count == 2, "Stale retry should have been aborted")
        #expect(delegate.handleReconnectionFailureCallCount == 0, "No failure handler since new cycle succeeded")
    }

    // MARK: - cancelTimeout Tests

    @Test("cancelTimeout prevents timeout from firing")
    func cancelTimeoutPreventsTimeout() async throws {
        let (coordinator, delegate) = createCoordinator(uiTimeoutDuration: 0.1)
        delegate.connectionIntent = .wantsConnection()
        delegate.connectionState = .ready

        await coordinator.handleEnteringAutoReconnect(deviceID: UUID())
        coordinator.cancelTimeout()

        try await Task.sleep(for: .milliseconds(250))

        // State should remain .connecting (timeout was cancelled)
        #expect(delegate.connectionState == .connecting)
    }
}

// MARK: - Mock Delegate

@MainActor
private final class MockReconnectionDelegate: BLEReconnectionDelegate {
    var connectionIntent: ConnectionIntent = .none
    var connectionState: ConnectionState = .disconnected

    var teardownSessionCallCount = 0
    var rebuildSessionCalls: [UUID] = []
    var rebuildSessionShouldThrow = false
    var disconnectTransportCallCount = 0
    var notifyConnectionLostCallCount = 0
    var handleReconnectionFailureCallCount = 0
    var connectedDeviceWasCleared = false

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    func setConnectedDevice(_ device: DeviceDTO?) {
        if device == nil {
            connectedDeviceWasCleared = true
        }
    }

    func teardownSessionForReconnect() async {
        teardownSessionCallCount += 1
    }

    func rebuildSession(deviceID: UUID) async throws {
        rebuildSessionCalls.append(deviceID)
        if rebuildSessionShouldThrow {
            throw ReconnectionTestError.rebuildFailed
        }
    }

    func disconnectTransport() async {
        disconnectTransportCallCount += 1
    }

    func notifyConnectionLost() async {
        notifyConnectionLostCallCount += 1
    }

    func handleReconnectionFailure() async {
        handleReconnectionFailureCallCount += 1
    }
}

private enum ReconnectionTestError: Error {
    case rebuildFailed
}
