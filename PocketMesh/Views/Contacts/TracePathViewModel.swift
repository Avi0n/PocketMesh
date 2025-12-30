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
    let hashByte: UInt8?          // nil for start/end node (local device)
    let resolvedName: String?     // From contacts lookup
    let snr: Double
    let isStartNode: Bool
    let isEndNode: Bool

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
struct TraceResult {
    let hops: [TraceHop]
    let durationMs: Int
    let success: Bool
    let errorMessage: String?

    static func timeout() -> TraceResult {
        TraceResult(hops: [], durationMs: 0, success: false, errorMessage: "No response received")
    }

    static func sendFailed(_ message: String) -> TraceResult {
        TraceResult(hops: [], durationMs: 0, success: false, errorMessage: message)
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

    // MARK: - Trace Correlation

    private var pendingTag: UInt32?
    private var traceStartTime: Date?
    private var traceTask: Task<Void, Never>?

    // MARK: - Event Subscription

    private var cancellables = Set<AnyCancellable>()

    /// Start listening for trace responses
    func startListening() {
        NotificationCenter.default.publisher(for: .traceDataReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let traceInfo = notification.userInfo?["traceInfo"] as? TraceInfo else { return }
                self?.handleTraceResponse(traceInfo)
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
        fullPathBytes.map { String(format: "%02X", $0) }.joined(separator: ",")
    }

    /// Can run trace if path has at least one hop and device connected
    var canRunTrace: Bool {
        !outboundPath.isEmpty && appState?.connectedDevice != nil && !isRunning
    }

    // MARK: - Configuration

    func configure(appState: AppState) {
        self.appState = appState
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
        let hashByte = repeater.publicKey[0]
        let hop = PathHop(hashByte: hashByte, resolvedName: repeater.displayName)
        outboundPath.append(hop)
    }

    /// Remove a repeater from the path
    func removeRepeater(at index: Int) {
        guard outboundPath.indices.contains(index) else { return }
        outboundPath.remove(at: index)
    }

    /// Move a repeater within the path
    func moveRepeater(from source: IndexSet, to destination: Int) {
        outboundPath.move(fromOffsets: source, toOffset: destination)
    }

    /// Copy full path string to clipboard
    func copyPathToClipboard() {
        UIPasteboard.general.string = fullPathString
    }

    // MARK: - Trace Execution

    /// Execute the trace and wait for response
    func runTrace() async {
        guard let appState,
              let session = appState.services?.session,
              !outboundPath.isEmpty else { return }

        // Cancel any pending trace
        traceTask?.cancel()

        isRunning = true
        result = nil

        // Generate random tag for correlation
        let tag = UInt32.random(in: 0...UInt32.max)
        pendingTag = tag
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
            result = .sendFailed("Failed to send trace packet")
            isRunning = false
            pendingTag = nil
            return
        }

        // Wait for response with timeout
        traceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(15))

                // Timeout - no response received
                if !Task.isCancelled && pendingTag == tag {
                    logger.warning("Trace timeout for tag \(tag)")
                    result = .timeout()
                    isRunning = false
                    pendingTag = nil
                }
            } catch {
                // Task cancelled (response received)
            }
        }
    }

    /// Handle trace response from event stream
    func handleTraceResponse(_ traceInfo: TraceInfo) {
        guard traceInfo.tag == pendingTag else {
            logger.debug("Ignoring trace response with non-matching tag \(traceInfo.tag)")
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

        // Build hops from response
        var hops: [TraceHop] = []

        // Start node (local device)
        if let firstNode = traceInfo.path.first {
            hops.append(TraceHop(
                hashByte: nil,
                resolvedName: appState?.connectedDevice?.nodeName ?? "My Device",
                snr: firstNode.snr,
                isStartNode: true,
                isEndNode: false
            ))
        }

        // Intermediate hops
        for node in traceInfo.path.dropFirst().dropLast() {
            let hashByte = node.hash
            let resolvedName = hashByte.flatMap { resolveHashToName($0) }
            hops.append(TraceHop(
                hashByte: hashByte,
                resolvedName: resolvedName,
                snr: node.snr,
                isStartNode: false,
                isEndNode: false
            ))
        }

        // End node (response received back)
        if traceInfo.path.count > 1, let lastNode = traceInfo.path.last {
            hops.append(TraceHop(
                hashByte: nil,
                resolvedName: appState?.connectedDevice?.nodeName ?? "My Device",
                snr: lastNode.snr,
                isStartNode: false,
                isEndNode: true
            ))
        }

        result = TraceResult(
            hops: hops,
            durationMs: durationMs,
            success: true,
            errorMessage: nil
        )

        isRunning = false
        pendingTag = nil
        traceStartTime = nil

        logger.info("Trace completed: \(hops.count) hops, \(durationMs)ms")
    }
}
