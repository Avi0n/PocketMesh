import SwiftUI
import PocketMeshKit
import OSLog

@Observable
@MainActor
final class RepeaterSettingsViewModel {

    // MARK: - Properties

    var session: RemoteNodeSessionDTO?

    // Device info (read-only from ver/clock)
    var firmwareVersion: String?
    var deviceTime: String?
    var isLoadingDeviceInfo = false
    var deviceInfoError: String?
    var deviceInfoLoaded: Bool { firmwareVersion != nil || deviceTime != nil }

    // Identity settings (from get name, get lat, get lon)
    var name: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var isLoadingIdentity = false
    var identityError: String?
    var identityLoaded = false

    // Radio settings (from get radio, get tx)
    var frequency: Double = 915.0  // MHz
    var bandwidth: Double = 250.0  // kHz
    var spreadingFactor: Int = 10
    var codingRate: Int = 5
    var txPower: Int = 20  // dBm
    var isLoadingRadio = false
    var radioError: String?
    var radioLoaded = false

    // Behavior settings (from get repeat, get advert.interval, get flood.max)
    var advertIntervalMinutes: Int = 15
    var floodAdvertIntervalHours: Int = 1
    var floodMaxHops: Int = 3
    var repeaterEnabled: Bool = true
    var isLoadingBehavior = false
    var behaviorError: String?
    var behaviorLoaded = false

    // Password change (no query available)
    var newPassword: String = ""
    var confirmPassword: String = ""

    // Expansion state for DisclosureGroups
    var isDeviceInfoExpanded = true  // Auto-expand Device Info on appear
    var isRadioExpanded = false
    var isIdentityExpanded = false
    var isBehaviorExpanded = false

    // State
    var isApplying = false
    var isRebooting = false
    var errorMessage: String?
    var successMessage: String?
    var showSuccessAlert = false

    /// Track if radio settings have been modified (requires restart)
    var radioSettingsModified = false

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?
    private let logger = Logger(subsystem: "PocketMesh", category: "RepeaterSettings")

    // MARK: - Command Queue

    /// Queue for CLI commands to prevent interleaving while allowing concurrent section requests
    private var commandQueue: [@Sendable () async -> Void] = []
    private var isProcessingQueue = false
    private var processingTask: Task<Void, Never>?

    /// Add a command to the queue and process if idle
    private func enqueue(_ command: @escaping @Sendable () async -> Void) {
        commandQueue.append(command)
        processQueueIfIdle()
    }

    /// Process queued commands serially
    private func processQueueIfIdle() {
        guard !isProcessingQueue, !commandQueue.isEmpty else { return }
        isProcessingQueue = true

        processingTask = Task {
            while !commandQueue.isEmpty && !Task.isCancelled {
                let command = commandQueue.removeFirst()
                await command()
            }
            await MainActor.run {
                self.isProcessingQueue = false
            }
        }
    }

    // MARK: - Cleanup

    /// Cancel all pending tasks when view disappears
    /// Call from .onDisappear to prevent updates to deallocated ViewModel
    func cleanup() {
        processingTask?.cancel()
        processingTask = nil
        for (_, task) in timeoutTasks {
            task.cancel()
        }
        timeoutTasks.removeAll()
        pendingQueries.removeAll()
        applyTasks.values.forEach { $0.cancel() }
        applyTasks.removeAll()
    }

    // MARK: - Debouncing for Immediate Apply

    /// Debounce tasks for immediate apply methods
    private var applyTasks: [String: Task<Void, Never>] = [:]

    /// Debounced apply - cancels previous task if called again within delay
    private func debouncedApply(key: String, delay: Duration = .milliseconds(300), action: @escaping @MainActor () async -> Void) {
        applyTasks[key]?.cancel()
        applyTasks[key] = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    // MARK: - Configuration

    func configure(appState: AppState, session: RemoteNodeSessionDTO) {
        self.repeaterAdminService = appState.repeaterAdminService
        self.session = session
        self.name = session.name
    }

    // MARK: - Pending Query Tracking

    /// Track which queries are in-flight for response correlation
    /// Uses Array (not Set) for deterministic FIFO ordering when correlating responses
    private var pendingQueries: [String] = []

    /// Per-section timeout tasks for clearing stale loading states
    /// Using dictionary allows multiple sections to load concurrently with independent timeouts
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Fetch Methods (Pull-to-Load)

    /// Fetch device info (firmware version and time)
    func fetchDeviceInfo() async {
        guard let session, let service = repeaterAdminService else { return }

        isLoadingDeviceInfo = true
        pendingQueries.append("ver")
        pendingQueries.append("clock")
        deviceInfoError = nil
        startTimeout(for: "deviceInfo")

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "ver")
            _ = try await service.sendCommand(sessionID: session.id, command: "clock")
        } catch {
            logger.error("Failed to query device info: \(error)")
            deviceInfoError = error.localizedDescription
            isLoadingDeviceInfo = false
            pendingQueries.removeAll { $0 == "ver" || $0 == "clock" }
        }
    }

    /// Fetch identity settings (name, latitude, longitude)
    func fetchIdentity() async {
        guard let session, let service = repeaterAdminService else { return }

        isLoadingIdentity = true
        pendingQueries.append("get name")
        pendingQueries.append("get lat")
        pendingQueries.append("get lon")
        identityError = nil
        startTimeout(for: "identity")

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "get name")
            _ = try await service.sendCommand(sessionID: session.id, command: "get lat")
            _ = try await service.sendCommand(sessionID: session.id, command: "get lon")
        } catch {
            logger.error("Failed to query identity: \(error)")
            identityError = error.localizedDescription
            isLoadingIdentity = false
            pendingQueries.removeAll { ["get name", "get lat", "get lon"].contains($0) }
        }
    }

    /// Fetch radio settings (frequency, bandwidth, SF, CR, TX power)
    func fetchRadioSettings() async {
        guard let session, let service = repeaterAdminService else { return }

        isLoadingRadio = true
        pendingQueries.append("get radio")
        pendingQueries.append("get tx")
        radioError = nil
        startTimeout(for: "radio")

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "get radio")
            _ = try await service.sendCommand(sessionID: session.id, command: "get tx")
        } catch {
            logger.error("Failed to query radio settings: \(error)")
            radioError = error.localizedDescription
            isLoadingRadio = false
            pendingQueries.removeAll { $0 == "get radio" || $0 == "get tx" }
        }
    }

    /// Fetch behavior settings (repeat mode, advert intervals, flood max)
    func fetchBehaviorSettings() async {
        guard let session, let service = repeaterAdminService else { return }

        isLoadingBehavior = true
        pendingQueries.append("get repeat")
        pendingQueries.append("get advert.interval")
        pendingQueries.append("get flood.advert.interval")
        pendingQueries.append("get flood.max")
        behaviorError = nil
        startTimeout(for: "behavior")

        do {
            _ = try await service.sendCommand(sessionID: session.id, command: "get repeat")
            _ = try await service.sendCommand(sessionID: session.id, command: "get advert.interval")
            _ = try await service.sendCommand(sessionID: session.id, command: "get flood.advert.interval")
            _ = try await service.sendCommand(sessionID: session.id, command: "get flood.max")
        } catch {
            logger.error("Failed to query behavior settings: \(error)")
            behaviorError = error.localizedDescription
            isLoadingBehavior = false
            pendingQueries.removeAll { ["get repeat", "get advert.interval", "get flood.advert.interval", "get flood.max"].contains($0) }
        }
    }

    /// Start timeout for a section's loading state
    /// Each section has its own independent timeout task
    private func startTimeout(for section: String) {
        // Cancel any existing timeout for this section
        timeoutTasks[section]?.cancel()

        timeoutTasks[section] = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                switch section {
                case "deviceInfo":
                    if isLoadingDeviceInfo {
                        deviceInfoError = "Request timed out"
                        isLoadingDeviceInfo = false
                        pendingQueries.removeAll { $0 == "ver" || $0 == "clock" }
                    }
                case "identity":
                    if isLoadingIdentity {
                        identityError = "Request timed out"
                        isLoadingIdentity = false
                        pendingQueries.removeAll { ["get name", "get lat", "get lon"].contains($0) }
                    }
                case "radio":
                    if isLoadingRadio {
                        radioError = "Request timed out"
                        isLoadingRadio = false
                        pendingQueries.removeAll { $0 == "get radio" || $0 == "get tx" }
                    }
                case "behavior":
                    if isLoadingBehavior {
                        behaviorError = "Request timed out"
                        isLoadingBehavior = false
                        pendingQueries.removeAll { ["get repeat", "get advert.interval", "get flood.advert.interval", "get flood.max"].contains($0) }
                    }
                default:
                    break
                }
                timeoutTasks.removeValue(forKey: section)
            }
        }
    }

    // MARK: - CLI Response Handling

    /// Handle CLI response from push notification
    /// Called by the handler registered in registerHandlers()
    func handleCLIResponse(_ frame: MessageFrame, from contact: ContactDTO) {
        // Verify response is for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              contact.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }

        // Determine which query this response is for based on pending queries
        let queryHint = pendingQueries.first { query in
            // Match response patterns to likely queries
            switch query {
            case "ver": return frame.text.contains("MeshCore") || (frame.text.hasPrefix("v") && frame.text.contains("("))
            case "clock": return frame.text.contains("UTC") || (frame.text.contains(":") && frame.text.contains("/"))
            case "get radio": return frame.text.contains(",") && frame.text.split(separator: ",").count >= 4
            case "get tx": return Int(frame.text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil && !frame.text.contains(",")
            case "get repeat": return frame.text.lowercased().contains("on") || frame.text.lowercased().contains("off")
            case "get advert.interval", "get flood.advert.interval", "get flood.max":
                return Int(frame.text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            case "get name": return !frame.text.contains(",") && !frame.text.contains("UTC") && !frame.text.contains("(")
            case "get lat", "get lon": return Double(frame.text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            default: return false
            }
        }

        let response = CLIResponse.parse(frame.text, forQuery: queryHint)

        switch response {
        case .version(let version):
            self.firmwareVersion = version
            pendingQueries.removeAll { $0 == "ver" }
            checkDeviceInfoComplete()
            logger.debug("Received firmware version: \(version)")

        case .deviceTime(let time):
            self.deviceTime = time
            pendingQueries.removeAll { $0 == "clock" }
            checkDeviceInfoComplete()
            logger.debug("Received device time: \(time)")

        case .name(let name):
            self.name = name
            pendingQueries.removeAll { $0 == "get name" }
            checkIdentityComplete()
            logger.debug("Received name: \(name)")

        case .latitude(let lat):
            self.latitude = lat
            pendingQueries.removeAll { $0 == "get lat" }
            checkIdentityComplete()
            logger.debug("Received latitude: \(lat)")

        case .longitude(let lon):
            self.longitude = lon
            pendingQueries.removeAll { $0 == "get lon" }
            checkIdentityComplete()
            logger.debug("Received longitude: \(lon)")

        case .radio(let freq, let bw, let sf, let cr):
            self.frequency = freq
            self.bandwidth = bw
            self.spreadingFactor = sf
            self.codingRate = cr
            pendingQueries.removeAll { $0 == "get radio" }
            checkRadioComplete()
            logger.debug("Received radio: \(freq),\(bw),\(sf),\(cr)")

        case .txPower(let power):
            self.txPower = power
            pendingQueries.removeAll { $0 == "get tx" }
            checkRadioComplete()
            logger.debug("Received TX power: \(power)")

        case .repeatMode(let enabled):
            self.repeaterEnabled = enabled
            pendingQueries.removeAll { $0 == "get repeat" }
            checkBehaviorComplete()
            logger.debug("Received repeat mode: \(enabled)")

        case .advertInterval(let minutes):
            self.advertIntervalMinutes = minutes
            pendingQueries.removeAll { $0 == "get advert.interval" }
            checkBehaviorComplete()
            logger.debug("Received advert interval: \(minutes)")

        case .floodAdvertInterval(let hours):
            self.floodAdvertIntervalHours = hours
            pendingQueries.removeAll { $0 == "get flood.advert.interval" }
            checkBehaviorComplete()
            logger.debug("Received flood advert interval: \(hours) hours")

        case .floodMax(let hops):
            self.floodMaxHops = hops
            pendingQueries.removeAll { $0 == "get flood.max" }
            checkBehaviorComplete()
            logger.debug("Received flood max: \(hops)")

        case .error(let message):
            handleErrorResponse(message)
            logger.warning("CLI error response: \(message)")

        case .unknownCommand(let message):
            // Handle gracefully - firmware may not support this command
            // Remove the pending query and log, but don't treat as fatal error
            handleUnknownCommand(message)
            logger.info("Unknown command response (firmware may not support): \(message)")

        case .ok:
            // Generic success for set commands - clear first pending set query (FIFO order)
            if let index = pendingQueries.firstIndex(where: { $0.hasPrefix("set ") || $0 == "password" }) {
                pendingQueries.remove(at: index)
            }

        case .raw(let text):
            // Unknown response format - remove first pending query (FIFO order)
            logger.debug("Unrecognized CLI response: \(text)")
            if !pendingQueries.isEmpty {
                pendingQueries.removeFirst()
            }
        }
    }

    private func checkDeviceInfoComplete() {
        if !pendingQueries.contains("ver") && !pendingQueries.contains("clock") {
            isLoadingDeviceInfo = false
            timeoutTasks["deviceInfo"]?.cancel()
            timeoutTasks.removeValue(forKey: "deviceInfo")
        }
    }

    private func checkIdentityComplete() {
        let identityQueries = ["get name", "get lat", "get lon"]
        if identityQueries.allSatisfy({ !pendingQueries.contains($0) }) {
            identityLoaded = true
            isLoadingIdentity = false
            timeoutTasks["identity"]?.cancel()
            timeoutTasks.removeValue(forKey: "identity")
        }
    }

    private func checkRadioComplete() {
        if !pendingQueries.contains("get radio") && !pendingQueries.contains("get tx") {
            radioLoaded = true
            isLoadingRadio = false
            timeoutTasks["radio"]?.cancel()
            timeoutTasks.removeValue(forKey: "radio")
        }
    }

    private func checkBehaviorComplete() {
        let behaviorQueries = ["get repeat", "get advert.interval", "get flood.advert.interval", "get flood.max"]
        if behaviorQueries.allSatisfy({ !pendingQueries.contains($0) }) {
            behaviorLoaded = true
            isLoadingBehavior = false
            timeoutTasks["behavior"]?.cancel()
            timeoutTasks.removeValue(forKey: "behavior")
        }
    }

    private func handleErrorResponse(_ message: String) {
        // Match error to the appropriate section based on pending queries
        if pendingQueries.contains("ver") || pendingQueries.contains("clock") {
            deviceInfoError = message
            pendingQueries.removeAll { $0 == "ver" || $0 == "clock" }
            isLoadingDeviceInfo = false
            timeoutTasks["deviceInfo"]?.cancel()
            timeoutTasks.removeValue(forKey: "deviceInfo")
        } else if pendingQueries.contains("get name") || pendingQueries.contains("get lat") || pendingQueries.contains("get lon") {
            identityError = message
            pendingQueries.removeAll { ["get name", "get lat", "get lon"].contains($0) }
            isLoadingIdentity = false
            timeoutTasks["identity"]?.cancel()
            timeoutTasks.removeValue(forKey: "identity")
        } else if pendingQueries.contains("get radio") || pendingQueries.contains("get tx") {
            radioError = message
            pendingQueries.removeAll { $0 == "get radio" || $0 == "get tx" }
            isLoadingRadio = false
            timeoutTasks["radio"]?.cancel()
            timeoutTasks.removeValue(forKey: "radio")
        } else if pendingQueries.contains(where: { $0.hasPrefix("get ") }) {
            behaviorError = message
            pendingQueries.removeAll { $0.hasPrefix("get ") }
            isLoadingBehavior = false
            timeoutTasks["behavior"]?.cancel()
            timeoutTasks.removeValue(forKey: "behavior")
        }
    }

    /// Handle "unknown command" responses gracefully
    /// Some firmware versions may not support all get commands
    private func handleUnknownCommand(_ message: String) {
        // Remove the first pending query (FIFO order) that might have caused this
        // Don't treat as fatal - just clear the pending query and let section complete
        if !pendingQueries.isEmpty {
            let query = pendingQueries.removeFirst()
            logger.debug("Cleared pending query '\(query)' due to unknown command response")

            // Trigger completion checks - section may still be usable with partial data
            checkDeviceInfoComplete()
            checkIdentityComplete()
            checkRadioComplete()
            checkBehaviorComplete()
        }
    }

    /// Register for CLI responses (called from view's .task modifier)
    func registerHandlers(appState: AppState) async {
        await appState.repeaterAdminService.setCLIHandler { [weak self] frame, contact in
            await MainActor.run {
                self?.handleCLIResponse(frame, from: contact)
            }
        }
    }

    // MARK: - Settings Actions

    /// Apply all radio settings including TX power (requires restart)
    /// This is the only section with an explicit Apply button
    func applyRadioSettings() async {
        guard let session, let service = repeaterAdminService else { return }

        isApplying = true
        errorMessage = nil

        do {
            // Format: set radio {freq},{bw},{sf},{cr}
            let radioCommand = "set radio \(frequency),\(bandwidth),\(spreadingFactor),\(codingRate)"
            _ = try await service.sendCommand(sessionID: session.id, command: radioCommand)

            // Format: set tx {dbm}
            let txCommand = "set tx \(txPower)"
            _ = try await service.sendCommand(sessionID: session.id, command: txCommand)

            radioSettingsModified = false
            successMessage = "Radio settings applied. Restart device to take effect."
            showSuccessAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isApplying = false
    }

    // MARK: - Immediate Apply Methods (debounced, non-restart settings)

    /// Apply name with debouncing to prevent rapid-fire commands
    func applyNameImmediately() {
        guard !name.isEmpty else { return }
        debouncedApply(key: "name") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set name \(self.name)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Name applied: \(self.name)")
            } catch {
                self.logger.error("Failed to apply name: \(error)")
            }
        }
    }

    /// Apply latitude with debouncing
    func applyLatitudeImmediately() {
        debouncedApply(key: "lat") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set lat \(self.latitude)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Latitude applied: \(self.latitude)")
            } catch {
                self.logger.error("Failed to apply latitude: \(error)")
            }
        }
    }

    /// Apply longitude with debouncing
    func applyLongitudeImmediately() {
        debouncedApply(key: "lon") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set lon \(self.longitude)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Longitude applied: \(self.longitude)")
            } catch {
                self.logger.error("Failed to apply longitude: \(error)")
            }
        }
    }

    /// Apply repeater enabled state with debouncing
    func applyRepeaterModeImmediately() {
        debouncedApply(key: "repeat") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set repeat \(self.repeaterEnabled ? "on" : "off")"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Repeater mode applied: \(self.repeaterEnabled)")
            } catch {
                self.logger.error("Failed to apply repeater mode: \(error)")
            }
        }
    }

    /// Apply advert interval with debouncing
    func applyAdvertIntervalImmediately() {
        debouncedApply(key: "advert.interval") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set advert.interval \(self.advertIntervalMinutes)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Advert interval applied: \(self.advertIntervalMinutes)")
            } catch {
                self.logger.error("Failed to apply advert interval: \(error)")
            }
        }
    }

    /// Apply flood advert interval with debouncing
    func applyFloodAdvertIntervalImmediately() {
        debouncedApply(key: "flood.advert.interval") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set flood.advert.interval \(self.floodAdvertIntervalHours)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Flood advert interval applied: \(self.floodAdvertIntervalHours)")
            } catch {
                self.logger.error("Failed to apply flood advert interval: \(error)")
            }
        }
    }

    /// Apply flood max hops with debouncing
    func applyFloodMaxImmediately() {
        debouncedApply(key: "flood.max") { [weak self] in
            guard let self, let session = self.session, let service = self.repeaterAdminService else { return }
            do {
                let command = "set flood.max \(self.floodMaxHops)"
                _ = try await service.sendCommand(sessionID: session.id, command: command)
                self.logger.debug("Flood max applied: \(self.floodMaxHops)")
            } catch {
                self.logger.error("Failed to apply flood max: \(error)")
            }
        }
    }

    /// Change admin password (requires explicit action due to security)
    func changePassword() async {
        guard let session, let service = repeaterAdminService else { return }
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
            let command = "password \(newPassword)"
            _ = try await service.sendCommand(sessionID: session.id, command: command)
            successMessage = "Password changed successfully"
            showSuccessAlert = true
            newPassword = ""
            confirmPassword = ""
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
}
