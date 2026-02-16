import OSLog
import PocketMeshServices
import SwiftUI

private let logger = Logger(subsystem: "com.pocketmesh", category: "RepeaterStatusVM")

/// ViewModel for repeater status display
@Observable
@MainActor
final class RepeaterStatusViewModel {

    // MARK: - Properties

    /// Current session
    var session: RemoteNodeSessionDTO?

    /// Last received status
    var status: RemoteNodeStatus?

    /// Neighbor entries
    var neighbors: [NeighbourInfo] = []

    /// Last received telemetry
    var telemetry: TelemetryResponse?

    /// Cached decoded data points to avoid repeated LPP decoding.
    /// The TelemetryResponse.dataPoints computed property decodes on every access,
    /// which causes memory pressure during SwiftUI re-renders.
    private(set) var cachedDataPoints: [LPPDataPoint] = []

    /// Loading states
    var isLoadingStatus = false
    var isLoadingNeighbors = false
    var isLoadingTelemetry = false

    /// Whether neighbors have been loaded at least once (for refresh logic)
    var neighborsLoaded = false

    /// Whether the neighbors disclosure group is expanded
    var neighborsExpanded = false

    /// Whether telemetry has been loaded at least once (for refresh logic)
    var telemetryLoaded = false

    /// Whether the telemetry disclosure group is expanded
    var telemetryExpanded = false

    /// Error message if any
    var errorMessage: String?

    // MARK: - OCV Curve Properties

    /// Whether the battery curve disclosure group is expanded
    var isBatteryCurveExpanded = false

    /// Selected OCV preset
    var selectedOCVPreset: OCVPreset = .liIon

    /// Current OCV voltage values
    var ocvValues: [Int] = OCVPreset.liIon.ocvArray

    /// Error from OCV save operation
    var ocvError: String?

    /// Contact ID for saving OCV settings
    private var contactID: UUID?

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?
    private var contactService: ContactService?
    var nodeSnapshotService: NodeSnapshotService?

    /// ID of the current session's snapshot (for enrichment).
    /// Because `handleStatusResponse` suspends while saving the snapshot,
    /// neighbor/telemetry handlers may fire before this is set.
    /// In that case, enrichment data is buffered in `pendingNeighborEntries`
    /// / `pendingTelemetryEntries` and flushed once the ID is available.
    private var currentSnapshotID: UUID?

    /// Buffered enrichment data received before `currentSnapshotID` was set.
    private var pendingNeighborEntries: [NeighborSnapshotEntry]?
    private var pendingTelemetryEntries: [TelemetrySnapshotEntry]?

    /// Previous snapshot for delta display
    private(set) var previousSnapshot: NodeStatusSnapshotDTO?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.repeaterAdminService = appState.services?.repeaterAdminService
        self.contactService = appState.services?.contactService
        self.nodeSnapshotService = appState.services?.nodeSnapshotService
        // Handler registration moved to registerHandlers() called from view's .task modifier
    }

    /// Register for push notification handlers
    /// Called from view's .task modifier to ensure proper lifecycle management
    /// This method is idempotent - it clears existing handlers before registering new ones
    func registerHandlers(appState: AppState) async {
        guard let repeaterAdminService = appState.services?.repeaterAdminService else { return }

        // Clear any existing handlers first (idempotent setup)
        await repeaterAdminService.clearHandlers()

        await repeaterAdminService.setStatusHandler { [weak self] status in
            await self?.handleStatusResponse(status)
        }

        await repeaterAdminService.setNeighboursHandler { [weak self] response in
            await MainActor.run {
                self?.handleNeighboursResponse(response)
            }
        }

        await repeaterAdminService.setTelemetryHandler { [weak self] response in
            await MainActor.run {
                self?.handleTelemetryResponse(response)
            }
        }

    }

    // MARK: - Status

    /// Timeout duration for status/neighbors requests
    private static let requestTimeout: Duration = .seconds(15)

    /// Timeout task for status request
    private var statusTimeoutTask: Task<Void, Never>?

    /// Timeout task for neighbors request
    private var neighborsTimeoutTask: Task<Void, Never>?

    /// Timeout task for telemetry request
    private var telemetryTimeoutTask: Task<Void, Never>?

    /// Check if error is a transient "not ready" error that should be retried.
    /// Error code 10 occurs when the firmware isn't fully ready after login.
    private func isTransientError(_ error: Error) -> Bool {
        guard let remoteError = error as? RemoteNodeError,
              case .sessionError(let meshError) = remoteError,
              case .deviceError(let code) = meshError else {
            return false
        }
        return code == 10
    }

    private static let statusRetryDelays: [Duration] = [
        .milliseconds(500),
        .seconds(1),
        .seconds(2),
    ]

    private func requestStatusWithRetries(sessionID: UUID) async throws -> RemoteNodeStatus {
        guard let repeaterAdminService else {
            throw RemoteNodeError.notConnected
        }

        var delayIterator = Self.statusRetryDelays.makeIterator()
        while true {
            do {
                return try await repeaterAdminService.requestStatus(sessionID: sessionID)
            } catch {
                guard isTransientError(error), let delay = delayIterator.next() else {
                    throw error
                }
                try? await Task.sleep(for: delay)
            }
        }
    }

    /// Request status from the repeater
    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard repeaterAdminService != nil else { return }

        self.session = session
        isLoadingStatus = true
        errorMessage = nil

        // Start timeout
        statusTimeoutTask?.cancel()
        statusTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingStatus == true && self?.status == nil {
                    self?.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
                    self?.isLoadingStatus = false
                }
            }
        }

        do {
            let response = try await requestStatusWithRetries(sessionID: session.id)
            await handleStatusResponse(response)
        } catch {
            errorMessage = error.localizedDescription
            isLoadingStatus = false
            statusTimeoutTask?.cancel()
        }
    }

    /// Request neighbors from the repeater
    func requestNeighbors(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingNeighbors = true
        errorMessage = nil

        // Start timeout
        neighborsTimeoutTask?.cancel()
        neighborsTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingNeighbors == true && (self?.neighbors.isEmpty ?? true) {
                    self?.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.requestTimedOut
                    self?.isLoadingNeighbors = false
                }
            }
        }

        do {
            let response = try await repeaterAdminService.requestNeighbors(sessionID: session.id)
            handleNeighboursResponse(response)
        } catch {
            errorMessage = error.localizedDescription
            isLoadingNeighbors = false  // Only clear on error
            neighborsTimeoutTask?.cancel()
        }
        // Note: Don't clear isLoadingNeighbors here - it's cleared by handleNeighboursResponse
    }

    /// Handle status response from push notification
    /// Validates response matches current session before updating
    func handleStatusResponse(_ response: RemoteNodeStatus) async {
        // Session validation: only accept responses for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              response.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }
        statusTimeoutTask?.cancel()  // Cancel timeout on success
        self.status = response
        self.isLoadingStatus = false

        // Capture snapshot for history
        guard let nodeSnapshotService, let session else { return }

        // Fetch previous snapshot BEFORE saving so we compare against the last visit
        let prev = await nodeSnapshotService.previousSnapshot(
            for: session.publicKey,
            before: .now
        )
        self.previousSnapshot = prev

        let snapshotID = await nodeSnapshotService.saveStatusSnapshot(
            nodePublicKey: session.publicKey,
            batteryMillivolts: response.batteryMillivolts,
            lastSNR: response.lastSNR,
            lastRSSI: Int16(clamping: response.lastRSSI),
            noiseFloor: Int16(clamping: response.noiseFloor),
            uptimeSeconds: response.uptimeSeconds,
            rxAirtimeSeconds: response.repeaterRxAirtimeSeconds,
            packetsSent: response.packetsSent,
            packetsReceived: response.packetsReceived
        )
        if let snapshotID {
            self.currentSnapshotID = snapshotID
        } else if let prevID = prev?.id {
            // Snapshot throttled — enrich the most recent existing snapshot instead
            self.currentSnapshotID = prevID
        }

        // Flush any enrichment data that arrived during the await
        if let enrichmentTarget = self.currentSnapshotID {
            if let pending = pendingNeighborEntries {
                pendingNeighborEntries = nil
                Task { await nodeSnapshotService.enrichWithNeighbors(pending, snapshotID: enrichmentTarget) }
            }
            if let pending = pendingTelemetryEntries {
                pendingTelemetryEntries = nil
                Task { await nodeSnapshotService.enrichWithTelemetry(pending, snapshotID: enrichmentTarget) }
            }
        }
    }

    /// Handle neighbours response from push notification
    func handleNeighboursResponse(_ response: NeighboursResponse) {
        // Note: NeighboursResponse may not include source prefix - validate if available
        neighborsTimeoutTask?.cancel()  // Cancel timeout on success
        self.neighbors = response.neighbours
        self.isLoadingNeighbors = false
        self.neighborsLoaded = true

        // Enrich current snapshot with neighbor data
        let entries = response.neighbours.map {
            NeighborSnapshotEntry(publicKeyPrefix: $0.publicKeyPrefix, snr: $0.snr, secondsAgo: $0.secondsAgo)
        }
        if let snapshotID = currentSnapshotID {
            Task { await nodeSnapshotService?.enrichWithNeighbors(entries, snapshotID: snapshotID) }
        } else {
            pendingNeighborEntries = entries
        }
    }

    // MARK: - Telemetry

    /// Request telemetry from the repeater
    func requestTelemetry(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingTelemetry = true

        // Start timeout
        telemetryTimeoutTask?.cancel()
        telemetryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingTelemetry == true && self?.telemetry == nil {
                    self?.isLoadingTelemetry = false
                }
            }
        }

        do {
            let response = try await repeaterAdminService.requestTelemetry(sessionID: session.id)
            handleTelemetryResponse(response)
        } catch {
            // Retry once on transient "not ready" errors (error code 10)
            if isTransientError(error) {
                try? await Task.sleep(for: .milliseconds(500))
                do {
                    let response = try await repeaterAdminService.requestTelemetry(sessionID: session.id)
                    handleTelemetryResponse(response)
                    return
                } catch {
                    // Retry failed, fall through to show error
                }
            }
            errorMessage = error.localizedDescription
            isLoadingTelemetry = false
            telemetryTimeoutTask?.cancel()
        }
    }

    /// Handle telemetry response from push notification
    func handleTelemetryResponse(_ response: TelemetryResponse) {
        // Session validation: only accept responses for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              response.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }
        telemetryTimeoutTask?.cancel()  // Cancel timeout on success
        self.telemetry = response
        // Decode and cache data points once to avoid repeated LPP decoding during view updates
        self.cachedDataPoints = response.dataPoints
        self.isLoadingTelemetry = false
        self.telemetryLoaded = true

        // Enrich current snapshot with telemetry data
        let entries: [TelemetrySnapshotEntry] = cachedDataPoints.compactMap { dp in
            let numericValue: Double?
            switch dp.value {
            case .float(let value):
                numericValue = value
            case .integer(let value):
                numericValue = Double(value)
            default:
                numericValue = nil
            }
            guard let value = numericValue else { return nil }
            return TelemetrySnapshotEntry(channel: Int(dp.channel), type: dp.typeName, value: value)
        }
        if !entries.isEmpty {
            if let snapshotID = currentSnapshotID {
                Task { await nodeSnapshotService?.enrichWithTelemetry(entries, snapshotID: snapshotID) }
            } else {
                pendingTelemetryEntries = entries
            }
        }
    }

    // MARK: - Telemetry Grouping

    /// Whether cached data points span multiple channels.
    var hasMultipleChannels: Bool {
        let channels = Set(cachedDataPoints.map(\.channel))
        return channels.count > 1
    }

    /// Data points grouped by channel, sorted by channel number.
    /// Only useful when `hasMultipleChannels` is true.
    var groupedDataPoints: [(channel: UInt8, dataPoints: [LPPDataPoint])] {
        Dictionary(grouping: cachedDataPoints, by: \.channel)
            .sorted { $0.key < $1.key }
            .map { (channel: $0.key, dataPoints: $0.value) }
    }

    // MARK: - Computed Properties

    /// Em-dash for missing data (cleaner than "Unavailable")
    private static let emDash = "—"

    var uptimeDisplay: String {
        guard let uptime = status?.uptimeSeconds else { return Self.emDash }
        let days = Int(uptime / 86400)
        let hours = Int((uptime % 86400) / 3600)
        let minutes = Int((uptime % 3600) / 60)

        if days > 0 {
            if days == 1 {
                return L10n.RemoteNodes.RemoteNodes.Status.uptime1Day(hours, minutes)
            } else {
                return L10n.RemoteNodes.RemoteNodes.Status.uptimeDays(days, hours, minutes)
            }
        } else if hours > 0 {
            return L10n.RemoteNodes.RemoteNodes.Status.uptimeHours(hours, minutes)
        }
        return L10n.RemoteNodes.RemoteNodes.Status.uptimeMinutes(minutes)
    }

    var batteryDisplay: String {
        guard let mv = status?.batteryMillivolts else { return Self.emDash }
        let volts = Double(mv) / 1000.0
        let battery = BatteryInfo(level: Int(mv))
        let percent = battery.percentage(using: ocvValues)
        return "\(volts.formatted(.number.precision(.fractionLength(2))))V (\(percent)%)"
    }

    var lastRSSIDisplay: String {
        guard let rssi = status?.lastRSSI else { return Self.emDash }
        return "\(rssi) dBm"
    }

    var lastSNRDisplay: String {
        guard let snr = status?.lastSNR else { return Self.emDash }
        return "\(snr.formatted(.number.precision(.fractionLength(1)))) dB"
    }

    var noiseFloorDisplay: String {
        guard let nf = status?.noiseFloor else { return Self.emDash }
        return "\(nf) dBm"
    }

    var packetsSentDisplay: String {
        guard let count = status?.packetsSent else { return Self.emDash }
        return count.formatted()
    }

    var packetsReceivedDisplay: String {
        guard let count = status?.packetsReceived else { return Self.emDash }
        return count.formatted()
    }

    var receiveErrorsDisplay: String? {
        guard let count = status?.receiveErrors, count > 0 else { return nil }
        return count.formatted()
    }

    // MARK: - Delta Display

    /// Format a delta timestamp relative to now.
    var previousSnapshotTimestamp: String? {
        guard let prev = previousSnapshot else { return nil }
        let interval = prev.timestamp.distance(to: .now)
        if interval < 3600 {
            return L10n.RemoteNodes.RemoteNodes.History.vsMinutesAgo(Int(interval / 60))
        } else if interval < 86400 {
            return L10n.RemoteNodes.RemoteNodes.History.vsHoursAgo(Int(interval / 3600))
        } else {
            return L10n.RemoteNodes.RemoteNodes.History.vsDate(prev.timestamp.formatted(.dateTime.month().day()))
        }
    }

    /// Battery delta from previous snapshot (in millivolts, positive = increase)
    var batteryDeltaMV: Int? {
        guard let current = status?.batteryMillivolts,
              let previous = previousSnapshot?.batteryMillivolts else { return nil }
        return Int(current) - Int(previous)
    }

    /// SNR delta from previous snapshot
    var snrDelta: Double? {
        guard let current = status?.lastSNR,
              let previous = previousSnapshot?.lastSNR else { return nil }
        return current - previous
    }

    /// RSSI delta from previous snapshot
    var rssiDelta: Int? {
        guard let current = status?.lastRSSI,
              let previous = previousSnapshot?.lastRSSI else { return nil }
        return Int(current) - Int(previous)
    }

    /// Noise floor delta from previous snapshot
    var noiseFloorDelta: Int? {
        guard let current = status?.noiseFloor,
              let previous = previousSnapshot?.noiseFloor else { return nil }
        return Int(current) - Int(previous)
    }

    /// Fetch all snapshots for the current node
    func fetchHistory() async -> [NodeStatusSnapshotDTO] {
        guard let nodeSnapshotService, let session else {
            logger.warning("fetchHistory: nodeSnapshotService or session is nil")
            return []
        }
        return await nodeSnapshotService.fetchSnapshots(for: session.publicKey)
    }

    // MARK: - OCV Settings

    /// Load OCV settings for a contact by public key
    func loadOCVSettings(publicKey: Data, deviceID: UUID) async {
        guard let contactService else { return }

        do {
            if let contact = try await contactService.getContact(deviceID: deviceID, publicKey: publicKey) {
                contactID = contact.id

                if let presetName = contact.ocvPreset {
                    if presetName == OCVPreset.custom.rawValue, let customString = contact.customOCVArrayString {
                        let parsed = customString.split(separator: ",")
                            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if parsed.count == 11 {
                            ocvValues = parsed
                            selectedOCVPreset = .custom
                            return
                        }
                    }
                    if let preset = OCVPreset(rawValue: presetName) {
                        selectedOCVPreset = preset
                        ocvValues = preset.ocvArray
                        return
                    }
                }

                selectedOCVPreset = .liIon
                ocvValues = OCVPreset.liIon.ocvArray
            }
        } catch {
            ocvError = L10n.RemoteNodes.RemoteNodes.Status.ocvLoadFailed
        }
    }

    /// Save OCV settings for the current contact
    func saveOCVSettings(preset: OCVPreset, values: [Int]) async {
        guard let contactService,
              let contactID else {
            ocvError = L10n.RemoteNodes.RemoteNodes.Status.ocvSaveNoContact
            return
        }

        ocvError = nil

        do {
            if preset == .custom {
                let customString = values.map(String.init).joined(separator: ",")
                try await contactService.updateContactOCVSettings(
                    contactID: contactID,
                    preset: OCVPreset.custom.rawValue,
                    customArray: customString
                )
            } else {
                try await contactService.updateContactOCVSettings(
                    contactID: contactID,
                    preset: preset.rawValue,
                    customArray: nil
                )
            }

            // Update local state
            selectedOCVPreset = preset
            ocvValues = values
        } catch {
            ocvError = L10n.RemoteNodes.RemoteNodes.Status.ocvSaveFailed(error.localizedDescription)
        }
    }
}
