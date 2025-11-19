import Foundation
import SwiftData

@Model
public final class Contact: Identifiable {

    public var id: UUID
    @Attribute(.unique) public var publicKey: Data // 32 bytes
    public var name: String
    public var type: ContactType
    public var lastAdvertisement: Date?
    public var lastModified: Date

    // Location from advertisement
    public var latitude: Double?
    public var longitude: Double?

    // Path information
    public var outPathLength: UInt8?
    public var outPath: Data? // Up to 64 bytes

    // Flags
    public var isManuallyAdded: Bool

    // Relationships
    public var device: Device?

    @Relationship(deleteRule: .cascade, inverse: \Message.contact)
    public var messages: [Message] = []

    public init(
        publicKey: Data,
        name: String,
        type: ContactType = .chat,
        device: Device? = nil
    ) {
        self.id = UUID()
        self.publicKey = publicKey
        self.name = name
        self.type = type
        self.device = device
        self.lastModified = Date()
        self.isManuallyAdded = false
    }
}

public enum ContactType: String, Codable, Sendable {
    case none = "NONE"
    case chat = "CHAT"
    case repeater = "REPEATER"
    case room = "ROOM"
}

// Extension to convert Data to hex string for display
public extension Data {
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
