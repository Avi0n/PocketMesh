import SwiftUI
import PocketMeshKit

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
            let pathType = hopCount == 0 ? "Direct" : "\(hopCount) hop\(hopCount > 1 ? "s" : "")"
            let source = fromCache ? ". Using cached info from advertisement. Node may have telemetry disabled." : ""
            return "\(pathType)\(source)"
        case .noPathFound:
            return "Remote node did not respond"
        case .failed(let message):
            return "Failed: \(message)"
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

    /// Repeaters available to add (excludes those already in path)
    var filteredAvailableRepeaters: [ContactDTO] {
        let pathHashBytes = Set(editablePath.map { $0.hashByte })
        return availableRepeaters.filter { repeater in
            !pathHashBytes.contains(repeater.publicKey[0])
        }
    }

    // Discovery cancellation
    private var discoveryTask: Task<Void, Never>?

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
    func loadContacts(deviceID: UUID) async {
        guard let appState else { return }
        do {
            let contacts = try await appState.dataStore.fetchContacts(deviceID: deviceID)
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
        guard let appState else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            let pathData = Data(editablePath.map { $0.hashByte })
            try await appState.contactService.setPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                path: pathData,
                pathLength: Int8(editablePath.count)
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = "Save path failed: \(error.localizedDescription)"
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
        guard let appState else { return }

        // Cancel any existing discovery
        discoveryTask?.cancel()

        isDiscovering = true
        discoveryResult = nil
        errorMessage = nil

        // Tier 1: Perform active path discovery (requires remote node response)
        discoveryTask = Task { @MainActor in
            do {
                try await appState.contactService.sendPathDiscovery(
                    deviceID: contact.deviceID,
                    publicKey: contact.publicKey
                )

                // Wait for push notification with timeout
                // 30 seconds allows for large mesh networks with distant nodes
                // The AdvertisementService handler will call handleDiscoveryResponse()
                // which cancels this task early if a response arrives
                try await Task.sleep(for: .seconds(30))

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
        }
    }

    /// Fall back to cached advertisement path when active discovery times out
    private func fallbackToCachedPath(for contact: ContactDTO) async {
        guard let appState else {
            discoveryResult = .noPathFound
            showDiscoveryResult = true
            return
        }

        do {
            if let advertPath = try await appState.contactService.getAdvertPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey
            ) {
                // Found cached path from advertisements
                discoveryResult = .success(hopCount: Int(advertPath.pathLength), fromCache: true)
                showDiscoveryResult = true

                // Update the contact's path in the database if different
                if contact.outPathLength != Int8(advertPath.pathLength) {
                    try? await appState.contactService.setPath(
                        deviceID: contact.deviceID,
                        publicKey: contact.publicKey,
                        path: advertPath.path,
                        pathLength: Int8(advertPath.pathLength)
                    )
                }
                onContactNeedsRefresh?()
                return
            }
        } catch {
            // Failed to query cached path
        }

        // No cached path available either
        discoveryResult = .noPathFound
        showDiscoveryResult = true
    }

    /// Cancel an in-progress path discovery
    func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isDiscovering = false
    }

    /// Called when a path discovery response is received via push notification
    func handleDiscoveryResponse(hopCount: Int) {
        discoveryTask?.cancel()
        isDiscovering = false

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
        guard let appState else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            try await appState.contactService.resetPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = "Reset path failed: \(error.localizedDescription)"
            showError = true
        }

        isSettingPath = false
    }

    /// Set a specific path for a contact
    func setPath(for contact: ContactDTO, path: Data, pathLength: Int8) async {
        guard let appState else { return }

        isSettingPath = true
        errorMessage = nil

        do {
            try await appState.contactService.setPath(
                deviceID: contact.deviceID,
                publicKey: contact.publicKey,
                path: path,
                pathLength: pathLength
            )
            onContactNeedsRefresh?()
        } catch {
            errorMessage = "Set path failed: \(error.localizedDescription)"
            showError = true
        }

        isSettingPath = false
    }
}
