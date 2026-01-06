import Foundation

/// Defines the interface for MeshCore device communication.
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

    /// Provides an observable connection state stream for UI binding.
    var connectionState: AsyncStream<ConnectionState> { get }

    // MARK: - Message Operations (used by MessageService)

    /// Sends a direct message to a contact.
    ///
    /// - Parameters:
    ///   - destination: The recipient's public key (6-byte prefix).
    ///   - text: The message text to send.
    ///   - timestamp: The timestamp of the message.
    /// - Returns: A `MessageSentInfo` object containing information about the sent message, including the ACK code.
    /// - Throws: `MeshCoreError` if the message fails to send or the device returns an error.
    func sendMessage(
        to destination: Data,
        text: String,
        timestamp: Date
    ) async throws -> MessageSentInfo

    /// Sends a message to a channel.
    ///
    /// - Parameters:
    ///   - channel: The channel index (0-7).
    ///   - text: The message text to send.
    ///   - timestamp: The timestamp of the message.
    /// - Throws: `MeshCoreError` if the channel message fails to send.
    func sendChannelMessage(
        channel: UInt8,
        text: String,
        timestamp: Date
    ) async throws

    // MARK: - Contact Operations (used by ContactService)

    /// Retrieves contacts from the device.
    ///
    /// - Parameter lastModified: An optional date for incremental synchronization.
    /// - Returns: An array of `MeshContact` objects retrieved from the device.
    /// - Throws: `MeshCoreError` if the contact query fails.
    func getContacts(since lastModified: Date?) async throws -> [MeshContact]

    /// Fetches a single contact from the device by public key.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the contact.
    /// - Returns: The contact if found, or `nil` if no contact exists with that key.
    /// - Throws: `MeshCoreError` if the query fails.
    func getContact(publicKey: Data) async throws -> MeshContact?

    /// Adds a contact to the device.
    ///
    /// - Parameter contact: The contact to add to the device's storage.
    /// - Throws: `MeshCoreError` if the contact cannot be added.
    func addContact(_ contact: MeshContact) async throws

    /// Removes a contact from the device.
    ///
    /// - Parameter publicKey: The contact's public key to remove.
    /// - Throws: `MeshCoreError` if the contact cannot be removed.
    func removeContact(publicKey: Data) async throws

    /// Resets the path to a contact.
    ///
    /// Triggers path re-discovery for the specified contact by clearing existing routing info.
    ///
    /// - Parameter publicKey: The contact's public key.
    /// - Throws: `MeshCoreError` if the path reset command fails.
    func resetPath(publicKey: Data) async throws

    /// Sends a path discovery request to a contact.
    ///
    /// - Parameter destination: The contact's public key.
    /// - Returns: A `MessageSentInfo` object containing information about the discovery request.
    /// - Throws: `MeshCoreError` if the discovery request fails.
    func sendPathDiscovery(to destination: Data) async throws -> MessageSentInfo

    // MARK: - Channel Operations (used by ChannelService)

    /// Retrieves information about a channel.
    ///
    /// - Parameter index: The channel index (0-7).
    /// - Returns: A `ChannelInfo` object including the name and secret.
    /// - Throws: `MeshCoreError` if the channel query fails.
    func getChannel(index: UInt8) async throws -> ChannelInfo

    /// Configures a channel's settings.
    ///
    /// - Parameters:
    ///   - index: The channel index (0-7).
    ///   - name: The channel name.
    ///   - secret: The 16-byte channel secret.
    /// - Throws: `MeshCoreError` if the channel configuration fails.
    func setChannel(index: UInt8, name: String, secret: Data) async throws
}
