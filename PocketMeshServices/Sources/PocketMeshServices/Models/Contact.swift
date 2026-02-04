import CoreLocation
import Foundation
import SwiftData

/// Represents a contact discovered on the mesh network.
/// Contacts are stored per-device and synced from the device's contact table.
@Model
public final class Contact {
    /// Unique identifier (derived from public key hash)
    @Attribute(.unique)
    public var id: UUID

    /// The device this contact belongs to
    public var deviceID: UUID

    /// The 32-byte public key of the contact
    public var publicKey: Data

    /// Human-readable name
    public var name: String

    /// Contact type (chat, repeater, room)
    public var typeRawValue: UInt8

    /// Permission flags
    public var flags: UInt8

    /// Outgoing path length (-1 = flood, 0+ = direct)
    public var outPathLength: Int8

    /// Outgoing routing path (up to 64 bytes)
    public var outPath: Data

    /// Last advertisement timestamp (device time)
    public var lastAdvertTimestamp: UInt32

    /// Contact latitude
    public var latitude: Double

    /// Contact longitude
    public var longitude: Double

    /// Last modification timestamp (for sync watermarking)
    public var lastModified: UInt32

    /// Local nickname override (optional)
    public var nickname: String?

    /// Whether this contact is blocked
    public var isBlocked: Bool

    /// Whether this contact's notifications are muted
    public var isMuted: Bool = false

    /// Whether this contact is a favorite/pinned
    public var isFavorite: Bool

    /// Last message timestamp (for sorting conversations)
    public var lastMessageDate: Date?

    /// Unread message count
    public var unreadCount: Int

    /// Unread mention count (mentions of current user not yet seen)
    public var unreadMentionCount: Int = 0

    /// Selected OCV preset name (nil = liIon default)
    public var ocvPreset: String?

    /// Custom OCV array as comma-separated string (e.g., "4240,4112,4029,...")
    public var customOCVArrayString: String?

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        publicKey: Data,
        name: String,
        typeRawValue: UInt8 = 0,
        flags: UInt8 = 0,
        outPathLength: Int8 = -1,
        outPath: Data = Data(),
        lastAdvertTimestamp: UInt32 = 0,
        latitude: Double = 0,
        longitude: Double = 0,
        lastModified: UInt32 = 0,
        nickname: String? = nil,
        isBlocked: Bool = false,
        isMuted: Bool = false,
        isFavorite: Bool = false,
        lastMessageDate: Date? = nil,
        unreadCount: Int = 0,
        unreadMentionCount: Int = 0,
        ocvPreset: String? = nil,
        customOCVArrayString: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.publicKey = publicKey
        self.name = name
        self.typeRawValue = typeRawValue
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.lastAdvertTimestamp = lastAdvertTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
        self.nickname = nickname
        self.isBlocked = isBlocked
        self.isMuted = isMuted
        self.isFavorite = isFavorite
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.ocvPreset = ocvPreset
        self.customOCVArrayString = customOCVArrayString
    }

    /// Creates a Contact from a protocol ContactFrame
    public convenience init(deviceID: UUID, from frame: ContactFrame) {
        self.init(
            deviceID: deviceID,
            publicKey: frame.publicKey,
            name: frame.name,
            typeRawValue: frame.type.rawValue,
            flags: frame.flags,
            outPathLength: frame.outPathLength,
            outPath: frame.outPath,
            lastAdvertTimestamp: frame.lastAdvertTimestamp,
            latitude: frame.latitude,
            longitude: frame.longitude,
            lastModified: frame.lastModified,
            isFavorite: (frame.flags & 0x01) != 0
        )
    }
}

// MARK: - Computed Properties

public extension Contact {
    /// The contact type enum
    var type: ContactType {
        ContactType(rawValue: typeRawValue) ?? .chat
    }

    /// Display name (nickname if set, otherwise name)
    var displayName: String {
        nickname ?? name
    }

    /// The 6-byte public key prefix for message addressing
    var publicKeyPrefix: Data {
        publicKey.prefix(6)
    }

    /// Whether this contact uses flood routing
    var isFloodRouted: Bool {
        outPathLength < 0
    }

    /// Whether this contact has a known, valid location
    var hasLocation: Bool {
        let hasNonZero = latitude != 0 || longitude != 0
        guard hasNonZero else { return false }
        return CLLocationCoordinate2DIsValid(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    /// Whether this contact is a repeater
    var isRepeater: Bool {
        type == .repeater
    }

    /// Whether this contact is a room
    var isRoom: Bool {
        type == .room
    }

    /// Updates from a protocol ContactFrame
    func update(from frame: ContactFrame) {
        self.name = frame.name
        self.typeRawValue = frame.type.rawValue
        self.flags = frame.flags
        self.outPathLength = frame.outPathLength
        self.outPath = frame.outPath
        self.lastAdvertTimestamp = frame.lastAdvertTimestamp
        self.latitude = frame.latitude
        self.longitude = frame.longitude
        self.lastModified = frame.lastModified
        self.isFavorite = (frame.flags & 0x01) != 0
    }

    /// Converts to a protocol ContactFrame for sending to device
    func toContactFrame() -> ContactFrame {
        ContactFrame(
            publicKey: publicKey,
            type: type,
            flags: flags,
            outPathLength: outPathLength,
            outPath: outPath,
            name: name,
            lastAdvertTimestamp: lastAdvertTimestamp,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified
        )
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of Contact for cross-actor transfers
public struct ContactDTO: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let deviceID: UUID
    public let publicKey: Data
    public let name: String
    public let typeRawValue: UInt8
    public let flags: UInt8
    public let outPathLength: Int8
    public let outPath: Data
    public let lastAdvertTimestamp: UInt32
    public let latitude: Double
    public let longitude: Double
    public let lastModified: UInt32
    public let nickname: String?
    public let isBlocked: Bool
    public let isMuted: Bool
    public let isFavorite: Bool
    public let lastMessageDate: Date?
    public let unreadCount: Int
    public let unreadMentionCount: Int
    public let ocvPreset: String?
    public let customOCVArrayString: String?

    public init(from contact: Contact) {
        self.id = contact.id
        self.deviceID = contact.deviceID
        self.publicKey = contact.publicKey
        self.name = contact.name
        self.typeRawValue = contact.typeRawValue
        self.flags = contact.flags
        self.outPathLength = contact.outPathLength
        self.outPath = contact.outPath
        self.lastAdvertTimestamp = contact.lastAdvertTimestamp
        self.latitude = contact.latitude
        self.longitude = contact.longitude
        self.lastModified = contact.lastModified
        self.nickname = contact.nickname
        self.isBlocked = contact.isBlocked
        self.isMuted = contact.isMuted
        self.isFavorite = contact.isFavorite
        self.lastMessageDate = contact.lastMessageDate
        self.unreadCount = contact.unreadCount
        self.unreadMentionCount = contact.unreadMentionCount
        self.ocvPreset = contact.ocvPreset
        self.customOCVArrayString = contact.customOCVArrayString
    }

    /// Memberwise initializer for creating DTOs directly
    public init(
        id: UUID,
        deviceID: UUID,
        publicKey: Data,
        name: String,
        typeRawValue: UInt8,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        lastAdvertTimestamp: UInt32,
        latitude: Double,
        longitude: Double,
        lastModified: UInt32,
        nickname: String?,
        isBlocked: Bool,
        isMuted: Bool,
        isFavorite: Bool,
        lastMessageDate: Date?,
        unreadCount: Int,
        unreadMentionCount: Int = 0,
        ocvPreset: String? = nil,
        customOCVArrayString: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.publicKey = publicKey
        self.name = name
        self.typeRawValue = typeRawValue
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.lastAdvertTimestamp = lastAdvertTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
        self.nickname = nickname
        self.isBlocked = isBlocked
        self.isMuted = isMuted
        self.isFavorite = isFavorite
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.ocvPreset = ocvPreset
        self.customOCVArrayString = customOCVArrayString
    }

    public var type: ContactType {
        ContactType(rawValue: typeRawValue) ?? .chat
    }

    public var displayName: String {
        nickname ?? name
    }

    public var publicKeyPrefix: Data {
        publicKey.prefix(6)
    }

    public var isFloodRouted: Bool {
        outPathLength < 0
    }

    public var hasLocation: Bool {
        let hasNonZero = latitude != 0 || longitude != 0
        guard hasNonZero else { return false }
        return CLLocationCoordinate2DIsValid(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    public var publicKeyHex: String {
        publicKey.hexString()
    }

    /// The active OCV array for this contact (preset or custom)
    public var activeOCVArray: [Int] {
        // If custom preset with valid custom string, parse it
        if ocvPreset == OCVPreset.custom.rawValue, let customString = customOCVArrayString {
            let parsed = customString.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parsed.count == 11 {
                return parsed
            }
        }

        // Use preset if set
        if let presetName = ocvPreset, let preset = OCVPreset(rawValue: presetName) {
            return preset.ocvArray
        }

        // Default to Li-Ion
        return OCVPreset.liIon.ocvArray
    }

    /// Converts to a protocol ContactFrame for sending to device
    public func toContactFrame() -> ContactFrame {
        ContactFrame(
            publicKey: publicKey,
            type: type,
            flags: flags,
            outPathLength: outPathLength,
            outPath: outPath,
            name: name,
            lastAdvertTimestamp: lastAdvertTimestamp,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified
        )
    }
}
