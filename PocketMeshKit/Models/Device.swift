import Foundation
import SwiftData

@Model
public final class Device {
    @Attribute(.unique) var publicKey: Data // 32 bytes - primary identifier
    public var name: String
    public var firmwareVersion: String
    public var lastConnected: Date
    public var isActive: Bool // Currently connected device

    // Radio parameters
    public var frequency: UInt32 // Hz
    public var bandwidth: UInt32 // Hz
    public var spreadingFactor: UInt8
    public var codingRate: UInt8
    public var txPower: Int8 // dBm

    // Location (optional)
    public var latitude: Double?
    public var longitude: Double?

    // Protocol configuration
    public var multiAcksEnabled: Bool = false
    public var defaultFloodScope: String = "*" // Global scope by default

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Contact.device)
    public var contacts: [Contact] = []

    @Relationship(deleteRule: .cascade, inverse: \Message.device)
    public var messages: [Message] = []

    @Relationship(deleteRule: .cascade, inverse: \Channel.device)
    public var channels: [Channel] = []

    public init(
        publicKey: Data,
        name: String,
        firmwareVersion: String,
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
        txPower: Int8,
    ) {
        self.publicKey = publicKey
        self.name = name
        self.firmwareVersion = firmwareVersion
        lastConnected = Date()
        isActive = false
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.txPower = txPower
    }
}
