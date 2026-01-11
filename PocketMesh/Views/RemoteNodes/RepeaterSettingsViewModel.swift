import SwiftUI
import PocketMeshServices
import OSLog

@Observable
@MainActor
final class RepeaterSettingsViewModel {

    // MARK: - Properties

    var session: RemoteNodeSessionDTO?

    // Device info (read-only from ver/clock)
    var firmwareVersion: String?
    private var deviceTimeUTC: String?
    var isLoadingDeviceInfo = false
    var deviceInfoError: String?
    var deviceInfoLoaded: Bool { firmwareVersion != nil || deviceTimeUTC != nil }

    /// Device time converted to user's local timezone and locale
    var deviceTime: String? {
        guard let utcString = deviceTimeUTC else { return nil }
        return Self.convertUTCToLocal(utcString)
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

    // Identity settings (from get name, get lat, get lon)
    var name: String?
    var latitude: Double?
    var longitude: Double?
    private var originalName: String?
    private var originalLatitude: Double?
    private var originalLongitude: Double?
    var isLoadingIdentity = false
    var identityError: String?
    var identityLoaded: Bool { originalName != nil || originalLatitude != nil || originalLongitude != nil }

    // Radio settings (from get radio, get tx)
    var frequency: Double?
    var bandwidth: Double?
    var spreadingFactor: Int?
    var codingRate: Int?
    var txPower: Int?
    var isLoadingRadio = false
    var radioError: String?
    var radioLoaded: Bool { frequency != nil || txPower != nil }

    // Behavior settings (from get repeat, get advert.interval, get flood.max)
    var advertIntervalMinutes: Int?
    var floodAdvertIntervalHours: Int?
    var floodMaxHops: Int?
    var repeaterEnabled: Bool?
    private var originalAdvertIntervalMinutes: Int?
    private var originalFloodAdvertIntervalHours: Int?
    private var originalFloodMaxHops: Int?
    private var originalRepeaterEnabled: Bool?
    var isLoadingBehavior = false
    var behaviorError: String?
    var behaviorLoaded: Bool { repeaterEnabled != nil || advertIntervalMinutes != nil }

    // Validation errors for behavior fields
    var advertIntervalError: String?
    var floodAdvertIntervalError: String?
    var floodMaxHopsError: String?

    // Password change (no query available)
    var newPassword: String = ""
    var confirmPassword: String = ""

    // Expansion state for DisclosureGroups
    var isDeviceInfoExpanded = false
    var isRadioExpanded = false
    var isIdentityExpanded = false
    var isBehaviorExpanded = false
    var isSecurityExpanded = false

    // State
    var isApplying = false
    var isRebooting = false
    var errorMessage: String?
    var successMessage: String?
    var showSuccessAlert = false
    var showErrorAlert = false
    var identityApplySuccess = false
    var behaviorApplySuccess = false

    /// Track if radio settings have been modified (requires restart)
    var radioSettingsModified = false

    /// Track if identity settings have been modified
    var identitySettingsModified: Bool {
        (name != nil && name != originalName) ||
        (latitude != nil && latitude != originalLatitude) ||
        (longitude != nil && longitude != originalLongitude)
    }

    /// Track if behavior settings have been modified
    var behaviorSettingsModified: Bool {
        (repeaterEnabled != nil && repeaterEnabled != originalRepeaterEnabled) ||
        (advertIntervalMinutes != nil && advertIntervalMinutes != originalAdvertIntervalMinutes) ||
        (floodAdvertIntervalHours != nil && floodAdvertIntervalHours != originalFloodAdvertIntervalHours) ||
        (floodMaxHops != nil && floodMaxHops != originalFloodMaxHops)
    }

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?
    private let logger = Logger(subsystem: "PocketMesh", category: "RepeaterSettings")

    /// Stream continuation for receiving CLI responses
    private var responseStreamContinuation: AsyncStream<String>.Continuation?

    /// Currently expected command (for logging/debugging)
    private var currentCommand: String?

    // MARK: - Cleanup

    /// Cancel any pending operations when view disappears
    func cleanup() {
        responseStreamContinuation?.finish()
        responseStreamContinuation = nil
        currentCommand = nil
    }

    // MARK: - Synchronous Command-Response

    /// Send a CLI command and wait for its response
    /// - Parameters:
    ///   - command: The CLI command to send (e.g., "get name", "ver")
    ///   - timeout: Maximum time to wait for response (default 5 seconds)
    /// - Returns: The raw response text from the repeater
    /// - Throws: RepeaterSettingsError.timeout if no response received
    private func sendAndWait(_ command: String, timeout: Duration = .seconds(5)) async throws -> String {
        guard let session, let service = repeaterAdminService else {
            throw RepeaterSettingsError.noService
        }

        currentCommand = command
        defer {
            currentCommand = nil
            responseStreamContinuation?.finish()
            responseStreamContinuation = nil
        }

        // Create stream FIRST (before sending command) to avoid missing fast responses
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.responseStreamContinuation = continuation

        // Send command - response arrives via handleCLIResponse
        _ = try await service.sendCommand(sessionID: session.id, command: command)
        logger.debug("Sent command: \(command)")

        // Race response against timeout
        // Keep consuming responses until we get one that parses for our command
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for await response in stream {
                    // Validate response matches expected command
                    let parsed = CLIResponse.parse(response, forQuery: command)
                    if case .raw = parsed {
                        // Unrecognized response - likely from a different command, keep waiting
                        self.logger.warning("Discarding mismatched response '\(response.prefix(20))' for command '\(command)'")
                    } else {
                        return response
                    }
                }
                throw RepeaterSettingsError.timeout
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw RepeaterSettingsError.timeout
            }

            guard let result = try await group.next() else {
                throw RepeaterSettingsError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Configuration

    func configure(appState: AppState, session: RemoteNodeSessionDTO) {
        self.repeaterAdminService = appState.services?.repeaterAdminService
        self.session = session
        self.name = session.name
    }

    // MARK: - Fetch Methods (Pull-to-Load)

    /// Fetch device info (firmware version and time)
    func fetchDeviceInfo() async {
        isLoadingDeviceInfo = true
        deviceInfoError = nil

        // Get firmware version
        do {
            let response = try await sendAndWait("ver")
            if case .version(let version) = CLIResponse.parse(response, forQuery: "ver") {
                self.firmwareVersion = version
                logger.debug("Received firmware version: \(version)")
            }
        } catch {
            logger.warning("Failed to get firmware version: \(error)")
        }

        // Get device time
        do {
            let response = try await sendAndWait("clock")
            if case .deviceTime(let time) = CLIResponse.parse(response, forQuery: "clock") {
                self.deviceTimeUTC = time
                logger.debug("Received device time: \(time)")
            }
        } catch {
            logger.warning("Failed to get device time: \(error)")
        }

        // Only show error if no data was received
        if !deviceInfoLoaded {
            deviceInfoError = "Failed to load device info"
        }

        isLoadingDeviceInfo = false
    }

    /// Fetch identity settings (name, latitude, longitude)
    func fetchIdentity() async {
        isLoadingIdentity = true
        identityError = nil

        // Get name
        do {
            let response = try await sendAndWait("get name")
            if case .name(let n) = CLIResponse.parse(response, forQuery: "get name") {
                self.name = n
                self.originalName = n
                logger.debug("Received name: \(n)")
            }
        } catch {
            logger.warning("Failed to get name: \(error)")
        }

        // Get latitude
        do {
            let response = try await sendAndWait("get lat")
            if case .latitude(let lat) = CLIResponse.parse(response, forQuery: "get lat") {
                self.latitude = lat
                self.originalLatitude = lat
                logger.debug("Received latitude: \(lat)")
            }
        } catch {
            logger.warning("Failed to get latitude: \(error)")
        }

        // Get longitude
        do {
            let response = try await sendAndWait("get lon")
            if case .longitude(let lon) = CLIResponse.parse(response, forQuery: "get lon") {
                self.longitude = lon
                self.originalLongitude = lon
                logger.debug("Received longitude: \(lon)")
            }
        } catch {
            logger.warning("Failed to get longitude: \(error)")
        }

        // Only show error if no data was received
        if !identityLoaded {
            identityError = "Failed to load identity settings"
        }

        isLoadingIdentity = false
    }

    /// Fetch radio settings (frequency, bandwidth, SF, CR, TX power)
    func fetchRadioSettings() async {
        isLoadingRadio = true
        radioError = nil

        // Get radio parameters
        do {
            let response = try await sendAndWait("get radio")
            if case .radio(let freq, let bw, let sf, let cr) = CLIResponse.parse(response, forQuery: "get radio") {
                self.frequency = freq
                self.bandwidth = bw
                self.spreadingFactor = sf
                self.codingRate = cr
                logger.debug("Received radio: \(freq),\(bw),\(sf),\(cr)")
            }
        } catch {
            logger.warning("Failed to get radio settings: \(error)")
        }

        // Get TX power
        do {
            let response = try await sendAndWait("get tx")
            if case .txPower(let power) = CLIResponse.parse(response, forQuery: "get tx") {
                self.txPower = power
                logger.debug("Received TX power: \(power)")
            }
        } catch {
            logger.warning("Failed to get TX power: \(error)")
        }

        // Only show error if no data was received
        if !radioLoaded {
            radioError = "Failed to load radio settings"
        }

        isLoadingRadio = false
    }

    /// Fetch behavior settings (repeat mode, advert intervals, flood max)
    func fetchBehaviorSettings() async {
        isLoadingBehavior = true
        behaviorError = nil

        // Get repeat mode
        do {
            let response = try await sendAndWait("get repeat")
            if case .repeatMode(let enabled) = CLIResponse.parse(response, forQuery: "get repeat") {
                self.repeaterEnabled = enabled
                self.originalRepeaterEnabled = enabled
                logger.debug("Received repeat mode: \(enabled)")
            }
        } catch {
            logger.warning("Failed to get repeat mode: \(error)")
        }

        // Get advert interval
        do {
            let response = try await sendAndWait("get advert.interval")
            if case .advertInterval(let minutes) = CLIResponse.parse(response, forQuery: "get advert.interval") {
                self.advertIntervalMinutes = minutes
                self.originalAdvertIntervalMinutes = minutes
                logger.debug("Received advert interval: \(minutes)")
            }
        } catch {
            logger.warning("Failed to get advert interval: \(error)")
        }

        // Get flood advert interval
        do {
            let response = try await sendAndWait("get flood.advert.interval")
            if case .floodAdvertInterval(let hours) = CLIResponse.parse(response, forQuery: "get flood.advert.interval") {
                self.floodAdvertIntervalHours = hours
                self.originalFloodAdvertIntervalHours = hours
                logger.debug("Received flood advert interval: \(hours) hours")
            }
        } catch {
            logger.warning("Failed to get flood advert interval: \(error)")
        }

        // Get flood max
        do {
            let response = try await sendAndWait("get flood.max")
            if case .floodMax(let hops) = CLIResponse.parse(response, forQuery: "get flood.max") {
                self.floodMaxHops = hops
                self.originalFloodMaxHops = hops
                logger.debug("Received flood max: \(hops)")
            }
        } catch {
            logger.warning("Failed to get flood max: \(error)")
        }

        // Only show error if no data was received
        if !behaviorLoaded {
            behaviorError = "Failed to load behavior settings"
        }

        isLoadingBehavior = false
    }

    // MARK: - CLI Response Handling

    /// Handle CLI response from push notification
    /// Yields to the waiting stream (does not finish - sendAndWait handles that)
    func handleCLIResponse(_ message: ContactMessage, from contact: ContactDTO) {
        // Verify response is for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              contact.publicKeyPrefix == expectedPrefix else {
            return
        }

        // Yield to waiting stream (don't finish - let sendAndWait validate and decide)
        if let continuation = responseStreamContinuation {
            continuation.yield(message.text)
        } else {
            logger.debug("Response with no waiting command: \(message.text.prefix(50))")
        }
    }

    /// Register for CLI responses (called from view's .task modifier)
    func registerHandlers(appState: AppState) async {
        guard let repeaterAdminService = appState.services?.repeaterAdminService else { return }
        await repeaterAdminService.setCLIHandler { [weak self] frame, contact in
            await MainActor.run {
                self?.handleCLIResponse(frame, from: contact)
            }
        }
    }

    // MARK: - Settings Actions

    /// Apply all radio settings including TX power (requires restart)
    func applyRadioSettings() async {
        guard let frequency, let bandwidth, let spreadingFactor, let codingRate, let txPower else {
            errorMessage = "Radio settings not loaded"
            return
        }

        isApplying = true
        errorMessage = nil

        do {
            var allSucceeded = true

            let radioCommand = "set radio \(frequency),\(bandwidth),\(spreadingFactor),\(codingRate)"
            let radioResponse = try await sendAndWait(radioCommand)
            if case .ok = CLIResponse.parse(radioResponse) {
                // Radio params accepted
            } else {
                allSucceeded = false
            }

            let txCommand = "set tx \(txPower)"
            let txResponse = try await sendAndWait(txCommand)
            if case .ok = CLIResponse.parse(txResponse) {
                // TX power accepted
            } else {
                allSucceeded = false
            }

            if allSucceeded {
                radioSettingsModified = false
                successMessage = "Radio settings applied. Restart device to take effect."
                showSuccessAlert = true
            } else {
                errorMessage = "Some radio settings failed to apply"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    /// Apply only changed identity settings (name, latitude, longitude)
    func applyIdentitySettings() async {
        isApplying = true
        errorMessage = nil

        do {
            var allSucceeded = true

            if let name, name != originalName {
                let response = try await sendAndWait("set name \(name)")
                if case .ok = CLIResponse.parse(response) {
                    originalName = name
                } else {
                    allSucceeded = false
                }
            }

            if let latitude, latitude != originalLatitude {
                let response = try await sendAndWait("set lat \(latitude)")
                if case .ok = CLIResponse.parse(response) {
                    originalLatitude = latitude
                } else {
                    allSucceeded = false
                }
            }

            if let longitude, longitude != originalLongitude {
                let response = try await sendAndWait("set lon \(longitude)")
                if case .ok = CLIResponse.parse(response) {
                    originalLongitude = longitude
                } else {
                    allSucceeded = false
                }
            }

            if allSucceeded {
                withAnimation {
                    isApplying = false
                    identityApplySuccess = true
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { identityApplySuccess = false }
                return
            } else {
                errorMessage = "Some settings failed to apply"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    /// Apply only changed behavior settings (repeat mode, intervals, flood max)
    func applyBehaviorSettings() async {
        // Clear previous validation errors
        advertIntervalError = nil
        floodAdvertIntervalError = nil
        floodMaxHopsError = nil

        // Validate 0-hop interval: accepts 0 (disabled) or 60-240
        if let interval = advertIntervalMinutes {
            if interval != 0 && (interval < 60 || interval > 240) {
                advertIntervalError = "Accepts 0 (disabled) or 60-240 min"
            }
        }

        // Validate flood interval: accepts 3-48
        if let interval = floodAdvertIntervalHours {
            if interval < 3 || interval > 48 {
                floodAdvertIntervalError = "Accepts 3-48 hours"
            }
        }

        // Validate flood max hops: accepts 0-64
        if let hops = floodMaxHops {
            if hops < 0 || hops > 64 {
                floodMaxHopsError = "Accepts 0-64 hops"
            }
        }

        // Don't proceed if validation failed
        if advertIntervalError != nil || floodAdvertIntervalError != nil || floodMaxHopsError != nil {
            return
        }

        isApplying = true
        errorMessage = nil

        do {
            var allSucceeded = true

            if let repeaterEnabled, repeaterEnabled != originalRepeaterEnabled {
                let response = try await sendAndWait("set repeat \(repeaterEnabled ? "on" : "off")")
                if case .ok = CLIResponse.parse(response) {
                    originalRepeaterEnabled = repeaterEnabled
                } else {
                    allSucceeded = false
                }
            }

            if let advertIntervalMinutes, advertIntervalMinutes != originalAdvertIntervalMinutes {
                let response = try await sendAndWait("set advert.interval \(advertIntervalMinutes)")
                if case .ok = CLIResponse.parse(response) {
                    originalAdvertIntervalMinutes = advertIntervalMinutes
                } else {
                    allSucceeded = false
                }
            }

            if let floodAdvertIntervalHours, floodAdvertIntervalHours != originalFloodAdvertIntervalHours {
                let response = try await sendAndWait("set flood.advert.interval \(floodAdvertIntervalHours)")
                if case .ok = CLIResponse.parse(response) {
                    originalFloodAdvertIntervalHours = floodAdvertIntervalHours
                } else {
                    allSucceeded = false
                }
            }

            if let floodMaxHops, floodMaxHops != originalFloodMaxHops {
                let response = try await sendAndWait("set flood.max \(floodMaxHops)")
                if case .ok = CLIResponse.parse(response) {
                    originalFloodMaxHops = floodMaxHops
                } else {
                    allSucceeded = false
                }
            }

            if allSucceeded {
                withAnimation {
                    isApplying = false
                    behaviorApplySuccess = true
                }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { behaviorApplySuccess = false }
                return
            } else {
                errorMessage = "Some settings failed to apply"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    // MARK: - Location Picker Support

    /// Update location from map picker (triggers modified detection via computed property)
    func setLocationFromPicker(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Change admin password (requires explicit action due to security)
    func changePassword() async {
        guard !newPassword.isEmpty else {
            errorMessage = "Password cannot be empty"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        isApplying = true
        errorMessage = nil

        do {
            let response = try await sendAndWait("password \(newPassword)")
            if case .ok = CLIResponse.parse(response) {
                successMessage = "Password changed successfully"
                showSuccessAlert = true
                newPassword = ""
                confirmPassword = ""
            } else {
                errorMessage = "Failed to change password"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    // MARK: - Device Actions

    /// Reboot the repeater
    func reboot() async {
        guard let session, let service = repeaterAdminService else { return }

        isRebooting = true
        errorMessage = nil

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "reboot")
            successMessage = "Reboot command sent"
            showSuccessAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRebooting = false
    }

    /// Force advertisement
    func forceAdvert() async {
        guard let session, let service = repeaterAdminService else { return }

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "advert")
            successMessage = "Advertisement sent"
            showSuccessAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sync repeater time with phone time
    func syncTime() async {
        isApplying = true
        errorMessage = nil

        do {
            let response = try await sendAndWait("clock sync")
            switch CLIResponse.parse(response) {
            case .ok:
                successMessage = "Time synced"
                showSuccessAlert = true
            case .error(let message):
                // Extract message after "ERR: " prefix if present
                if message.contains("clock cannot go backwards") {
                    errorMessage = "Repeater clock is ahead of phone time. If it's too far forward, reboot the repeater then sync time again."
                } else {
                    let cleanMessage = message.replacing("ERR: ", with: "")
                    errorMessage = cleanMessage.isEmpty ? "Failed to sync time" : cleanMessage
                }
                showErrorAlert = true
            default:
                errorMessage = "Unexpected response: \(response)"
                showErrorAlert = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        isApplying = false
    }
}

// MARK: - Error Types

enum RepeaterSettingsError: LocalizedError {
    case notConnected
    case timeout
    case noService

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to repeater"
        case .timeout: return "Command timed out"
        case .noService: return "Repeater service not available"
        }
    }
}
