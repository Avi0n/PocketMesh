import OSLog
import MC1Services
import SwiftUI

private let logger = Logger(subsystem: "com.mc1", category: "RepeaterStatusVM")

/// ViewModel for repeater status display
@Observable
@MainActor
final class RepeaterStatusViewModel {

    // MARK: - Shared Helper

    var helper = NodeStatusHelper()

    // MARK: - Repeater-Only Properties

    /// Neighbor entries
    var neighbors: [NeighbourInfo] = []

    /// Loading states
    var isLoadingNeighbors = false

    /// Whether neighbors have been loaded at least once (for refresh logic)
    var neighborsLoaded = false

    /// Whether the neighbors disclosure group is expanded
    var neighborsExpanded = false

    /// Owner info text
    var ownerInfo: String?

    /// Owner info loading/state
    var isLoadingOwnerInfo = false
    var ownerInfoLoaded: Bool { ownerInfo != nil }
    var ownerInfoExpanded = false
    var ownerInfoError: String?

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?

    /// Buffered neighbor enrichment data received before snapshot ID was set.
    private var pendingNeighborEntries: [NeighborSnapshotEntry]?

    // MARK: - Initialization

    init() {}

    func configure(appState: AppState) {
        self.repeaterAdminService = appState.services?.repeaterAdminService
        helper.configure(
            contactService: appState.services?.contactService,
            nodeSnapshotService: appState.services?.nodeSnapshotService
        )
    }

    func registerHandlers(appState: AppState) async {
        guard let repeaterAdminService = appState.services?.repeaterAdminService else { return }

        await repeaterAdminService.clearHandlers()

        await repeaterAdminService.setStatusHandler { [weak self] status in
            await self?.handleStatusResponse(status)
        }

        await repeaterAdminService.setNeighboursHandler { [weak self] response in
            await self?.handleNeighboursResponse(response)
        }

        await repeaterAdminService.setTelemetryHandler { [weak self] response in
            await self?.helper.handleTelemetryResponse(response)
        }
    }

    // MARK: - Status

    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        if helper.session == nil { helper.session = session }
        helper.isLoadingStatus = true
        helper.errorMessage = nil

        do {
            let response = try await helper.performWithTransientRetries(operationName: "status") { [repeaterAdminService] timeout in
                return try await repeaterAdminService.requestStatus(sessionID: session.id, timeout: timeout)
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
            rxAirtimeSeconds: response.repeaterRxAirtimeSeconds,
            receiveErrors: response.receiveErrors
        )

        // Flush any buffered neighbor entries now that snapshot ID is set
        if let pending = pendingNeighborEntries {
            pendingNeighborEntries = nil
            helper.flushPendingNeighborEntries(pending)
        }
    }

    // MARK: - Neighbors

    func requestNeighbors(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        if helper.session == nil { helper.session = session }
        isLoadingNeighbors = true
        helper.errorMessage = nil

        do {
            let response = try await helper.performWithTransientRetries(operationName: "neighbors") { [repeaterAdminService] timeout in
                return try await repeaterAdminService.requestNeighbors(sessionID: session.id, timeout: timeout)
            }
            handleNeighboursResponse(response)
        } catch RemoteNodeError.timeout {
            helper.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
            isLoadingNeighbors = false
        } catch {
            helper.errorMessage = error.localizedDescription
            isLoadingNeighbors = false
        }
    }

    func handleNeighboursResponse(_ response: NeighboursResponse) {
        self.neighbors = response.neighbours
        self.isLoadingNeighbors = false
        self.neighborsLoaded = true

        let entries = response.neighbours.map {
            NeighborSnapshotEntry(publicKeyPrefix: $0.publicKeyPrefix, snr: $0.snr, secondsAgo: $0.secondsAgo)
        }
        if !helper.enrichWithNeighbors(entries) {
            pendingNeighborEntries = entries
        }
    }

    // MARK: - Telemetry

    func requestTelemetry(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        if helper.session == nil { helper.session = session }
        helper.isLoadingTelemetry = true
        helper.errorMessage = nil

        do {
            let response = try await helper.performWithTransientRetries(operationName: "telemetry") { [repeaterAdminService] timeout in
                return try await repeaterAdminService.requestTelemetry(sessionID: session.id, timeout: timeout)
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

    // MARK: - Owner Info

    func requestOwnerInfo(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }
        if helper.session == nil { helper.session = session }

        ownerInfoError = nil
        isLoadingOwnerInfo = true

        do {
            let response = try await helper.performWithTransientRetries(operationName: "ownerInfo") { [repeaterAdminService] timeout in
                return try await repeaterAdminService.requestOwnerInfo(sessionID: session.id, timeout: timeout)
            }
            ownerInfo = response.ownerInfo
        } catch RemoteNodeError.timeout {
            ownerInfoError = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
        } catch {
            ownerInfoError = error.localizedDescription
        }
        isLoadingOwnerInfo = false
    }

    // MARK: - Repeater-Only Display

    var receiveErrorsDisplay: String? {
        guard let count = helper.status?.receiveErrors, count > 0 else { return nil }
        return count.formatted()
    }
}
