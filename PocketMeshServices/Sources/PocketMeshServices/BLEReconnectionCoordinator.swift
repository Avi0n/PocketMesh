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

    private var timeoutTask: Task<Void, Never>?

    /// UI timeout duration before transitioning from "connecting" to "disconnected".
    /// iOS auto-reconnect continues in the background even after this fires.
    private let uiTimeoutDuration: TimeInterval

    init(uiTimeoutDuration: TimeInterval = 10) {
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

        // Tear down session layer (it's invalid now)
        await delegate.teardownSessionForReconnect()

        // Show "connecting" state with pulsing blue icon
        delegate.setConnectionState(.connecting)

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

        cancelTimeout()

        guard delegate.connectionIntent.wantsConnection else {
            logger.info("Ignoring reconnection: user disconnected")
            await delegate.disconnectTransport()
            return
        }

        // Accept both disconnected (normal) and connecting (auto-reconnect in progress)
        let state = delegate.connectionState
        guard state == .disconnected || state == .connecting else {
            logger.info("Ignoring reconnection: already \(String(describing: state))")
            return
        }

        delegate.setConnectionState(.connecting)

        do {
            try await delegate.rebuildSession(deviceID: deviceID)
        } catch {
            logger.error("[BLE] Auto-reconnect session rebuild failed: \(error.localizedDescription)")
            await delegate.handleReconnectionFailure()
        }
    }

    /// Cancels the UI timeout timer.
    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func handleUITimeout(deviceID: UUID) async {
        guard let delegate, delegate.connectionState == .connecting else { return }

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
