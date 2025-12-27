#if targetEnvironment(simulator)
import Foundation
import MeshCore

/// Mock session for simulator that allows runtime manipulation of contacts.
/// Used to test archiving behavior when device capacity is reached.
public actor SimulatorMeshSession: MeshCoreSessionProtocol {

    // MARK: - Mutable State

    /// Current contacts on the simulated device
    private var _contacts: [MeshContact] = []

    /// Maximum contacts before oldest gets removed
    private var _maxContacts: Int = 100

    // MARK: - Configuration

    /// Set the contacts list
    public func setContacts(_ contacts: [MeshContact]) {
        _contacts = contacts
    }

    /// Get current contacts
    public func currentContacts() -> [MeshContact] {
        _contacts
    }

    /// Set maximum contact capacity
    public func setMaxContacts(_ max: Int) {
        _maxContacts = max
    }

    /// Get maximum contact capacity
    public func maxContacts() -> Int {
        _maxContacts
    }

    // MARK: - MeshCoreSessionProtocol

    public var connectionState: AsyncStream<MeshCore.ConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.finish()
        }
    }

    public func getContacts(since lastModified: Date?) async throws -> [MeshContact] {
        _contacts
    }

    public func addContact(_ contact: MeshContact) async throws {
        // Simulate device capacity behavior - remove oldest when at limit
        if _contacts.count >= _maxContacts {
            _contacts.removeFirst()
        }
        _contacts.append(contact)
    }

    public func removeContact(publicKey: Data) async throws {
        _contacts.removeAll { $0.publicKey == publicKey }
    }

    public func sendMessage(to destination: Data, text: String, timestamp: Date) async throws -> MessageSentInfo {
        MessageSentInfo(type: 0, expectedAck: Data([0x01, 0x02, 0x03, 0x04]), suggestedTimeoutMs: 5000)
    }

    public func sendChannelMessage(channel: UInt8, text: String, timestamp: Date) async throws {
        // No-op for simulator
    }

    public func resetPath(publicKey: Data) async throws {
        // No-op for simulator
    }

    public func sendPathDiscovery(to destination: Data) async throws -> MessageSentInfo {
        MessageSentInfo(type: 0, expectedAck: Data([0x01, 0x02, 0x03, 0x04]), suggestedTimeoutMs: 5000)
    }

    public func shareContact(publicKey: Data) async throws {
        // No-op for simulator
    }

    public func exportContact(publicKey: Data?) async throws -> String {
        "meshcore://contact/simulator"
    }

    public func importContact(cardData: Data) async throws {
        // No-op for simulator
    }

    public func getChannel(index: UInt8) async throws -> ChannelInfo {
        ChannelInfo(index: index, name: "", secret: Data(repeating: 0, count: 16))
    }

    public func setChannel(index: UInt8, name: String, secret: Data) async throws {
        // No-op for simulator
    }
}
#endif
