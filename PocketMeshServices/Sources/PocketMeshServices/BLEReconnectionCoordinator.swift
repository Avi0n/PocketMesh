// BLEReconnectionCoordinator.swift

import OSLog

/// Coordinates the iOS auto-reconnect lifecycle, managing timeout state and
/// orchestrating teardown/rebuild via its delegate.
///
/// Extracted from ConnectionManager to isolate the reconnect timeout/state machine
/// from session rebuild logic.
@MainActor
final class BLEReconnectionCoordinator {

    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "BLEReconnectionCoordinator")

    weak var delegate: BLEReconnectionDelegate?

    /// The device ID currently being auto-reconnected, used to reject completions
    /// for a stale device when the user has manually connected to a different one.
    private(set) var reconnectingDeviceID: UUID?

    private var timeoutTask: Task<Void, Never>?

    /// Incremented each time a reconnection cycle starts, used to detect stale retries.
    private var reconnectGeneration = 0

    /// UI timeout duration before transitioning from "connecting" to "disconnected".
    /// iOS auto-reconnect continues in the background even after this fires.
    private let uiTimeoutDuration: TimeInterval

    init(uiTimeoutDuration: TimeInterval = 15) {
        self.uiTimeoutDuration = uiTimeoutDuration
    }

    /// Handles the device entering iOS auto-reconnect phase.
    /// Tears down session layer and starts a UI timeout.
    func handleEnteringAutoReconnect(deviceID: UUID) async {
        guard let delegate else { return }

        guard delegate.connectionIntent.wantsConnection else {
            logger.info("Ignoring auto-reconnect: user disconnected")
            await delegate.disconnectTransport()
            return
        }

        // C3 fix: set connecting state BEFORE awaiting teardown so that
        // handleReconnectionComplete() sees .connecting even if it runs
        // during the teardown await.
        delegate.setConnectionState(.connecting)
        reconnectingDeviceID = deviceID
        reconnectGeneration += 1

        // Tear down session layer (it's invalid now)
        await delegate.teardownSessionForReconnect()

        // Start UI timeout
        cancelTimeout()
        timeoutTask = Task { [weak self, uiTimeoutDuration] in
            try? await Task.sleep(for: .seconds(uiTimeoutDuration))
            guard !Task.isCancelled, let self else { return }
            await self.handleUITimeout(deviceID: deviceID)
        }
    }

    /// Handles iOS auto-reconnect completion. Cancels the UI timeout
    /// and delegates session rebuild to ConnectionManager.
    func handleReconnectionComplete(deviceID: UUID) async {
        guard let delegate else { return }

        guard delegate.connectionIntent.wantsConnection else {
            cancelTimeout()
            logger.info("Ignoring reconnection: user disconnected")
            reconnectingDeviceID = nil
            await delegate.disconnectTransport()
            return
        }

        // Reject stale device completions without canceling the active timeout,
        // so the current reconnect retains its timeout fallback
        if let expectedID = reconnectingDeviceID, expectedID != deviceID {
            logger.warning("[BLE] Ignoring auto-reconnect completion for \(deviceID.uuidString.prefix(8)): expecting \(expectedID.uuidString.prefix(8))")
            return
        }

        // This completion is for our device — safe to cancel timeout
        cancelTimeout()

        // Accept both disconnected (normal) and connecting (auto-reconnect in progress)
        let state = delegate.connectionState
        guard state == .disconnected || state == .connecting else {
            logger.info("Ignoring reconnection: already \(String(describing: state))")
            return
        }

        reconnectGeneration += 1
        let expectedGeneration = reconnectGeneration

        reconnectingDeviceID = nil
        delegate.setConnectionState(.connecting)

        do {
            try await delegate.rebuildSession(deviceID: deviceID)
        } catch {
            logger.warning("[BLE] Auto-reconnect session rebuild failed: \(error.localizedDescription) - retrying in 2s")
            await retryRebuild(deviceID: deviceID, expectedGeneration: expectedGeneration)
        }
    }

    /// Restarts the UI timeout without tearing down the session.
    /// Used when user taps Connect while iOS auto-reconnect is already in progress.
    func restartTimeout(deviceID: UUID) {
        reconnectingDeviceID = deviceID
        cancelTimeout()
        timeoutTask = Task { [weak self, uiTimeoutDuration] in
            try? await Task.sleep(for: .seconds(uiTimeoutDuration))
            guard !Task.isCancelled, let self else { return }
            await self.handleUITimeout(deviceID: deviceID)
        }
    }

    /// Cancels the UI timeout timer.
    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// Clears the reconnecting device ID, used when manual connect supersedes auto-reconnect.
    func clearReconnectingDevice() {
        reconnectingDeviceID = nil
    }

    /// Retries a failed session rebuild after a short delay, aborting if the reconnect
    /// generation has changed or the user disconnected during the wait.
    private func retryRebuild(deviceID: UUID, expectedGeneration: Int) async {
        guard let delegate else { return }

        try? await Task.sleep(for: .seconds(2))

        guard expectedGeneration == reconnectGeneration else {
            logger.info("New reconnect cycle started during rebuild retry delay - aborting stale retry")
            return
        }
        guard delegate.connectionIntent.wantsConnection else {
            logger.info("User disconnected during rebuild retry delay")
            await delegate.handleReconnectionFailure()
            return
        }

        do {
            try await delegate.rebuildSession(deviceID: deviceID)
            logger.info("[BLE] Auto-reconnect session rebuild succeeded on retry")
        } catch {
            logger.error("[BLE] Auto-reconnect session rebuild failed on retry: \(error.localizedDescription)")
            await delegate.handleReconnectionFailure()
        }
    }

    private func handleUITimeout(deviceID: UUID) async {
        guard let delegate, delegate.connectionState == .connecting else { return }

        reconnectingDeviceID = nil
        logger.warning(
            "[BLE] Auto-reconnect UI timeout (\(uiTimeoutDuration)s) fired - transitioning UI to disconnected (iOS reconnect continues in background)"
        )
        delegate.setConnectionState(.disconnected)
        delegate.setConnectedDevice(nil)
        await delegate.notifyConnectionLost()
    }
}

/// Delegate protocol for BLEReconnectionCoordinator.
/// ConnectionManager implements this to provide session management.
@MainActor
protocol BLEReconnectionDelegate: AnyObject {
    var connectionIntent: ConnectionIntent { get }
    var connectionState: ConnectionState { get }

    /// Sets the connection state (used by coordinator for state transitions).
    func setConnectionState(_ state: ConnectionState)

    /// Sets the connected device (used by coordinator to clear on timeout).
    func setConnectedDevice(_ device: DeviceDTO?)

    /// Tears down the current session and services for reconnection.
    func teardownSessionForReconnect() async

    /// Rebuilds the session after iOS auto-reconnect completes.
    func rebuildSession(deviceID: UUID) async throws

    /// Disconnects the BLE transport (used when user disconnected during reconnect).
    func disconnectTransport() async

    /// Notifies the UI layer of connection loss.
    func notifyConnectionLost() async

    /// Handles reconnection failure (cleanup session, disconnect transport).
    func handleReconnectionFailure() async
}
