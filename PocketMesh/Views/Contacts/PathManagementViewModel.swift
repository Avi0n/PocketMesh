import SwiftUI
import PocketMeshServices
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "PathManagement")

/// Represents a single hop in the routing path with stable identity for SwiftUI
struct PathHop: Identifiable, Equatable {
    let id = UUID()
    var hashByte: UInt8
    var resolvedName: String?  // Contact name if resolved, nil if unknown

    var displayText: String {
        if let name = resolvedName {
            return "\(name) (\(String(format: "%02X", hashByte)))"
        }
        return String(format: "%02X", hashByte)
    }
}

/// Result of a path discovery operation
enum PathDiscoveryResult: Equatable {
    case success(hopCount: Int, fromCache: Bool = false)
    case noPathFound
    case failed(String)

    var description: String {
        switch self {
        case .success(let hopCount, let fromCache):
            let pathType: String
            if hopCount == 0 {
                pathType = L10n.Contacts.Contacts.PathDiscovery.direct
            } else if hopCount == 1 {
                pathType = L10n.Contacts.Contacts.PathDiscovery.Hops.singular
            } else {
                pathType = L10n.Contacts.Contacts.PathDiscovery.Hops.plural(hopCount)
            }
            let source = fromCache ? L10n.Contacts.Contacts.PathDiscovery.cachedSuffix : ""
            return "\(pathType)\(source)"
        case .noPathFound:
            return L10n.Contacts.Contacts.PathDiscovery.noResponse
        case .failed(let message):
            return L10n.Contacts.Contacts.PathDiscovery.failed(message)
        }
    }
}

@MainActor @Observable
final class PathManagementViewModel {

    // MARK: - State

    var isDiscovering = false
    var isSettingPath = false
    var discoveryResult: PathDiscoveryResult?
    var showDiscoveryResult = false
    var errorMessage: String?
    var showError = false

    // Path editing state
    var showingPathEditor = false
    var editablePath: [PathHop] = []  // Current path being edited (stable identifiers)
    var availableRepeaters: [ContactDTO] = []  // Known repeaters to add
    var allContacts: [ContactDTO] = []  // All contacts for name resolution

    /// Repeaters available to add (allows duplicates for paths like A → B → A)
    var filteredAvailableRepeaters: [ContactDTO] {
        availableRepeaters
    }

    // Discovery cancellation
    private var discoveryTask: Task<Void, Never>?

    // Discovery countdown state
    var discoverySecondsRemaining: Int?
    private var countdownTask: Task<Void, Never>?
    private var discoveryStartTime: Date?
    private var discoveryTimeoutSeconds: Double?

    // MARK: - Dependencies

    private var appState: AppState?

    // MARK: - Callbacks

    /// Called when path discovery completes and contact should be refreshed
    var onContactNeedsRefresh: (() -> Void)?

    // MARK: - Configuration

    func configure(appState: AppState, onContactNeedsRefresh: @escaping () -> Void) {
        self.appState = appState
        self.onContactNeedsRefresh = onContactNeedsRefresh
    }

    // MARK: - Name Resolution

    /// Resolve a path hash byte to a contact name if possible
    /// Returns the contact name if exactly one contact matches, otherwise nil
    func resolveHashToName(_ hashByte: UInt8) -> String? {
        let matches = allContacts.filter { $0.publicKey.first == hashByte }
        if matches.count == 1 {
            return matches[0].displayName
        }
        return nil  // Ambiguous (multiple matches) or unknown
    }

    /// Create a PathHop from a hash byte, resolving the name if possible
    func createPathHop(from hashByte: UInt8) -> PathHop {
        PathHop(hashByte: hashByte, resolvedName: resolveHashToName(hashByte))
    }

    /// Load all contacts for name resolution and filter repeaters for adding
    /// Skips fetch if contacts are already loaded for the same device
    func loadContacts(deviceID: UUID, forceReload: Bool = false) async {
        guard let appState,
              let dataStore = appState.services?.dataStore else { return }

        // Skip if already loaded
        if !forceReload && !allContacts.isEmpty {
            return
        }

        do {
            let contacts = try await dataStore.fetchContacts(deviceID: deviceID)
            allContacts = contacts
            availableRepeaters = contacts.filter { $0.type == .repeater }
        } catch {
            allContacts = []
            availableRepeaters = []
        }
    }

    /// Initialize editable path from contact's current path with name resolution
    func initializeEditablePath(from contact: ContactDTO) {
        let pathLength = Int(max(0, contact.outPathLength))
        let pathBytes = Array(contact.outPath.prefix(pathLength))
        editablePath = pathBytes.map { createPathHop(from: $0) }
    }

    /// Add a repeater to the path using its public key's first byte
    func addRepeater(_ repeater: ContactDTO) {
        let hashByte = repeater.publicKey[0]
        let hop = PathHop(hashByte: hashByte, resolvedName: repeater.displayName)
        editablePath.append(hop)
    }

    /// Remove a repeater from the path at index
    func removeRepeater(at index: Int) {
        guard editablePath.indices.contains(index) else { return }
        editablePath.remove(at: index)
    }

    /// Move a repeater within the path
    func moveRepeater(from source: IndexSet, to destination: Int) {
        editablePath.move(fromOffsets: source, toOffset: destination)
    }

    /// Save the edited path to the contact
    func saveEditedPath(for contact: ContactDTO) async {
        guard let appState,
              let contactService = appState.services?.contactService else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            let pathData = Data(editablePath.map { $0.hashByte })
            try await contactService.setPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                path: pathData,
                pathLength: Int8(editablePath.count)
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = L10n.Contacts.Contacts.PathManagement.Error.saveFailed(error.localizedDescription)
            showError = true
        }

        isSettingPath = false
    }

    // MARK: - Path Operations

    /// Initiate path discovery for a contact (with cancel support)
    /// Uses two-tier approach:
    /// 1. First perform active discovery to get fresh path (requires remote response)
    /// 2. If timeout, fall back to cached advertisement path
    func discoverPath(for contact: ContactDTO) async {
        guard let appState,
              let contactService = appState.services?.contactService else { return }

        // Cancel any existing discovery
        discoveryTask?.cancel()

        isDiscovering = true
        discoveryResult = nil
        errorMessage = nil

        // Tier 1: Perform active path discovery (requires remote node response)
        discoveryTask = Task { @MainActor in
            do {
                let sentResponse = try await contactService.sendPathDiscovery(
                    deviceID: contact.deviceID,
                    publicKey: contact.publicKey
                )

                // Calculate timeout from firmware's suggested value
                // MeshCore uses suggested_timeout/600 which gives ~1.67× the raw ms-to-seconds conversion
                // This accounts for network variability in mesh routing
                let timeoutSeconds = Double(sentResponse.suggestedTimeoutMs) / 600.0
                logger.info("Path discovery timeout: \(Int(timeoutSeconds))s (firmware suggested: \(sentResponse.suggestedTimeoutMs)ms)")

                // Start countdown timer
                self.discoveryTimeoutSeconds = timeoutSeconds
                self.discoveryStartTime = Date.now
                self.discoverySecondsRemaining = Int(timeoutSeconds)
                self.startCountdownTask()

                // Wait for push notification with firmware-suggested timeout
                // The AdvertisementService handler will call handleDiscoveryResponse()
                // which cancels this task early if a response arrives
                try await Task.sleep(for: .seconds(timeoutSeconds))

                if !Task.isCancelled {
                    // Timeout - remote node did not respond
                    // Tier 2: Fall back to cached advertisement path
                    await fallbackToCachedPath(for: contact)
                }
            } catch is CancellationError {
                // User cancelled or response received - no feedback needed
            } catch {
                discoveryResult = .failed(error.localizedDescription)
                showDiscoveryResult = true
            }

            isDiscovering = false
            cleanupCountdownState()
        }
    }

    /// Handle timeout when active discovery doesn't receive a response
    private func fallbackToCachedPath(for contact: ContactDTO) async {
        // Active discovery timed out - remote node did not respond
        discoveryResult = .noPathFound
        showDiscoveryResult = true
    }

    /// Start the countdown task that updates remaining seconds every 5 seconds
    private func startCountdownTask() {
        countdownTask = Task {
            while !Task.isCancelled, let timeout = discoveryTimeoutSeconds, let startTime = discoveryStartTime {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }

                let elapsed = Date.now.timeIntervalSince(startTime)
                let remaining = max(0, Int(timeout - elapsed))
                discoverySecondsRemaining = remaining
            }
        }
    }

    /// Clean up countdown state when discovery ends
    private func cleanupCountdownState() {
        countdownTask?.cancel()
        countdownTask = nil
        discoverySecondsRemaining = nil
        discoveryStartTime = nil
        discoveryTimeoutSeconds = nil
    }

    /// Cancel an in-progress path discovery
    func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isDiscovering = false
        cleanupCountdownState()
    }

    /// Called when a path discovery response is received via push notification
    func handleDiscoveryResponse(hopCount: Int) {
        discoveryTask?.cancel()
        isDiscovering = false
        cleanupCountdownState()

        // hopCount == 0 means direct path (zero hops via repeaters)
        // hopCount > 0 means routed path through repeaters
        // Both are successful discoveries
        discoveryResult = .success(hopCount: hopCount, fromCache: false)
        showDiscoveryResult = true

        // Signal that contact data should be refreshed to show new path
        onContactNeedsRefresh?()
    }

    /// Reset the path for a contact (force flood routing)
    func resetPath(for contact: ContactDTO) async {
        guard let appState,
              let contactService = appState.services?.contactService else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            try await contactService.resetPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = L10n.Contacts.Contacts.PathManagement.Error.resetFailed(error.localizedDescription)
            showError = true
        }

        isSettingPath = false
    }

    /// Set a specific path for a contact
    func setPath(for contact: ContactDTO, path: Data, pathLength: Int8) async {
        guard let appState,
              let contactService = appState.services?.contactService else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            try await contactService.setPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                path: path,
                pathLength: pathLength
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = L10n.Contacts.Contacts.PathManagement.Error.setFailed(error.localizedDescription)
            showError = true
        }

        isSettingPath = false
    }
}
