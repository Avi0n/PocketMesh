import Foundation
import MeshCore

/// Protocol for PersistenceStore to enable testability of dependent services.
///
/// This protocol abstracts the SwiftData persistence operations used by services,
/// allowing them to be tested with mock implementations.
///
/// ## Usage
///
/// Services can accept this protocol type for dependency injection:
/// ```swift
/// actor MyService {
///     private let dataStore: any PersistenceStoreProtocol
///
///     init(dataStore: any PersistenceStoreProtocol) {
///         self.dataStore = dataStore
///     }
/// }
/// ```
public protocol PersistenceStoreProtocol: Actor {

    // MARK: - Message Operations

    /// Save a new message
    func saveMessage(_ dto: MessageDTO) async throws

    /// Fetch a message by ID
    func fetchMessage(id: UUID) async throws -> MessageDTO?

    /// Fetch a message by ACK code
    func fetchMessage(ackCode: UInt32) async throws -> MessageDTO?

    /// Fetch messages for a contact
    func fetchMessages(contactID: UUID, limit: Int, offset: Int) async throws -> [MessageDTO]

    /// Fetch messages for a channel
    func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int, offset: Int) async throws -> [MessageDTO]

    /// Update message status
    func updateMessageStatus(id: UUID, status: MessageStatus) async throws

    /// Update message ACK info
    func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws

    /// Update message status by ACK code
    func updateMessageByAckCode(_ ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws

    /// Update message retry status
    func updateMessageRetryStatus(id: UUID, status: MessageStatus, retryAttempt: Int, maxRetryAttempts: Int) async throws

    /// Update heard repeats count
    func updateMessageHeardRepeats(id: UUID, heardRepeats: Int) async throws

    /// Update link preview data for a message
    func updateMessageLinkPreview(
        id: UUID,
        url: String?,
        title: String?,
        imageData: Data?,
        iconData: Data?,
        fetched: Bool
    ) async throws

    // MARK: - Contact Operations

    /// Fetch all confirmed contacts for a device
    func fetchContacts(deviceID: UUID) async throws -> [ContactDTO]

    /// Fetch contacts with recent messages
    func fetchConversations(deviceID: UUID) async throws -> [ContactDTO]

    /// Fetch a contact by ID
    func fetchContact(id: UUID) async throws -> ContactDTO?

    /// Fetch a contact by public key
    func fetchContact(deviceID: UUID, publicKey: Data) async throws -> ContactDTO?

    /// Fetch a contact by public key prefix
    func fetchContact(deviceID: UUID, publicKeyPrefix: Data) async throws -> ContactDTO?

    /// Save or update a contact from a ContactFrame
    @discardableResult
    func saveContact(deviceID: UUID, from frame: ContactFrame) async throws -> UUID

    /// Save or update a contact from DTO
    func saveContact(_ dto: ContactDTO) async throws

    /// Delete a contact
    func deleteContact(id: UUID) async throws

    /// Update contact's last message info (nil clears the date, removing from conversations list)
    func updateContactLastMessage(contactID: UUID, date: Date?) async throws

    /// Increment unread count for a contact
    func incrementUnreadCount(contactID: UUID) async throws

    /// Clear unread count for a contact
    func clearUnreadCount(contactID: UUID) async throws

    /// Delete all messages for a contact
    func deleteMessagesForContact(contactID: UUID) async throws

    /// Fetch discovered (pending) contacts
    func fetchDiscoveredContacts(deviceID: UUID) async throws -> [ContactDTO]

    /// Mark a discovered contact as confirmed
    func confirmContact(id: UUID) async throws

    // MARK: - Channel Operations

    /// Fetch all channels for a device
    func fetchChannels(deviceID: UUID) async throws -> [ChannelDTO]

    /// Fetch a channel by index
    func fetchChannel(deviceID: UUID, index: UInt8) async throws -> ChannelDTO?

    /// Fetch a channel by ID
    func fetchChannel(id: UUID) async throws -> ChannelDTO?

    /// Save or update a channel from ChannelInfo
    @discardableResult
    func saveChannel(deviceID: UUID, from info: ChannelInfo) async throws -> UUID

    /// Save or update a channel from DTO
    func saveChannel(_ dto: ChannelDTO) async throws

    /// Delete a channel
    func deleteChannel(id: UUID) async throws

    /// Update channel's last message info
    func updateChannelLastMessage(channelID: UUID, date: Date) async throws

    /// Increment unread count for a channel
    func incrementChannelUnreadCount(channelID: UUID) async throws

    /// Clear unread count for a channel
    func clearChannelUnreadCount(channelID: UUID) async throws

    // MARK: - Saved Trace Paths

    /// Fetch all saved trace paths for a device
    func fetchSavedTracePaths(deviceID: UUID) async throws -> [SavedTracePathDTO]

    /// Fetch a single saved trace path by ID
    func fetchSavedTracePath(id: UUID) async throws -> SavedTracePathDTO?

    /// Create a new saved trace path
    func createSavedTracePath(deviceID: UUID, name: String, pathBytes: Data, initialRun: TracePathRunDTO?) async throws -> SavedTracePathDTO

    /// Update a saved trace path's name
    func updateSavedTracePathName(id: UUID, name: String) async throws

    /// Delete a saved trace path
    func deleteSavedTracePath(id: UUID) async throws

    /// Append a run to a saved trace path
    func appendTracePathRun(pathID: UUID, run: TracePathRunDTO) async throws

    // MARK: - Heard Repeats

    /// Find a sent channel message matching criteria within a time window
    func findSentChannelMessage(deviceID: UUID, channelIndex: UInt8, timestamp: UInt32, text: String, withinSeconds: Int) async throws -> MessageDTO?

    /// Save a message repeat entry
    func saveMessageRepeat(_ dto: MessageRepeatDTO) async throws

    /// Fetch all repeats for a message
    func fetchMessageRepeats(messageID: UUID) async throws -> [MessageRepeatDTO]

    /// Check if a repeat exists for the given RX log entry
    func messageRepeatExists(rxLogEntryID: UUID) async throws -> Bool

    /// Increment heard repeats count and return new count
    func incrementMessageHeardRepeats(id: UUID) async throws -> Int

    // MARK: - Debug Log Entries

    /// Save a batch of debug log entries
    func saveDebugLogEntries(_ dtos: [DebugLogEntryDTO]) async throws

    /// Fetch debug log entries since a given date
    func fetchDebugLogEntries(since date: Date, limit: Int) async throws -> [DebugLogEntryDTO]

    /// Count all debug log entries
    func countDebugLogEntries() async throws -> Int

    /// Prune debug log entries, keeping only the most recent
    func pruneDebugLogEntries(keepCount: Int) async throws

    /// Clear all debug log entries
    func clearDebugLogEntries() async throws
}
