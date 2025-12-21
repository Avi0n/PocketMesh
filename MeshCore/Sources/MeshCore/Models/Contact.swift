import Foundation

/// Represents a contact stored on the MeshCore device.
///
/// `MeshContact` defines a node in the mesh network that your device has discovered or stored.
/// Contacts are typically discovered through advertisements and are used as message destinations.
///
/// ## Identity
/// Each contact has a unique 32-byte public key. The ``id`` property
/// is the hex string representation for use with SwiftUI's `Identifiable`.
///
/// ## Routing
/// The ``outPath`` and ``outPathLength`` describe the routing path to reach
/// this contact. A path length of -1 indicates flood routing (broadcast to all).
///
/// ## Location
/// If the contact shares its location, ``latitude`` and ``longitude``
/// contain GPS coordinates.
///
/// ## Usage
/// ```swift
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
    /// The unique identifier for the contact, represented as a hex string of the public key.
    public let id: String

    /// The contact's 32-byte public key.
    public let publicKey: Data

    /// The type identifier for the contact.
    public let type: UInt8

    /// The operational flags for the contact.
    public let flags: UInt8

    /// The length of the outbound routing path, where -1 indicates flood routing.
    public let outPathLength: Int8

    /// The outbound routing path data.
    public let outPath: Data

    /// The name this contact advertises on the network.
    public let advertisedName: String

    /// The date and time when this contact last sent an advertisement.
    public let lastAdvertisement: Date

    /// The latitude coordinate of the contact, if location sharing is enabled.
    public let latitude: Double

    /// The longitude coordinate of the contact, if location sharing is enabled.
    public let longitude: Double

    /// The date and time when this contact record was last modified.
    public let lastModified: Date

    /// Computes the first 6 bytes of the public key as a hex string.
    ///
    /// This prefix is commonly used for UI display and as a compact message destination.
    public var publicKeyPrefix: String {
        publicKey.prefix(6).hexString
    }

    /// Indicates whether this contact uses flood (broadcast) routing.
    ///
    /// Flood routing sends messages to all nodes in the network. This is used when
    /// no direct path is known.
    public var isFloodPath: Bool {
        outPathLength == -1
    }

    /// Initializes a new mesh contact with the specified properties.
    ///
    /// - Parameters:
    ///   - id: Unique hex string identifier.
    ///   - publicKey: The 32-byte public key data.
    ///   - type: Contact type identifier.
    ///   - flags: Operational flags.
    ///   - outPathLength: Length of the outbound path.
    ///   - outPath: Outbound path data.
    ///   - advertisedName: Name advertised by the node.
    ///   - lastAdvertisement: Date of last advertisement.
    ///   - latitude: Latitude coordinate.
    ///   - longitude: Longitude coordinate.
    ///   - lastModified: Date of last record update.
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
