import Foundation

/// A contact stored on the MeshCore device.
///
/// `MeshContact` represents a node in the mesh network that your device knows about.
/// Contacts are discovered through advertisements and can be used as message destinations.
///
/// ## Properties
///
/// - **Identity**: Each contact has a unique 32-byte public key. The ``id`` property
///   is the hex string representation for use with SwiftUI's `Identifiable`.
///
/// - **Path**: The ``outPath`` and ``outPathLength`` describe the routing path to reach
///   this contact. A path length of -1 indicates flood routing (broadcast to all).
///
/// - **Location**: If the contact shares its location, ``latitude`` and ``longitude``
///   contain GPS coordinates.
///
/// ## Usage
///
/// ```swift
/// // Get contacts from the session
/// let contacts = try await session.getContacts()
///
/// // Find a contact by name
/// if let contact = session.getContactByName("MyNode") {
///     try await session.sendMessage(to: contact.publicKey, text: "Hello!")
/// }
///
/// // Check routing mode
/// if contact.isFloodPath {
///     print("\(contact.advertisedName) uses flood routing")
/// }
/// ```
public struct MeshContact: Sendable, Identifiable, Equatable {
    /// Unique identifier (hex string of public key).
    public let id: String

    /// The contact's 32-byte public key.
    public let publicKey: Data

    /// Contact type identifier.
    public let type: UInt8

    /// Contact flags.
    public let flags: UInt8

    /// Length of the outbound routing path (-1 for flood routing).
    public let outPathLength: Int8

    /// Outbound routing path data.
    public let outPath: Data

    /// The name this contact advertises on the network.
    public let advertisedName: String

    /// When this contact last sent an advertisement.
    public let lastAdvertisement: Date

    /// Latitude coordinate, if location is shared.
    public let latitude: Double

    /// Longitude coordinate, if location is shared.
    public let longitude: Double

    /// When this contact record was last modified.
    public let lastModified: Date

    /// The first 6 bytes of the public key as a hex string.
    ///
    /// This prefix is commonly used for display and as a message destination.
    public var publicKeyPrefix: String {
        publicKey.prefix(6).hexString
    }

    /// Whether this contact uses flood (broadcast) routing.
    ///
    /// Flood routing sends messages to all nodes in the network, useful when
    /// no direct path is known. Path length -1 indicates flood routing.
    public var isFloodPath: Bool {
        outPathLength == -1
    }

    public init(
        id: String,
        publicKey: Data,
        type: UInt8,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        advertisedName: String,
        lastAdvertisement: Date,
        latitude: Double,
        longitude: Double,
        lastModified: Date
    ) {
        self.id = id
        self.publicKey = publicKey
        self.type = type
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.advertisedName = advertisedName
        self.lastAdvertisement = lastAdvertisement
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
    }
}
