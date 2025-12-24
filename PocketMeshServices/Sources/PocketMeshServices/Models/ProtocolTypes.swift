/// Protocol types that add iOS-specific value over MeshCore.
///
/// MeshCore provides protocol-level types for parsing and command building.
/// This file provides:
/// - Semantic enums with helper methods (ContactType, TextType, etc.)
/// - ContactFrame for creating contacts (vs MeshContact which is parsed)
/// - Protocol constants and limits
///
/// Types that are direct duplicates of MeshCore types have been removed.
/// Use MeshCore types directly: SelfInfo, DeviceCapabilities, ChannelInfo,
/// ContactMessage, ChannelMessage, MessageSentInfo, BatteryInfo.

import Foundation

// MARK: - Contact Types

/// Contact type identifier for mesh network nodes
public enum ContactType: UInt8, Sendable, Codable {
    case chat = 0x01
    case repeater = 0x02
    case room = 0x03
}

// MARK: - Text Types

/// Message text type encoding
public enum TextType: UInt8, Sendable, Codable {
    case plain = 0x00
    case cliData = 0x01
    case signedPlain = 0x02
}

// MARK: - Location Policy

/// Advertisement location sharing policy
public enum AdvertLocationPolicy: UInt8, Sendable, Codable {
    case none = 0
    case share = 1
}

// MARK: - Remote Node Types

/// Discriminates between remote node types for role-specific handling
public enum RemoteNodeRole: UInt8, Sendable, Codable {
    case repeater = 0x02
    case roomServer = 0x03

    /// Initialize from ContactType
    public init?(contactType: ContactType) {
        switch contactType {
        case .repeater: self = .repeater
        case .room: self = .roomServer
        case .chat: return nil
        }
    }
}

/// Permission levels for room server access
public enum RoomPermissionLevel: UInt8, Sendable, Comparable, Codable {
    case guest = 0x00
    case readWrite = 0x01
    case admin = 0x02

    public var canPost: Bool { self >= .readWrite }
    public var isAdmin: Bool { self == .admin }

    public var displayName: String {
        switch self {
        case .guest: return "Guest"
        case .readWrite: return "Member"
        case .admin: return "Admin"
        }
    }

    public static func < (lhs: RoomPermissionLevel, rhs: RoomPermissionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Contact Frame (for creating contacts)

/// Contact information frame from device
public struct ContactFrame: Sendable, Equatable {
    public let publicKey: Data
    public let type: ContactType
    public let flags: UInt8
    public let outPathLength: Int8
    public let outPath: Data
    public let name: String
    public let lastAdvertTimestamp: UInt32
    public let latitude: Double
    public let longitude: Double
    public let lastModified: UInt32

    public init(
        publicKey: Data,
        type: ContactType,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        name: String,
        lastAdvertTimestamp: UInt32,
        latitude: Double,
        longitude: Double,
        lastModified: UInt32
    ) {
        self.publicKey = publicKey
        self.type = type
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.name = name
        self.lastAdvertTimestamp = lastAdvertTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
    }
}

// MARK: - Protocol Constants

/// Error codes returned by the device
public enum ProtocolError: UInt8, Sendable, Error {
    case unsupportedCommand = 0x01
    case notFound = 0x02
    case tableFull = 0x03
    case badState = 0x04
    case fileIOError = 0x05
    case illegalArgument = 0x06
}

/// Protocol size limits and constants
public enum ProtocolLimits {
    public static let publicKeySize = 32
    public static let maxPathSize = 64
    public static let maxFrameSize = 250
    public static let signatureSize = 64
    public static let maxContacts = 100
    public static let offlineQueueSize = 16
    public static let maxNameLength = 32
    public static let channelSecretSize = 16
    public static let maxMessageLength = 160

    /// Maximum characters for direct messages (app-enforced limit per MeshCore spec)
    public static let maxDirectMessageLength = 150

    /// Calculate max channel message length based on node name
    /// Formula: 160 - nodeNameLength - 2
    public static func maxChannelMessageLength(nodeNameLength: Int) -> Int {
        max(0, 160 - nodeNameLength - 2)
    }
}

// MARK: - Confirmations

/// Confirmation that a message was acknowledged
public struct SendConfirmation: Sendable, Equatable {
    public let ackCode: UInt32
    public let roundTripTime: UInt32

    public init(ackCode: UInt32, roundTripTime: UInt32) {
        self.ackCode = ackCode
        self.roundTripTime = roundTripTime
    }
}
