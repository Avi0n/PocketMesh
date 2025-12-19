import Foundation

/// Protocol for MeshCoreSession to enable testability of dependent services.
///
/// This protocol abstracts the core mesh communication operations used by services
/// in the PocketMeshServices layer, allowing them to be tested without a real BLE connection.
///
/// ## Usage
///
/// Services can accept this protocol type for dependency injection:
/// ```swift
/// actor MyService {
///     private let session: any MeshCoreSessionProtocol
///
///     init(session: any MeshCoreSessionProtocol) {
///         self.session = session
///     }
/// }
/// ```
public protocol MeshCoreSessionProtocol: Actor {

    // MARK: - Connection State

    /// Observable connection state stream for UI binding
    var connectionState: AsyncStream<ConnectionState> { get }

    // MARK: - Message Operations (used by MessageService)

    /// Send a direct message to a contact
    /// - Parameters:
    ///   - destination: The recipient's public key (6-byte prefix)
    ///   - text: The message text
    ///   - timestamp: Message timestamp
    /// - Returns: Information about the sent message including ACK code
    func sendMessage(
        to destination: Data,
        text: String,
        timestamp: Date
    ) async throws -> MessageSentInfo

    /// Send a message to a channel
    /// - Parameters:
    ///   - channel: The channel index (0-7)
    ///   - text: The message text
    ///   - timestamp: Message timestamp
    func sendChannelMessage(
        channel: UInt8,
        text: String,
        timestamp: Date
    ) async throws

    // MARK: - Contact Operations (used by ContactService)

    /// Get contacts from the device
    /// - Parameter lastModified: Optional date for incremental sync
    /// - Returns: Array of mesh contacts
    func getContacts(since lastModified: Date?) async throws -> [MeshContact]

    /// Add a contact to the device
    /// - Parameter contact: The contact to add
    func addContact(_ contact: MeshContact) async throws

    /// Remove a contact from the device
    /// - Parameter publicKey: The contact's public key
    func removeContact(publicKey: Data) async throws

    /// Reset the path to a contact (triggers re-discovery)
    /// - Parameter publicKey: The contact's public key
    func resetPath(publicKey: Data) async throws

    /// Send a path discovery request to a contact
    /// - Parameter destination: The contact's public key
    /// - Returns: Information about the sent message
    func sendPathDiscovery(to destination: Data) async throws -> MessageSentInfo

    // MARK: - Channel Operations (used by ChannelService)

    /// Get information about a channel
    /// - Parameter index: The channel index (0-7)
    /// - Returns: Channel information including name and secret
    func getChannel(index: UInt8) async throws -> ChannelInfo

    /// Set a channel's configuration
    /// - Parameters:
    ///   - index: The channel index (0-7)
    ///   - name: The channel name
    ///   - secret: The 16-byte channel secret
    func setChannel(index: UInt8, name: String, secret: Data) async throws
}
