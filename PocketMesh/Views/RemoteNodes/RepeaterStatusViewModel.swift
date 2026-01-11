import SwiftUI
import PocketMeshServices

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

    /// Clock time from the repeater (stored as UTC)
    private var clockTimeUTC: String?

    /// Clock time converted to user's local timezone and locale
    var clockTime: String? {
        guard let utcString = clockTimeUTC else { return nil }
        return Self.convertUTCToLocal(utcString)
    }

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

    /// Current OCV array for telemetry percentage calculation
    var currentOCVArray: [Int] {
        ocvValues
    }

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?
    private var contactService: ContactService?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.repeaterAdminService = appState.services?.repeaterAdminService
        self.contactService = appState.services?.contactService
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
            await MainActor.run {
                self?.handleStatusResponse(status)
            }
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

        await repeaterAdminService.setCLIHandler { [weak self] frame, contact in
            await MainActor.run {
                self?.handleCLIResponse(frame, from: contact)
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

    /// Request status from the repeater
    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

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
                    self?.errorMessage = "Request timed out"
                    self?.isLoadingStatus = false
                }
            }
        }

        do {
            let response = try await repeaterAdminService.requestStatus(sessionID: session.id)
            handleStatusResponse(response)
            // Also request clock time
            _ = try? await repeaterAdminService.sendCommand(sessionID: session.id, command: "clock")
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
                    self?.errorMessage = "Request timed out"
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
    func handleStatusResponse(_ response: RemoteNodeStatus) {
        // Session validation: only accept responses for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              response.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }
        statusTimeoutTask?.cancel()  // Cancel timeout on success
        self.status = response
        self.isLoadingStatus = false
    }

    /// Handle neighbours response from push notification
    func handleNeighboursResponse(_ response: NeighboursResponse) {
        // Note: NeighboursResponse may not include source prefix - validate if available
        neighborsTimeoutTask?.cancel()  // Cancel timeout on success
        self.neighbors = response.neighbours
        self.isLoadingNeighbors = false
        self.neighborsLoaded = true
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
        self.isLoadingTelemetry = false
        self.telemetryLoaded = true
    }

    /// Handle CLI response (for clock time)
    func handleCLIResponse(_ frame: ContactMessage, from contact: ContactDTO) {
        // Validate session exists and response is from our session
        // Note: Compare using prefix bytes since contact.publicKey and session.publicKey
        // come from different sources (contacts database vs session)
        guard let session = session else {
            return
        }

        // Compare public key prefixes directly from the message sender
        // The contact's publicKeyPrefix should match the session's publicKeyPrefix
        guard Data(frame.senderPublicKeyPrefix) == Data(session.publicKeyPrefix) else {
            return
        }

        let response = CLIResponse.parse(frame.text)
        switch response {
        case .deviceTime(let time):
            self.clockTimeUTC = time
        default:
            break
        }
    }

    /// Convert UTC time string (e.g., "06:40 - 18/4/2025 UTC") to local time using user's locale
    private static func convertUTCToLocal(_ utcString: String) -> String {
        // Format: "HH:mm - d/M/yyyy UTC"
        let pattern = #"(\d{1,2}:\d{2}) - (\d{1,2}/\d{1,2}/\d{4}) UTC"#
        guard let regex = try? Regex(pattern),
              let match = utcString.firstMatch(of: regex),
              match.count >= 3 else {
            return utcString
        }

        let timeStr = String(match[1].substring ?? "")
        let dateStr = String(match[2].substring ?? "")

        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "HH:mm d/M/yyyy"
        inputFormatter.timeZone = TimeZone(identifier: "UTC")

        guard let date = inputFormatter.date(from: "\(timeStr) \(dateStr)") else {
            return utcString
        }

        let timeString = date.formatted(date: .omitted, time: .shortened)
        let dateString = date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits))
        return "\(timeString) - \(dateString)"
    }

    // MARK: - Computed Properties

    /// Em-dash for missing data (cleaner than "Unavailable")
    private static let emDash = "—"

    var uptimeDisplay: String {
        guard let uptime = status?.uptimeSeconds else { return Self.emDash }
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60

        if days > 0 {
            if days == 1 {
                return "1 day \(hours)h \(minutes)m"
            } else {
                return "\(days) days \(hours)h \(minutes)m"
            }
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var batteryDisplay: String {
        guard let mv = status?.batteryMillivolts else { return Self.emDash }
        let volts = Double(mv) / 1000.0
        let battery = BatteryInfo(level: Int(mv))
        let percent = battery.percentage(using: currentOCVArray)
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

    var clockDisplay: String {
        clockTime ?? Self.emDash
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
            ocvError = "Failed to load battery curve settings"
        }
    }

    /// Save OCV settings for the current contact
    func saveOCVSettings(preset: OCVPreset, values: [Int]) async {
        guard let contactService,
              let contactID else {
            ocvError = "Cannot save: contact not found"
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
            ocvError = "Failed to save: \(error.localizedDescription)"
        }
    }
}
