import Foundation
import SwiftData

/// Represents an authenticated session with a remote node.
/// Used for both room servers and repeater admin connections.
@Model
public final class RemoteNodeSession {
    /// Unique session identifier
    @Attribute(.unique)
    public var id: UUID

    /// The companion radio used to access this node
    public var deviceID: UUID

    /// 32-byte remote node's public key
    public var publicKey: Data

    /// Human-readable node name
    public var name: String

    /// Raw value of RemoteNodeRole
    public var roleRawValue: UInt8

    /// Node latitude (non-optional, consistent with Device)
    public var latitude: Double

    /// Node longitude
    public var longitude: Double

    /// Whether currently connected/authenticated
    public var isConnected: Bool

    /// Permission level raw value (RoomPermissionLevel)
    public var permissionLevelRawValue: UInt8

    /// Last successful connection date
    public var lastConnectedDate: Date?

    /// Cached battery level from last status
    public var lastBatteryMillivolts: UInt16?

    /// Cached uptime from last status
    public var lastUptimeSeconds: UInt32?

    /// Cached noise floor from last status
    public var lastNoiseFloor: Int16?

    /// Unread message count (room-specific)
    public var unreadCount: Int

    /// Last RX airtime in seconds (repeater-specific)
    public var lastRxAirtimeSeconds: UInt32?

    /// Number of neighbors (repeater-specific)
    public var neighborCount: Int

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        publicKey: Data,
        name: String,
        role: RemoteNodeRole,
        latitude: Double = 0,
        longitude: Double = 0,
        isConnected: Bool = false,
        permissionLevel: RoomPermissionLevel = .guest,
        lastConnectedDate: Date? = nil,
        lastBatteryMillivolts: UInt16? = nil,
        lastUptimeSeconds: UInt32? = nil,
        lastNoiseFloor: Int16? = nil,
        unreadCount: Int = 0,
        lastRxAirtimeSeconds: UInt32? = nil,
        neighborCount: Int = 0
    ) {
        self.id = id
        self.deviceID = deviceID
        self.publicKey = publicKey
        self.name = name
        self.roleRawValue = role.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.isConnected = isConnected
        self.permissionLevelRawValue = permissionLevel.rawValue
        self.lastConnectedDate = lastConnectedDate
        self.lastBatteryMillivolts = lastBatteryMillivolts
        self.lastUptimeSeconds = lastUptimeSeconds
        self.lastNoiseFloor = lastNoiseFloor
        self.unreadCount = unreadCount
        self.lastRxAirtimeSeconds = lastRxAirtimeSeconds
        self.neighborCount = neighborCount
    }
}

// MARK: - Computed Properties

public extension RemoteNodeSession {
    /// The node role enum
    var role: RemoteNodeRole {
        RemoteNodeRole(rawValue: roleRawValue) ?? .repeater
    }

    /// The permission level enum
    var permissionLevel: RoomPermissionLevel {
        get { RoomPermissionLevel(rawValue: permissionLevelRawValue) ?? .guest }
        set { permissionLevelRawValue = newValue.rawValue }
    }

    /// Whether this is a room server session
    var isRoom: Bool { role == .roomServer }

    /// Whether this is a repeater session
    var isRepeater: Bool { role == .repeater }

    /// 6-byte public key prefix for addressing
    var publicKeyPrefix: Data { publicKey.prefix(6) }

    /// Hex string representation of full public key
    var publicKeyHex: String {
        publicKey.map { String(format: "%02X", $0) }.joined()
    }

    /// Whether user can post messages (room-specific)
    var canPost: Bool { isRoom && permissionLevel.canPost }

    /// Whether user has admin access
    var isAdmin: Bool { permissionLevel.isAdmin }
}

// MARK: - Sendable DTO

/// A sendable snapshot of RemoteNodeSession for cross-actor transfers
public struct RemoteNodeSessionDTO: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let deviceID: UUID
    public let publicKey: Data
    public let name: String
    public let role: RemoteNodeRole
    public let latitude: Double
    public let longitude: Double
    public let isConnected: Bool
    public let permissionLevel: RoomPermissionLevel
    public let lastConnectedDate: Date?
    public let lastBatteryMillivolts: UInt16?
    public let lastUptimeSeconds: UInt32?
    public let lastNoiseFloor: Int16?
    public let unreadCount: Int
    public let lastRxAirtimeSeconds: UInt32?
    public let neighborCount: Int

    public init(from model: RemoteNodeSession) {
        self.id = model.id
        self.deviceID = model.deviceID
        self.publicKey = model.publicKey
        self.name = model.name
        self.role = model.role
        self.latitude = model.latitude
        self.longitude = model.longitude
        self.isConnected = model.isConnected
        self.permissionLevel = model.permissionLevel
        self.lastConnectedDate = model.lastConnectedDate
        self.lastBatteryMillivolts = model.lastBatteryMillivolts
        self.lastUptimeSeconds = model.lastUptimeSeconds
        self.lastNoiseFloor = model.lastNoiseFloor
        self.unreadCount = model.unreadCount
        self.lastRxAirtimeSeconds = model.lastRxAirtimeSeconds
        self.neighborCount = model.neighborCount
    }

    /// Memberwise initializer for creating DTOs directly
    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        publicKey: Data,
        name: String,
        role: RemoteNodeRole,
        latitude: Double = 0,
        longitude: Double = 0,
        isConnected: Bool = false,
        permissionLevel: RoomPermissionLevel = .guest,
        lastConnectedDate: Date? = nil,
        lastBatteryMillivolts: UInt16? = nil,
        lastUptimeSeconds: UInt32? = nil,
        lastNoiseFloor: Int16? = nil,
        unreadCount: Int = 0,
        lastRxAirtimeSeconds: UInt32? = nil,
        neighborCount: Int = 0
    ) {
        self.id = id
        self.deviceID = deviceID
        self.publicKey = publicKey
        self.name = name
        self.role = role
        self.latitude = latitude
        self.longitude = longitude
        self.isConnected = isConnected
        self.permissionLevel = permissionLevel
        self.lastConnectedDate = lastConnectedDate
        self.lastBatteryMillivolts = lastBatteryMillivolts
        self.lastUptimeSeconds = lastUptimeSeconds
        self.lastNoiseFloor = lastNoiseFloor
        self.unreadCount = unreadCount
        self.lastRxAirtimeSeconds = lastRxAirtimeSeconds
        self.neighborCount = neighborCount
    }

    public var publicKeyPrefix: Data { publicKey.prefix(6) }

    public var publicKeyHex: String {
        publicKey.map { String(format: "%02X", $0) }.joined()
    }

    public var isRoom: Bool { role == .roomServer }

    public var isRepeater: Bool { role == .repeater }

    public var canPost: Bool { isRoom && permissionLevel.canPost }

    public var isAdmin: Bool { permissionLevel.isAdmin }
}
