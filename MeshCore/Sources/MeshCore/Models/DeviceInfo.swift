import Foundation

/// Self info returned after appstart
public struct SelfInfo: Sendable, Equatable {
    public let advertisementType: UInt8
    public let txPower: UInt8
    public let maxTxPower: UInt8
    public let publicKey: Data
    public let latitude: Double
    public let longitude: Double
    public let multiAcks: UInt8
    public let advertisementLocationPolicy: UInt8
    public let telemetryModeEnvironment: UInt8
    public let telemetryModeLocation: UInt8
    public let telemetryModeBase: UInt8
    public let manualAddContacts: Bool
    public let radioFrequency: Double
    public let radioBandwidth: Double
    public let radioSpreadingFactor: UInt8
    public let radioCodingRate: UInt8
    public let name: String

    public init(
        advertisementType: UInt8,
        txPower: UInt8,
        maxTxPower: UInt8,
        publicKey: Data,
        latitude: Double,
        longitude: Double,
        multiAcks: UInt8,
        advertisementLocationPolicy: UInt8,
        telemetryModeEnvironment: UInt8,
        telemetryModeLocation: UInt8,
        telemetryModeBase: UInt8,
        manualAddContacts: Bool,
        radioFrequency: Double,
        radioBandwidth: Double,
        radioSpreadingFactor: UInt8,
        radioCodingRate: UInt8,
        name: String
    ) {
        self.advertisementType = advertisementType
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.publicKey = publicKey
        self.latitude = latitude
        self.longitude = longitude
        self.multiAcks = multiAcks
        self.advertisementLocationPolicy = advertisementLocationPolicy
        self.telemetryModeEnvironment = telemetryModeEnvironment
        self.telemetryModeLocation = telemetryModeLocation
        self.telemetryModeBase = telemetryModeBase
        self.manualAddContacts = manualAddContacts
        self.radioFrequency = radioFrequency
        self.radioBandwidth = radioBandwidth
        self.radioSpreadingFactor = radioSpreadingFactor
        self.radioCodingRate = radioCodingRate
        self.name = name
    }
}

/// Device capabilities and firmware info
public struct DeviceCapabilities: Sendable, Equatable {
    public let firmwareVersion: UInt8
    public let maxContacts: Int
    public let maxChannels: Int
    public let blePin: UInt32
    public let firmwareBuild: String
    public let model: String
    public let version: String

    public init(
        firmwareVersion: UInt8,
        maxContacts: Int,
        maxChannels: Int,
        blePin: UInt32,
        firmwareBuild: String,
        model: String,
        version: String
    ) {
        self.firmwareVersion = firmwareVersion
        self.maxContacts = maxContacts
        self.maxChannels = maxChannels
        self.blePin = blePin
        self.firmwareBuild = firmwareBuild
        self.model = model
        self.version = version
    }
}

/// Battery and storage info
/// Per Python reader.py:262-268, battery level is read as UInt16 (2 bytes little-endian)
/// representing raw millivolts, NOT a percentage.
public struct BatteryInfo: Sendable, Equatable {
    /// Raw battery level in millivolts (UInt16 range: 0-65535)
    /// Note: This is NOT a percentage. Convert to percentage based on device specs.
    public let level: Int
    public let usedStorageKB: Int?
    public let totalStorageKB: Int?

    public init(level: Int, usedStorageKB: Int? = nil, totalStorageKB: Int? = nil) {
        self.level = level
        self.usedStorageKB = usedStorageKB
        self.totalStorageKB = totalStorageKB
    }
}
