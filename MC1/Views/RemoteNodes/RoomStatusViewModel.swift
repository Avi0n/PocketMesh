import MC1Services
import SwiftUI

/// ViewModel for room server status display
@Observable
@MainActor
final class RoomStatusViewModel {

    // MARK: - Shared Helper

    var helper = NodeStatusHelper()

    // MARK: - Dependencies

    private var roomAdminService: RoomAdminService?

    // MARK: - Initialization

    init() {}

    func configure(appState: AppState) {
        self.roomAdminService = appState.services?.roomAdminService
        helper.configure(
            contactService: appState.services?.contactService,
            nodeSnapshotService: appState.services?.nodeSnapshotService
        )
    }

    func registerHandlers(appState: AppState) async {
        guard let roomAdminService = appState.services?.roomAdminService else { return }

        await roomAdminService.clearHandlers()

        await roomAdminService.setStatusHandler { [weak self] status in
            await self?.handleStatusResponse(status)
        }

        await roomAdminService.setTelemetryHandler { [weak self] response in
            await self?.helper.handleTelemetryResponse(response)
        }
    }

    // MARK: - Status

    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard let roomAdminService else { return }

        if helper.session == nil { helper.session = session }
        helper.isLoadingStatus = true
        helper.errorMessage = nil

        do {
            let response = try await helper.performWithTransientRetries(operationName: "status") { [roomAdminService] timeout in
                return try await roomAdminService.requestStatus(sessionID: session.id, timeout: timeout)
            }
            await handleStatusResponse(response)
        } catch RemoteNodeError.timeout {
            helper.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
            helper.isLoadingStatus = false
        } catch {
            helper.errorMessage = error.localizedDescription
            helper.isLoadingStatus = false
        }
    }

    private func handleStatusResponse(_ response: RemoteNodeStatus) async {
        await helper.handleStatusResponse(
            response,
            postedCount: response.roomServerPostedCount,
            postPushCount: response.roomServerPostPushCount
        )
    }

    // MARK: - Telemetry

    func requestTelemetry(for session: RemoteNodeSessionDTO) async {
        guard let roomAdminService else { return }

        if helper.session == nil { helper.session = session }
        helper.isLoadingTelemetry = true
        helper.errorMessage = nil

        do {
            let response = try await helper.performWithTransientRetries(operationName: "telemetry") { [roomAdminService] timeout in
                return try await roomAdminService.requestTelemetry(sessionID: session.id, timeout: timeout)
            }
            helper.handleTelemetryResponse(response)
        } catch RemoteNodeError.timeout {
            helper.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
            helper.isLoadingTelemetry = false
        } catch {
            helper.errorMessage = error.localizedDescription
            helper.isLoadingTelemetry = false
        }
    }

    // MARK: - Room-Only Display

    var postsReceivedDisplay: String {
        guard let count = helper.status?.roomServerPostedCount else { return NodeStatusHelper.emDash }
        return count.formatted()
    }

    var postsPushedDisplay: String {
        guard let count = helper.status?.roomServerPostPushCount else { return NodeStatusHelper.emDash }
        return count.formatted()
    }
}
