import Foundation
import SwiftData
import SwiftUI

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
    public var isPending: Bool

    // Relationships
    public var device: Device?

    @Relationship(deleteRule: .cascade, inverse: \Message.contact)
    public var messages: [Message] = []

    public init(
        publicKey: Data,
        name: String,
        type: ContactType = .companion,
        device: Device? = nil,
        isPending: Bool = false,
    ) {
        id = UUID()
        self.publicKey = publicKey
        self.name = name
        self.type = type
        self.device = device
        lastModified = Date()
        isManuallyAdded = false
        self.isPending = isPending
    }
}

public enum ContactType: String, Codable, Sendable {
    case none = "NONE"
    case companion = "COMPANION" // Type 1 - companion/client (was "CHAT")
    case repeater = "REPEATER"
    case room = "ROOM" // Type 3
    case sensor = "SENSOR" // Type 4 - NEW

    public var displayName: String {
        switch self {
        case .none: "Unknown"
        case .companion: "Companion"
        case .repeater: "Repeater"
        case .room: "Room"
        case .sensor: "Sensor"
        }
    }

    public var iconName: String {
        switch self {
        case .none: "questionmark.circle"
        case .companion: "iphone"
        case .repeater: "antenna.radiowaves.left.and.right"
        case .room: "building.2"
        case .sensor: "sensor"
        }
    }

    public var color: Color {
        switch self {
        case .none: .gray
        case .companion: .blue
        case .repeater: .purple
        case .room: .cyan
        case .sensor: .orange
        }
    }
}
