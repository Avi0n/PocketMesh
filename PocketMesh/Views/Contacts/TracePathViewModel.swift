import Combine
import CoreLocation
import SwiftUI
import UIKit
import MeshCore
import PocketMeshServices
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "TracePath")

/// Represents a single hop in a trace result
struct TraceHop: Identifiable {
    let id = UUID()
    let hashBytes: Data?          // nil for start/end node (local device)
    let resolvedName: String?     // From contacts lookup
    let snr: Double
    let isStartNode: Bool
    let isEndNode: Bool
    let latitude: Double?
    let longitude: Double?

    /// Display string for hash (shows all bytes)
    var hashDisplayString: String? {
        hashBytes?.map { $0.hexString }.joined()
    }

    /// Whether this hop has a valid (non-zero) location.
    /// Uses OR logic to match ContactDTO.hasLocation - if either coordinate is non-zero,
    /// we have some location data. (0,0) is "Null Island" and extremely unlikely.
    var hasLocation: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat != 0 || lon != 0
    }

    /// Map SNR to 0-1 range for cellularbars variableValue
    var signalLevel: Double {
        Self.signalLevel(for: snr)
    }

    var signalColor: Color {
        Self.signalColor(for: snr)
    }

    /// Shared signal level calculation for any SNR value
    static func signalLevel(for snr: Double) -> Double {
        if snr >= 5 { return 1.0 }
        if snr >= -5 { return 0.66 }
        return 0.33
    }

    /// Shared signal color calculation for any SNR value
    static func signalColor(for snr: Double) -> Color {
        if snr >= 5 { return .green }
        if snr >= -5 { return .yellow }
        return .red
    }
}

/// Result of a trace operation
struct TraceResult: Identifiable {
    let id = UUID()
    let hops: [TraceHop]
    let durationMs: Int
    let success: Bool
    let errorMessage: String?
    let tracedPathBytes: [UInt8]  // Path that was actually traced

    /// Comma-separated path string for display/copy
    var tracedPathString: String {
        tracedPathBytes.map { $0.hexString }.joined(separator: ",")
    }

    static func timeout(attemptedPath: [UInt8]) -> TraceResult {
        TraceResult(hops: [], durationMs: 0, success: false,
                    errorMessage: L10n.Contacts.Contacts.Trace.Error.noResponse, tracedPathBytes: attemptedPath)
    }

    static func sendFailed(_ message: String, attemptedPath: [UInt8]) -> TraceResult {
        TraceResult(hops: [], durationMs: 0, success: false,
                    errorMessage: message, tracedPathBytes: attemptedPath)
    }
}

/// Result of parsing and adding repeater codes
struct CodeInputResult {
    var added: [String] = []
    var notFound: [String] = []
    var alreadyInPath: [String] = []
    var invalidFormat: [String] = []

    var hasErrors: Bool {
        !notFound.isEmpty || !alreadyInPath.isEmpty || !invalidFormat.isEmpty
    }

    var errorMessage: String? {
        guard hasErrors else { return nil }

        var parts: [String] = []

        if !invalidFormat.isEmpty {
            parts.append(L10n.Contacts.Contacts.CodeInput.Error.invalidFormat(invalidFormat.joined(separator: ", ")))
        }
        if !notFound.isEmpty {
            parts.append(L10n.Contacts.Contacts.CodeInput.Error.notFound(notFound.joined(separator: ", ")))
        }
        if !alreadyInPath.isEmpty {
            parts.append(L10n.Contacts.Contacts.CodeInput.Error.alreadyInPath(alreadyInPath.joined(separator: ", ")))
        }

        return parts.joined(separator: " · ")
    }
}

@MainActor @Observable
final class TracePathViewModel {

    // MARK: - Path Building State

    var outboundPath: [PathHop] = []
    var availableRepeaters: [ContactDTO] = []
    var autoReturnPath = true
    private var allContacts: [ContactDTO] = []

    // MARK: - Execution State

    var isRunning = false
    var result: TraceResult?
    var resultID: UUID?  // Set to new UUID only on successful trace
    var errorMessage: String?
    var errorAutoClearDelay: Duration = .seconds(4)
    private var errorAutoClearTask: Task<Void, Never>?
    var errorHapticTrigger = 0  // Incremented on each error for haptic feedback

    /// Buffer between consecutive batch traces to avoid network flooding.
    private static let interTraceBufferMs = 500

    // MARK: - Batch Trace State

    var batchEnabled = false {
        didSet {
            if !batchEnabled {
                clearBatchState()
            }
        }
    }
    var batchSize = 5
    var currentTraceIndex = 0
    var completedResults: [TraceResult] = []

    /// Task running the batch loop - stored so cancellation works
    private var batchTask: Task<Void, Never>?

    /// Flag to signal batch loop should stop (since we await in the calling context)
    private var batchCancelled = false

    /// Continuation for awaiting trace response in batch mode
    private var traceContinuation: CheckedContinuation<Void, Never>?

    var isBatchInProgress: Bool {
        batchEnabled && currentTraceIndex > 0 && currentTraceIndex <= batchSize
    }

    var isBatchComplete: Bool {
        batchEnabled && completedResults.count == batchSize
    }

    var successfulResults: [TraceResult] {
        completedResults.filter { $0.success }
    }

    var successCount: Int {
        successfulResults.count
    }

    /// Clear batch execution state
    func clearBatchState() {
        currentTraceIndex = 0
        completedResults = []
    }

    // MARK: - Batch Aggregates

    var averageRTT: Int? {
        let rtts = successfulResults.map(\.durationMs)
        guard !rtts.isEmpty else { return nil }
        return rtts.reduce(0, +) / rtts.count
    }

    var minRTT: Int? {
        successfulResults.map(\.durationMs).min()
    }

    var maxRTT: Int? {
        successfulResults.map(\.durationMs).max()
    }

    /// Returns aggregate stats for a hop at the given index (0 = start node, 1+ = intermediate/end)
    /// Returns nil for start node (index 0) as it has no received SNR
    func hopStats(at index: Int) -> (avg: Double, min: Double, max: Double)? {
        guard index > 0 else { return nil }  // Start node has no SNR

        let snrValues = successfulResults.compactMap { result -> Double? in
            guard index < result.hops.count else { return nil }
            let hop = result.hops[index]
            guard !hop.isStartNode else { return nil }
            return hop.snr
        }

        guard !snrValues.isEmpty else { return nil }

        let avg = snrValues.reduce(0, +) / Double(snrValues.count)
        let min = snrValues.min() ?? 0
        let max = snrValues.max() ?? 0

        return (avg, min, max)
    }

    /// Returns the SNR for a hop from the most recent successful result
    func latestHopSNR(at index: Int) -> Double? {
        guard let latest = successfulResults.last,
              index < latest.hops.count else { return nil }
        return latest.hops[index].snr
    }

    // MARK: - Saved Path State

    var activeSavedPath: SavedTracePathDTO?
    var isRunningSavedPath: Bool { activeSavedPath != nil }
    /// Returns the second-most-recent successful run for comparison display
    var previousRun: TracePathRunDTO? {
        let successfulRuns = activeSavedPath?.runs
            .filter { $0.success }
            .sorted(by: { $0.date > $1.date }) ?? []
        return successfulRuns.count >= 2 ? successfulRuns[1] : nil
    }

    // MARK: - Trace Correlation

    private var pendingTag: UInt32?
    private var pendingDeviceID: UUID?  // Track which device initiated trace
    private var traceStartTime: Date?
    private var traceTask: Task<Void, Never>?

    // MARK: - Path Hash Tracking (for save validation)

    private var pendingPathHash: [UInt8]?
    // resultPathHash removed - now derived from result.tracedPathBytes

    // MARK: - Event Subscription

    private var cancellables = Set<AnyCancellable>()

    /// Start listening for trace responses
    func startListening() {
        NotificationCenter.default.publisher(for: .traceDataReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let traceInfo = notification.userInfo?["traceInfo"] as? TraceInfo else { return }
                let deviceID = notification.userInfo?["deviceID"] as? UUID
                self?.handleTraceResponse(traceInfo, deviceID: deviceID)
            }
            .store(in: &cancellables)
    }

    /// Stop listening for trace responses
    func stopListening() {
        cancellables.removeAll()
    }

    // MARK: - Dependencies

    private var appState: AppState?

    // MARK: - Computed Properties

    /// Full path: outbound + optional mirrored return (minus last hop to avoid duplicate)
    var fullPathBytes: [UInt8] {
        let outbound = outboundPath.map { $0.hashByte }
        guard !outbound.isEmpty else { return [] }

        if autoReturnPath {
            let returnPath = outbound.reversed().dropFirst()
            return outbound + returnPath
        } else {
            return outbound
        }
    }

    /// Comma-separated path string for display/copy
    var fullPathString: String {
        fullPathBytes.map { $0.hexString }.joined(separator: ",")
    }

    /// Can run trace if path has at least one hop and not currently running
    var canRunTraceWhenConnected: Bool {
        !outboundPath.isEmpty && !isRunning
    }

    /// Can save path if result is successful and path hasn't changed since trace ran
    var canSavePath: Bool {
        if batchEnabled {
            guard !completedResults.isEmpty else { return false }
            guard let firstSuccess = successfulResults.first else { return false }
            return fullPathBytes == firstSuccess.tracedPathBytes
        } else {
            guard let result, result.success else { return false }
            return fullPathBytes == result.tracedPathBytes
        }
    }

    // MARK: - Distance Calculation

    /// Total path distance in meters, using a priority cascade:
    /// 1. Full path (including device legs) if device has location
    /// 2. Intermediate repeaters only if device lacks location
    /// 3. Nil if fewer than 2 hops with valid location
    var totalPathDistance: Double? {
        guard let result, result.success else { return nil }
        guard result.hops.count >= 2 else { return nil }

        // Priority 1: Full path including device legs
        if let fullDistance = calculateDistance(for: result.hops) {
            return fullDistance
        }

        // Priority 2: Intermediate repeaters only (device has no location)
        let repeaters = result.hops.filter { !$0.isStartNode && !$0.isEndNode }
        return calculateDistance(for: repeaters)
    }

    /// Calculate total distance for a sequence of hops, or nil if any lacks location
    private func calculateDistance(for hops: [TraceHop]) -> Double? {
        guard hops.count >= 2 else { return nil }

        var totalMeters: Double = 0

        for index in 0..<(hops.count - 1) {
            let current = hops[index]
            let next = hops[index + 1]

            guard current.hasLocation, next.hasLocation,
                  let curLat = current.latitude, let curLon = current.longitude,
                  let nextLat = next.latitude, let nextLon = next.longitude else {
                return nil
            }

            let from = CLLocation(latitude: curLat, longitude: curLon)
            let to = CLLocation(latitude: nextLat, longitude: nextLon)
            totalMeters += from.distance(from: to)
        }

        return totalMeters
    }

    /// Names of intermediate repeaters that lack location data
    var repeatersWithoutLocation: [String] {
        guard let result else { return [] }

        return result.hops
            .filter { !$0.isStartNode && !$0.isEndNode && !$0.hasLocation }
            .map { $0.resolvedName ?? $0.hashDisplayString ?? "Unknown" }
    }

    /// Whether the distance calculation used intermediate-only fallback (device has no location)
    var isDistanceUsingFallback: Bool {
        guard let result, result.success, totalPathDistance != nil else { return false }

        guard let startNode = result.hops.first, let endNode = result.hops.last else { return false }

        // If device nodes lack location, we used the intermediate-only fallback
        return !startNode.hasLocation || !endNode.hasLocation
    }

    // MARK: - Configuration

    func configure(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Error Handling

    func setError(_ message: String) {
        errorAutoClearTask?.cancel()

        errorMessage = message
        errorHapticTrigger += 1

        errorAutoClearTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: errorAutoClearDelay)
            guard !Task.isCancelled else { return }
            errorMessage = nil
        }
    }

    func clearError() {
        errorAutoClearTask?.cancel()
        errorAutoClearTask = nil
        errorMessage = nil
    }

    // MARK: - Hash Resolution

    /// Resolve a hash byte to the best matching repeater name
    func resolveHashToName(_ hashByte: UInt8) -> String? {
        bestRepeaterMatch(for: hashByte)?.displayName
    }

    /// Resolve a hash byte to the best matching repeater location
    func resolveHashToLocation(_ hashByte: UInt8) -> (latitude: Double, longitude: Double)? {
        guard let contact = bestRepeaterMatch(for: hashByte), contact.hasLocation else { return nil }
        return (contact.latitude, contact.longitude)
    }

    private var currentUserLocation: CLLocation? {
        appState?.locationService.currentLocation
    }

    private func bestRepeaterMatch(for hashByte: UInt8) -> ContactDTO? {
        RepeaterResolver.bestMatch(for: hashByte, in: availableRepeaters, userLocation: currentUserLocation)
    }

    // MARK: - Data Loading

    /// Load contacts for name resolution and available repeaters
    func loadContacts(deviceID: UUID) async {
        guard let appState,
              let dataStore = appState.services?.dataStore else { return }
        do {
            let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
            allContacts = contacts
            availableRepeaters = contacts.filter { $0.type == .repeater }
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
            allContacts = []
            availableRepeaters = []
        }
    }

    // MARK: - Path Manipulation

    /// Add a repeater to the outbound path
    func addRepeater(_ repeater: ContactDTO) {
        clearError()
        let hashByte = repeater.publicKey[0]
        let hop = PathHop(hashByte: hashByte, resolvedName: repeater.displayName)
        outboundPath.append(hop)
        activeSavedPath = nil
        pendingPathHash = nil
        result = nil
    }

    /// Parse comma-separated hex codes and add matching repeaters to the path
    func addRepeatersFromCodes(_ input: String) -> CodeInputResult {
        var result = CodeInputResult()

        let codes = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }

        // Deduplicate while preserving order
        var seen = Set<String>()
        let uniqueCodes = codes.filter { seen.insert($0).inserted }

        let existingBytes = Set(outboundPath.map { $0.hashByte })

        for code in uniqueCodes {
            // Validate hex format (exactly 2 hex characters)
            guard code.count == 2,
                  let byte = UInt8(code, radix: 16) else {
                result.invalidFormat.append(code)
                continue
            }

            // Check if already in path
            if existingBytes.contains(byte) {
                result.alreadyInPath.append(code)
                continue
            }

            // Find matching repeater (prefer closer or more recent on collisions)
            if let repeater = bestRepeaterMatch(for: byte) {
                let hop = PathHop(hashByte: byte, resolvedName: repeater.displayName)
                outboundPath.append(hop)
                result.added.append(code)
            } else {
                result.notFound.append(code)
            }
        }

        // Clear saved path reference if we added anything
        if !result.added.isEmpty {
            activeSavedPath = nil
            pendingPathHash = nil
            self.result = nil
            clearError()
        }

        return result
    }

    /// Remove a repeater from the path
    func removeRepeater(at index: Int) {
        clearError()
        guard outboundPath.indices.contains(index) else { return }
        outboundPath.remove(at: index)
        activeSavedPath = nil
        pendingPathHash = nil
        result = nil
    }

    /// Move a repeater within the path
    func moveRepeater(from source: IndexSet, to destination: Int) {
        clearError()
        outboundPath.move(fromOffsets: source, toOffset: destination)
        activeSavedPath = nil
        pendingPathHash = nil
        result = nil
    }

    /// Copy full path string to clipboard
    func copyPathToClipboard() {
        UIPasteboard.general.string = fullPathString
    }

    /// Generate a default name from the path (e.g., "Tower → ... → Ridge")
    func generatePathName() -> String {
        let names = outboundPath.compactMap { $0.resolvedName }
        switch names.count {
        case 0:
            return L10n.Contacts.Contacts.PathName.prefix(String(fullPathString.prefix(8)))
        case 1:
            return names[0]
        case 2:
            return L10n.Contacts.Contacts.PathName.twoEndpoints(names[0], names[1])
        default:
            return L10n.Contacts.Contacts.PathName.multipleEndpoints(names[0], names[names.count - 1])
        }
    }

    /// Extract SNR values from intermediate hops (excluding start and end nodes)
    private func extractHopsSNR(from result: TraceResult) -> [Double] {
        result.hops
            .filter { !$0.isStartNode && !$0.isEndNode }
            .map { $0.snr }
    }

    /// Save the current path with the given name
    /// - Returns: `true` if save succeeded, `false` otherwise
    @discardableResult
    func savePath(name: String) async -> Bool {
        guard let appState,
              let deviceID = appState.connectedDevice?.id,
              let dataStore = appState.services?.dataStore else { return false }

        // For batch mode, save all completed results
        if batchEnabled && !completedResults.isEmpty {
            guard let firstSuccess = successfulResults.first else { return false }

            // Create initial run from first successful result
            let initialRun = TracePathRunDTO(
                id: UUID(),
                date: Date(),
                success: true,
                roundTripMs: firstSuccess.durationMs,
                hopsSNR: extractHopsSNR(from: firstSuccess)
            )

            do {
                let savedPath = try await dataStore.createSavedTracePath(
                    deviceID: deviceID,
                    name: name,
                    pathBytes: Data(firstSuccess.tracedPathBytes),
                    initialRun: initialRun
                )

                // Append remaining results as additional runs
                for (index, batchResult) in completedResults.enumerated() {
                    // Skip the first successful result (already saved as initial)
                    if batchResult.id == firstSuccess.id { continue }

                    let run = TracePathRunDTO(
                        id: UUID(),
                        date: Date().addingTimeInterval(Double(index)),
                        success: batchResult.success,
                        roundTripMs: batchResult.durationMs,
                        hopsSNR: extractHopsSNR(from: batchResult)
                    )
                    try await dataStore.appendTracePathRun(pathID: savedPath.id, run: run)
                }

                // Refresh to get all runs
                if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                    activeSavedPath = updated
                }
                logger.info("Saved batch path: \(name) with \(self.completedResults.count) runs")
                return true
            } catch {
                logger.error("Failed to save batch path: \(error.localizedDescription)")
                return false
            }
        }

        // Single trace mode (original behavior)
        guard let result, result.success else { return false }

        let initialRun = TracePathRunDTO(
            id: UUID(),
            date: Date(),
            success: true,
            roundTripMs: result.durationMs,
            hopsSNR: extractHopsSNR(from: result)
        )

        do {
            let savedPath = try await dataStore.createSavedTracePath(
                deviceID: deviceID,
                name: name,
                pathBytes: Data(result.tracedPathBytes),
                initialRun: initialRun
            )
            activeSavedPath = savedPath
            logger.info("Saved path: \(name)")
            return true
        } catch {
            logger.error("Failed to save path: \(error.localizedDescription)")
            return false
        }
    }

    /// Load a saved path into the builder
    func loadSavedPath(_ savedPath: SavedTracePathDTO) {
        // Clear existing path
        outboundPath.removeAll()
        result = nil
        pendingPathHash = nil

        // Reconstruct outbound path from saved bytes
        // The saved pathBytes contains full path (outbound + return)
        // We need to extract just the outbound portion
        let fullPath = savedPath.pathHashBytes
        guard !fullPath.isEmpty else { return }

        // Outbound is first half (rounded up)
        let outboundCount = (fullPath.count + 1) / 2
        let outboundBytes = Array(fullPath.prefix(outboundCount))

        for hashByte in outboundBytes {
            let name = resolveHashToName(hashByte)
            outboundPath.append(PathHop(hashByte: hashByte, resolvedName: name))
        }

        activeSavedPath = savedPath
        logger.info("Loaded saved path: \(savedPath.name) with \(outboundBytes.count) hops")
    }

    /// Clear the path (resets to empty state)
    func clearPath() {
        clearError()
        activeSavedPath = nil
        outboundPath.removeAll()
        result = nil
        pendingPathHash = nil
    }

    /// Clear active saved path reference if it matches the deleted path
    func handleSavedPathDeleted(id: UUID) {
        guard activeSavedPath?.id == id else { return }
        activeSavedPath = nil
        logger.info("Cleared active saved path reference after deletion")
    }

    /// Find a saved path matching the current path bytes
    /// Returns the most recently used match if multiple exist
    private func findMatchingSavedPath() async -> SavedTracePathDTO? {
        guard let appState,
              let deviceID = appState.connectedDevice?.id,
              let dataStore = appState.services?.dataStore else { return nil }

        let pathBytes = fullPathBytes
        guard !pathBytes.isEmpty else { return nil }

        do {
            let savedPaths = try await dataStore.fetchSavedTracePaths(deviceID: deviceID)
            let matches = savedPaths.filter { $0.pathHashBytes == pathBytes }

            // Return most recently used (by latest run date)
            return matches.max { path1, path2 in
                let date1 = path1.runs.map(\.date).max() ?? .distantPast
                let date2 = path2.runs.map(\.date).max() ?? .distantPast
                return date1 < date2
            }
        } catch {
            logger.error("Failed to fetch saved paths for matching: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Trace Execution

    /// Execute the trace and wait for response
    func runTrace() async {
        guard let appState,
              let session = appState.services?.session,
              !outboundPath.isEmpty else { return }

        // Cancel any pending trace
        traceTask?.cancel()

        // Clear previous results and errors
        resultID = nil
        clearError()

        // Match to saved path if not already running one
        if activeSavedPath == nil {
            if let matchedPath = await findMatchingSavedPath() {
                activeSavedPath = matchedPath
                logger.info("Matched path to saved path: \(matchedPath.name)")
            }
        }

        isRunning = true
        result = nil
        pendingPathHash = fullPathBytes

        // Generate random tag for correlation
        let tag = UInt32.random(in: 0...UInt32.max)
        pendingTag = tag
        pendingDeviceID = appState.connectedDevice?.id  // Capture device
        traceStartTime = Date()

        // Build path data
        let pathData = Data(fullPathBytes)

        // Send trace command
        var timeoutSeconds = 15.0
        do {
            let sentInfo = try await session.sendTrace(
                tag: tag,
                authCode: 0,  // Not used for basic trace
                flags: 0,
                path: pathData
            )
            timeoutSeconds = Double(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2
            logger.info("Sent trace with tag \(tag), path: \(self.fullPathString), timeout: \(timeoutSeconds)s")
        } catch {
            logger.error("Failed to send trace: \(error.localizedDescription)")
            setError(L10n.Contacts.Contacts.Trace.Error.sendFailed)
            pendingPathHash = nil

            // Record failed run for saved paths
            if let savedPath = activeSavedPath,
               let dataStore = appState.services?.dataStore {
                let failedRun = TracePathRunDTO(
                    id: UUID(),
                    date: Date(),
                    success: false,
                    roundTripMs: 0,
                    hopsSNR: []
                )
                Task { @MainActor [weak self] in
                    do {
                        try await dataStore.appendTracePathRun(pathID: savedPath.id, run: failedRun)
                        if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                            self?.activeSavedPath = updated
                        }
                    } catch {
                        logger.error("Failed to record send failure: \(error.localizedDescription)")
                    }
                }
            }

            isRunning = false
            pendingTag = nil
            pendingDeviceID = nil
            return
        }

        // Wait for response with timeout
        traceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))

                // Timeout - no response received
                if !Task.isCancelled && pendingTag == tag {
                    logger.warning("Trace timeout for tag \(tag) after \(timeoutSeconds)s")
                    setError(L10n.Contacts.Contacts.Trace.Error.noResponse)
                    pendingPathHash = nil

                    // Record failed run for saved paths
                    if let savedPath = activeSavedPath,
                       let dataStore = appState.services?.dataStore {
                        let failedRun = TracePathRunDTO(
                            id: UUID(),
                            date: Date(),
                            success: false,
                            roundTripMs: 0,
                            hopsSNR: []
                        )
                        do {
                            try await dataStore.appendTracePathRun(pathID: savedPath.id, run: failedRun)
                            if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                                activeSavedPath = updated
                            }
                        } catch {
                            logger.error("Failed to record timeout: \(error.localizedDescription)")
                        }
                    }

                    isRunning = false
                    pendingTag = nil
                    pendingDeviceID = nil
                }
            } catch {
                // Task cancelled (response received)
            }
        }
    }

    // MARK: - Batch Trace Execution

    /// Execute multiple traces in batch mode
    func runBatchTrace() async {
        guard batchEnabled else {
            await runTrace()
            return
        }

        // Reset batch state before any early returns
        clearBatchState()
        batchCancelled = false
        resultID = nil
        clearError()

        guard let appState,
              let session = appState.services?.session,
              !outboundPath.isEmpty else { return }

        // Match to saved path if not already running one
        if activeSavedPath == nil {
            if let matchedPath = await findMatchingSavedPath() {
                activeSavedPath = matchedPath
                logger.info("Matched path to saved path: \(matchedPath.name)")
            }
        }

        isRunning = true
        result = nil

        // Execute traces sequentially
        for traceIndex in 1...batchSize {
            // Check cancellation BEFORE starting next trace
            if batchCancelled { break }

            currentTraceIndex = traceIndex

            // Run single trace and wait for result
            await executeSingleTrace(session: session, appState: appState)

            // Check if we got a successful result to show the sheet
            if let latestResult = completedResults.last, latestResult.success {
                // First successful result triggers sheet presentation
                if successCount == 1 {
                    result = latestResult
                    resultID = UUID()
                } else {
                    // Update result for subsequent successful traces
                    result = latestResult
                }
            }

            // Small buffer between traces (unless this is the last one)
            if traceIndex < batchSize {
                // Check cancellation BEFORE sleeping
                if batchCancelled { break }
                try? await Task.sleep(for: .milliseconds(Self.interTraceBufferMs))
                // Check cancellation AFTER sleeping
                if batchCancelled { break }
            }
        }

        isRunning = false
        currentTraceIndex = 0

        // If batch completed but all traces failed, show error
        if isBatchComplete && successCount == 0 {
            setError(L10n.Contacts.Contacts.Trace.Error.allFailed(batchSize))
        }
    }

    /// Execute a single trace within a batch, storing result in completedResults
    private func executeSingleTrace(session: MeshCoreSession, appState: AppState) async {
        pendingPathHash = fullPathBytes

        // Generate random tag for correlation
        let tag = UInt32.random(in: 0...UInt32.max)
        pendingTag = tag
        pendingDeviceID = appState.connectedDevice?.id
        traceStartTime = Date()

        let pathData = Data(fullPathBytes)

        var timeoutSeconds = 15.0
        do {
            let sentInfo = try await session.sendTrace(
                tag: tag,
                authCode: 0,
                flags: 0,
                path: pathData
            )
            timeoutSeconds = Double(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2
            logger.info("Sent batch trace \(self.currentTraceIndex)/\(self.batchSize) with tag \(tag), timeout: \(timeoutSeconds)s")
        } catch {
            logger.error("Failed to send trace: \(error.localizedDescription)")
            let failedResult = TraceResult.sendFailed(
                L10n.Contacts.Contacts.Trace.Error.sendFailed,
                attemptedPath: pendingPathHash ?? []
            )
            completedResults.append(failedResult)
            recordFailedRun(appState: appState)
            pendingPathHash = nil
            pendingTag = nil
            return
        }

        // Wait for response with timeout using continuation
        // Store continuation so handleTraceResponse can resume it immediately
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            traceContinuation = continuation

            traceTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(timeoutSeconds))

                    // Timeout - resume continuation if still waiting
                    if traceContinuation != nil && pendingTag == tag {
                        logger.warning("Batch trace timeout for tag \(tag) after \(timeoutSeconds)s")
                        let timeoutResult = TraceResult.timeout(attemptedPath: pendingPathHash ?? [])
                        completedResults.append(timeoutResult)
                        recordFailedRun(appState: appState)
                        pendingPathHash = nil
                        pendingTag = nil

                        // Resume continuation atomically (only if not already resumed by handleTraceResponse)
                        if let continuation = traceContinuation {
                            traceContinuation = nil
                            continuation.resume()
                        }
                    }
                } catch {
                    // Cancelled - handleTraceResponse already resumed continuation
                }
            }
        }
    }

    /// Record a failed run for saved paths
    private func recordFailedRun(appState: AppState) {
        guard let savedPath = activeSavedPath,
              let dataStore = appState.services?.dataStore else { return }

        let failedRun = TracePathRunDTO(
            id: UUID(),
            date: Date(),
            success: false,
            roundTripMs: 0,
            hopsSNR: []
        )

        Task { @MainActor [weak self] in
            do {
                try await dataStore.appendTracePathRun(pathID: savedPath.id, run: failedRun)
                if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                    self?.activeSavedPath = updated
                }
            } catch {
                logger.error("Failed to record run: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel any running batch trace
    func cancelBatchTrace() {
        // Set cancel flag for batch loop
        batchCancelled = true

        // Cancel batch loop Task
        batchTask?.cancel()
        batchTask = nil

        // Cancel current trace timeout task
        traceTask?.cancel()
        traceTask = nil

        // Clear continuation if waiting (prevent leaked continuation)
        if let continuation = traceContinuation {
            traceContinuation = nil
            continuation.resume()
        }

        isRunning = false
        currentTraceIndex = 0
        pendingTag = nil
        pendingDeviceID = nil
        pendingPathHash = nil
    }

    /// Handle trace response from event stream
    func handleTraceResponse(_ traceInfo: TraceInfo, deviceID: UUID?) {
        guard traceInfo.tag == pendingTag else {
            logger.debug("Ignoring trace response with non-matching tag \(traceInfo.tag)")
            return
        }

        // Validate device ID if both are available; skip if either is nil
        if let pending = pendingDeviceID, let received = deviceID, pending != received {
            logger.warning("Ignoring trace response from different device")
            return
        }

        // Cancel timeout
        traceTask?.cancel()
        traceTask = nil

        // Calculate duration
        let durationMs: Int
        if let startTime = traceStartTime {
            durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        } else {
            durationMs = 0
        }

        // Build hops from response using receiver attribution model:
        // Each node's SNR shows what it measured when receiving.
        // This answers "how well did this node receive the signal?"
        var hops: [TraceHop] = []
        let deviceName = appState?.connectedDevice?.nodeName ?? L10n.Contacts.Contacts.Results.Hop.myDevice
        let path = traceInfo.path

        // Resolve device location: GPS first, then device's set location, treat (0,0) as nil
        var deviceLat: Double?
        var deviceLon: Double?
        if let gpsLocation = appState?.locationService.currentLocation {
            deviceLat = gpsLocation.coordinate.latitude
            deviceLon = gpsLocation.coordinate.longitude
        } else if let device = appState?.connectedDevice,
                  device.latitude != 0 || device.longitude != 0 {
            deviceLat = device.latitude
            deviceLon = device.longitude
        }

        // Start node has no SNR (it transmitted first, didn't receive anything)
        hops.append(TraceHop(
            hashBytes: nil,
            resolvedName: deviceName,
            snr: 0,
            isStartNode: true,
            isEndNode: false,
            latitude: deviceLat,
            longitude: deviceLon
        ))

        // Intermediate hops - each shows SNR it measured when receiving
        for node in path where node.hashBytes != nil {
            let resolvedName: String?
            var latitude: Double?
            var longitude: Double?

            if let bytes = node.hashBytes, let firstByte = bytes.first {
                let matchingHop = outboundPath.first(where: { $0.hashByte == firstByte })
                let bestMatch = bestRepeaterMatch(for: firstByte)
                resolvedName = bestMatch?.displayName ?? matchingHop?.resolvedName

                if let bestMatch, bestMatch.hasLocation {
                    latitude = bestMatch.latitude
                    longitude = bestMatch.longitude
                }
            } else {
                resolvedName = nil
            }

            hops.append(TraceHop(
                hashBytes: node.hashBytes,
                resolvedName: resolvedName,
                snr: node.snr,
                isStartNode: false,
                isEndNode: false,
                latitude: latitude,
                longitude: longitude
            ))
        }

        // End node shows SNR it measured when receiving
        let endSnr = path.last?.snr ?? 0
        hops.append(TraceHop(
            hashBytes: nil,
            resolvedName: deviceName,
            snr: endSnr,
            isStartNode: false,
            isEndNode: true,
            latitude: deviceLat,
            longitude: deviceLon
        ))

        result = TraceResult(
            hops: hops,
            durationMs: durationMs,
            success: true,
            errorMessage: nil,
            tracedPathBytes: pendingPathHash ?? []
        )

        // In batch mode, store result and resume continuation
        if batchEnabled, let result {
            completedResults.append(result)
        } else {
            resultID = UUID()
            isRunning = false
        }

        // Resume continuation if waiting (enables immediate batch progression)
        if let continuation = traceContinuation {
            traceContinuation = nil
            traceTask?.cancel()
            continuation.resume()
        }

        pendingPathHash = nil
        pendingTag = nil
        pendingDeviceID = nil
        traceStartTime = nil

        // Auto-append run if this is a saved path
        if let savedPath = activeSavedPath,
           let dataStore = appState?.services?.dataStore {
            let hopsSNR = hops
                .filter { !$0.isStartNode && !$0.isEndNode }
                .map { $0.snr }
            let runDTO = TracePathRunDTO(
                id: UUID(),
                date: Date(),
                success: true,
                roundTripMs: durationMs,
                hopsSNR: hopsSNR
            )

            Task { @MainActor [weak self] in
                do {
                    try await dataStore.appendTracePathRun(pathID: savedPath.id, run: runDTO)
                    // Refresh saved path to get updated runs
                    if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                        self?.activeSavedPath = updated
                    }
                    logger.info("Appended run to saved path")
                } catch {
                    logger.error("Failed to append run: \(error.localizedDescription)")
                }
            }
        }

        logger.info("Trace completed: \(hops.count) hops, \(durationMs)ms")
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Test helper to set pending tag without running a full trace
    func setPendingTagForTesting(_ tag: UInt32) {
        pendingTag = tag
    }

    /// Test helper to set pending device ID
    func setPendingDeviceIDForTesting(_ deviceID: UUID?) {
        pendingDeviceID = deviceID
    }

    /// Test helper to set pending path hash
    func setPendingPathHashForTesting(_ pathHash: [UInt8]?) {
        pendingPathHash = pathHash
    }

    /// Test helper to set contacts for hash resolution
    func setContactsForTesting(_ contacts: [ContactDTO]) {
        allContacts = contacts
        availableRepeaters = contacts.filter { $0.type == .repeater }
    }
    #endif
}
