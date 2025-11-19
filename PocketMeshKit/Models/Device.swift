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
    public var radioFrequency: UInt32 // Hz * 1000
    public var radioBandwidth: UInt32 // kHz * 1000
    public var radioSpreadingFactor: UInt8
    public var radioCodingRate: UInt8
    public var txPower: Int8 // dBm

    // Location (optional)
    public var latitude: Double?
    public var longitude: Double?

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
        radioFrequency: UInt32,
        radioBandwidth: UInt32,
        radioSpreadingFactor: UInt8,
        radioCodingRate: UInt8,
        txPower: Int8
    ) {
        self.publicKey = publicKey
        self.name = name
        self.firmwareVersion = firmwareVersion
        self.lastConnected = Date()
        self.isActive = false
        self.radioFrequency = radioFrequency
        self.radioBandwidth = radioBandwidth
        self.radioSpreadingFactor = radioSpreadingFactor
        self.radioCodingRate = radioCodingRate
        self.txPower = txPower
    }
}
