import Combine
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

    /// Display string for hash (shows all bytes)
    var hashDisplayString: String? {
        hashBytes?.map { $0.hexString }.joined()
    }

    var signalLevel: Double {
        // Map SNR to 0-1 range for cellularbars variableValue
        if snr >= 5 { return 1.0 }
        if snr >= -5 { return 0.66 }
        return 0.33
    }

    var signalColor: Color {
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
                    errorMessage: "No response received", tracedPathBytes: attemptedPath)
    }

    static func sendFailed(_ message: String, attemptedPath: [UInt8]) -> TraceResult {
        TraceResult(hops: [], durationMs: 0, success: false,
                    errorMessage: message, tracedPathBytes: attemptedPath)
    }
}

@MainActor @Observable
final class TracePathViewModel {

    // MARK: - Path Building State

    var outboundPath: [PathHop] = []
    var availableRepeaters: [ContactDTO] = []
    private var allContacts: [ContactDTO] = []

    // MARK: - Execution State

    var isRunning = false
    var result: TraceResult?
    var resultID: UUID?  // Set to new UUID only on successful trace
    var errorMessage: String?
    var errorHapticTrigger = 0  // Incremented on each error for haptic feedback
    private var errorClearTask: Task<Void, Never>?

    /// Duration before error auto-clears. Injectable for testing.
    var errorAutoClearDelay: Duration = .seconds(4)

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

    /// Full path: outbound + mirrored return (minus last hop to avoid duplicate)
    var fullPathBytes: [UInt8] {
        let outbound = outboundPath.map { $0.hashByte }
        guard !outbound.isEmpty else { return [] }
        let returnPath = outbound.reversed().dropFirst()
        return outbound + returnPath
    }

    /// Comma-separated path string for display/copy
    var fullPathString: String {
        fullPathBytes.map { $0.hexString }.joined(separator: ",")
    }

    /// Can run trace if path has at least one hop and device connected
    var canRunTrace: Bool {
        !outboundPath.isEmpty && appState?.connectedDevice != nil && !isRunning
    }

    /// Can save path if result is successful and path hasn't changed since trace ran
    var canSavePath: Bool {
        guard let result, result.success else { return false }
        return fullPathBytes == result.tracedPathBytes
    }

    // MARK: - Configuration

    func configure(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Error Handling

    func setError(_ message: String) {
        errorClearTask?.cancel()
        errorMessage = message
        errorHapticTrigger += 1
        errorClearTask = Task { @MainActor in
            try? await Task.sleep(for: errorAutoClearDelay)
            if !Task.isCancelled {
                errorMessage = nil
            }
        }
    }

    func clearError() {
        errorClearTask?.cancel()
        errorMessage = nil
    }

    // MARK: - Name Resolution

    /// Resolve a hash byte to contact name (single match only)
    func resolveHashToName(_ hashByte: UInt8) -> String? {
        let matches = allContacts.filter { $0.publicKey.first == hashByte }
        return matches.count == 1 ? matches[0].displayName : nil
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
    }

    /// Remove a repeater from the path
    func removeRepeater(at index: Int) {
        clearError()
        guard outboundPath.indices.contains(index) else { return }
        outboundPath.remove(at: index)
        activeSavedPath = nil
        pendingPathHash = nil
    }

    /// Move a repeater within the path
    func moveRepeater(from source: IndexSet, to destination: Int) {
        clearError()
        outboundPath.move(fromOffsets: source, toOffset: destination)
        activeSavedPath = nil
        pendingPathHash = nil
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
            return "Path \(fullPathString.prefix(8))"
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) → \(names[1])"
        default:
            return "\(names[0]) → ... → \(names[names.count - 1])"
        }
    }

    /// Save the current path with the given name
    /// - Returns: `true` if save succeeded, `false` otherwise
    @discardableResult
    func savePath(name: String) async -> Bool {
        guard let appState,
              let deviceID = appState.connectedDevice?.id,
              let dataStore = appState.services?.dataStore,
              let result = result, result.success else { return false }

        // Create initial run DTO (filter to intermediate hops only)
        let hopsSNR = result.hops
            .filter { !$0.isStartNode && !$0.isEndNode }
            .map { $0.snr }
        let initialRun = TracePathRunDTO(
            id: UUID(),
            date: Date(),
            success: true,
            roundTripMs: result.durationMs,
            hopsSNR: hopsSNR
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
        do {
            _ = try await session.sendTrace(
                tag: tag,
                authCode: 0,  // Not used for basic trace
                flags: 0,
                path: pathData
            )
            logger.info("Sent trace with tag \(tag), path: \(self.fullPathString)")
        } catch {
            logger.error("Failed to send trace: \(error.localizedDescription)")
            setError("Failed to send trace packet")
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
                Task { @MainActor in
                    do {
                        try await dataStore.appendTracePathRun(pathID: savedPath.id, run: failedRun)
                        if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                            activeSavedPath = updated
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
                try await Task.sleep(for: .seconds(15))

                // Timeout - no response received
                if !Task.isCancelled && pendingTag == tag {
                    logger.warning("Trace timeout for tag \(tag)")
                    setError("No response received")
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

        // Build hops from response using sender attribution model:
        // Each node's SNR shows how well the NEXT hop received its transmission.
        // This answers "how good was this node's outgoing signal?"
        var hops: [TraceHop] = []
        let deviceName = appState?.connectedDevice?.nodeName ?? "My Device"
        let path = traceInfo.path

        // Start node gets SNR from first path node (how first repeater heard our transmission)
        let startSnr = path.first?.snr ?? 0
        hops.append(TraceHop(
            hashBytes: nil,
            resolvedName: deviceName,
            snr: startSnr,
            isStartNode: true,
            isEndNode: false
        ))

        // Intermediate hops - each gets SNR from the NEXT node's measurement
        for (index, node) in path.enumerated() where node.hashBytes != nil {
            let resolvedName: String?
            if let bytes = node.hashBytes, bytes.count == 1 {
                resolvedName = resolveHashToName(bytes[0])
            } else {
                resolvedName = nil  // Multi-byte: no resolution possible
            }

            // Get SNR from next position in path (sender attribution)
            let nextSnr = index + 1 < path.count ? path[index + 1].snr : 0

            hops.append(TraceHop(
                hashBytes: node.hashBytes,
                resolvedName: resolvedName,
                snr: nextSnr,
                isStartNode: false,
                isEndNode: false
            ))
        }

        // End node - no SNR (no next hop to measure our transmission)
        hops.append(TraceHop(
            hashBytes: nil,
            resolvedName: deviceName,
            snr: 0,
            isStartNode: false,
            isEndNode: true
        ))

        result = TraceResult(
            hops: hops,
            durationMs: durationMs,
            success: true,
            errorMessage: nil,
            tracedPathBytes: pendingPathHash ?? []
        )
        resultID = UUID()
        pendingPathHash = nil
        isRunning = false
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

            Task { @MainActor in
                do {
                    try await dataStore.appendTracePathRun(pathID: savedPath.id, run: runDTO)
                    // Refresh saved path to get updated runs
                    if let updated = try await dataStore.fetchSavedTracePath(id: savedPath.id) {
                        activeSavedPath = updated
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
    #endif
}
