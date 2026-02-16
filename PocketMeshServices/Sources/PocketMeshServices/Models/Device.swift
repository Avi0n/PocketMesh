import Foundation
import SwiftData

/// Represents a connected MeshCore BLE device.
/// Each device has its own isolated data store for contacts, messages, and channels.
@Model
public final class Device {
    /// Unique identifier for the device (derived from BLE peripheral identifier)
    @Attribute(.unique)
    public var id: UUID

    /// The 32-byte public key of the device
    public var publicKey: Data

    /// Human-readable name of the node
    public var nodeName: String

    /// Firmware version code (e.g., 8)
    public var firmwareVersion: UInt8

    /// Firmware version string (e.g., "v1.11.0")
    public var firmwareVersionString: String

    /// Manufacturer name
    public var manufacturerName: String

    /// Build date string
    public var buildDate: String

    /// Maximum number of contacts supported
    public var maxContacts: UInt16

    /// Maximum number of channels supported
    public var maxChannels: UInt8

    /// Radio frequency in kHz
    public var frequency: UInt32

    /// Radio bandwidth in kHz
    public var bandwidth: UInt32

    /// LoRa spreading factor (5-12)
    public var spreadingFactor: UInt8

    /// LoRa coding rate (5-8)
    public var codingRate: UInt8

    /// Transmit power in dBm (may be negative)
    public var txPower: Int8

    /// Maximum transmit power in dBm
    public var maxTxPower: Int8

    /// Node latitude (scaled by 1e6)
    public var latitude: Double

    /// Node longitude (scaled by 1e6)
    public var longitude: Double

    /// BLE PIN (0 = disabled, 100000-999999 = enabled)
    public var blePin: UInt32

    /// Whether client repeat mode is enabled (v9+ firmware)
    public var clientRepeat: Bool = false

    /// Cached radio settings from before repeat mode was enabled, for restoration on disable.
    /// All 4 fields are set together when enabling repeat mode, and cleared together when disabling.
    public var preRepeatFrequency: UInt32?
    public var preRepeatBandwidth: UInt32?
    public var preRepeatSpreadingFactor: UInt8?
    public var preRepeatCodingRate: UInt8?

    /// Manual add contacts mode
    public var manualAddContacts: Bool

    /// Auto-add configuration bitmask from device
    public var autoAddConfig: UInt8 = 0

    /// Number of acknowledgments to send for direct messages (0=disabled, 1-2 typical)
    public var multiAcks: UInt8

    /// Telemetry mode for base data
    public var telemetryModeBase: UInt8

    /// Telemetry mode for location data
    public var telemetryModeLoc: UInt8

    /// Telemetry mode for environment data
    public var telemetryModeEnv: UInt8

    /// Advertisement location policy
    public var advertLocationPolicy: UInt8

    /// Last time the device was connected
    public var lastConnected: Date

    /// Last sync timestamp for contacts (watermark for incremental sync)
    public var lastContactSync: UInt32

    /// Whether this is the currently active device
    public var isActive: Bool

    /// Selected OCV preset name (nil = liIon default)
    public var ocvPreset: String?

    /// Custom OCV array as comma-separated string (e.g., "4240,4112,4029,...")
    public var customOCVArrayString: String?

    /// Connection methods available for this device (BLE, WiFi, etc.)
    public var connectionMethods: [ConnectionMethod] = []

    public init(
        id: UUID = UUID(),
        publicKey: Data,
        nodeName: String,
        firmwareVersion: UInt8 = 0,
        firmwareVersionString: String = "",
        manufacturerName: String = "",
        buildDate: String = "",
        maxContacts: UInt16 = 100,
        maxChannels: UInt8 = 8,
        frequency: UInt32 = 915_000,
        bandwidth: UInt32 = 250_000,
        spreadingFactor: UInt8 = 10,
        codingRate: UInt8 = 5,
        txPower: Int8 = 20,
        maxTxPower: Int8 = 20,
        latitude: Double = 0,
        longitude: Double = 0,
        blePin: UInt32 = 0,
        clientRepeat: Bool = false,
        preRepeatFrequency: UInt32? = nil,
        preRepeatBandwidth: UInt32? = nil,
        preRepeatSpreadingFactor: UInt8? = nil,
        preRepeatCodingRate: UInt8? = nil,
        manualAddContacts: Bool = false,
        autoAddConfig: UInt8 = 0,
        multiAcks: UInt8 = 2,
        telemetryModeBase: UInt8 = 2,
        telemetryModeLoc: UInt8 = 0,
        telemetryModeEnv: UInt8 = 0,
        advertLocationPolicy: UInt8 = 0,
        lastConnected: Date = Date(),
        lastContactSync: UInt32 = 0,
        isActive: Bool = false,
        ocvPreset: String? = nil,
        customOCVArrayString: String? = nil,
        connectionMethods: [ConnectionMethod] = []
    ) {
        self.id = id
        self.publicKey = publicKey
        self.nodeName = nodeName
        self.firmwareVersion = firmwareVersion
        self.firmwareVersionString = firmwareVersionString
        self.manufacturerName = manufacturerName
        self.buildDate = buildDate
        self.maxContacts = maxContacts
        self.maxChannels = maxChannels
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.latitude = latitude
        self.longitude = longitude
        self.blePin = blePin
        self.clientRepeat = clientRepeat
        self.preRepeatFrequency = preRepeatFrequency
        self.preRepeatBandwidth = preRepeatBandwidth
        self.preRepeatSpreadingFactor = preRepeatSpreadingFactor
        self.preRepeatCodingRate = preRepeatCodingRate
        self.manualAddContacts = manualAddContacts
        self.autoAddConfig = autoAddConfig
        self.multiAcks = multiAcks
        self.telemetryModeBase = telemetryModeBase
        self.telemetryModeLoc = telemetryModeLoc
        self.telemetryModeEnv = telemetryModeEnv
        self.advertLocationPolicy = advertLocationPolicy
        self.lastConnected = lastConnected
        self.lastContactSync = lastContactSync
        self.isActive = isActive
        self.ocvPreset = ocvPreset
        self.customOCVArrayString = customOCVArrayString
        self.connectionMethods = connectionMethods
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of Device for cross-actor transfers
public struct DeviceDTO: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var publicKey: Data
    public var nodeName: String
    public var firmwareVersion: UInt8
    public var firmwareVersionString: String
    public var manufacturerName: String
    public var buildDate: String
    public var maxContacts: UInt16
    public var maxChannels: UInt8
    public var frequency: UInt32
    public var bandwidth: UInt32
    public var spreadingFactor: UInt8
    public var codingRate: UInt8
    public var txPower: Int8
    public var maxTxPower: Int8
    public var latitude: Double
    public var longitude: Double
    public var blePin: UInt32
    public var clientRepeat: Bool
    public var preRepeatFrequency: UInt32?
    public var preRepeatBandwidth: UInt32?
    public var preRepeatSpreadingFactor: UInt8?
    public var preRepeatCodingRate: UInt8?
    public var manualAddContacts: Bool
    public var autoAddConfig: UInt8
    public var multiAcks: UInt8
    public var telemetryModeBase: UInt8
    public var telemetryModeLoc: UInt8
    public var telemetryModeEnv: UInt8
    public var advertLocationPolicy: UInt8
    public var lastConnected: Date
    public var lastContactSync: UInt32
    public var isActive: Bool
    public var ocvPreset: String?
    public var customOCVArrayString: String?
    public var connectionMethods: [ConnectionMethod]

    /// Computed auto-add mode based on manualAddContacts and autoAddConfig
    public var autoAddMode: AutoAddMode {
        AutoAddMode.mode(manualAddContacts: manualAddContacts, autoAddConfig: autoAddConfig)
    }

    /// Whether to auto-add Contact type nodes (bit 0x02)
    public var autoAddContacts: Bool {
        autoAddConfig & 0x02 != 0
    }

    /// Whether to auto-add Repeater type nodes (bit 0x04)
    public var autoAddRepeaters: Bool {
        autoAddConfig & 0x04 != 0
    }

    /// Whether to auto-add Room Server type nodes (bit 0x08)
    public var autoAddRoomServers: Bool {
        autoAddConfig & 0x08 != 0
    }

    /// Whether to overwrite oldest non-favorite when storage is full (bit 0x01)
    public var overwriteOldest: Bool {
        autoAddConfig & 0x01 != 0
    }

    /// Whether the device supports auto-add configuration (v1.12+)
    /// Devices with older firmware only support manualAddContacts toggle
    public var supportsAutoAddConfig: Bool {
        firmwareVersionString.isAtLeast(major: 1, minor: 12)
    }

    /// Whether this device supports client repeat mode (firmware v9+)
    public var supportsClientRepeat: Bool { firmwareVersion >= 9 }

    /// Whether pre-repeat radio settings are saved for restoration.
    public var hasPreRepeatSettings: Bool {
        preRepeatFrequency != nil && preRepeatBandwidth != nil &&
        preRepeatSpreadingFactor != nil && preRepeatCodingRate != nil
    }

    public init(
        id: UUID,
        publicKey: Data,
        nodeName: String,
        firmwareVersion: UInt8,
        firmwareVersionString: String,
        manufacturerName: String,
        buildDate: String,
        maxContacts: UInt16,
        maxChannels: UInt8,
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
        txPower: Int8,
        maxTxPower: Int8,
        latitude: Double,
        longitude: Double,
        blePin: UInt32,
        clientRepeat: Bool = false,
        preRepeatFrequency: UInt32? = nil,
        preRepeatBandwidth: UInt32? = nil,
        preRepeatSpreadingFactor: UInt8? = nil,
        preRepeatCodingRate: UInt8? = nil,
        manualAddContacts: Bool,
        autoAddConfig: UInt8 = 0,
        multiAcks: UInt8,
        telemetryModeBase: UInt8,
        telemetryModeLoc: UInt8,
        telemetryModeEnv: UInt8,
        advertLocationPolicy: UInt8,
        lastConnected: Date,
        lastContactSync: UInt32,
        isActive: Bool,
        ocvPreset: String?,
        customOCVArrayString: String?,
        connectionMethods: [ConnectionMethod] = []
    ) {
        self.id = id
        self.publicKey = publicKey
        self.nodeName = nodeName
        self.firmwareVersion = firmwareVersion
        self.firmwareVersionString = firmwareVersionString
        self.manufacturerName = manufacturerName
        self.buildDate = buildDate
        self.maxContacts = maxContacts
        self.maxChannels = maxChannels
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.latitude = latitude
        self.longitude = longitude
        self.blePin = blePin
        self.clientRepeat = clientRepeat
        self.preRepeatFrequency = preRepeatFrequency
        self.preRepeatBandwidth = preRepeatBandwidth
        self.preRepeatSpreadingFactor = preRepeatSpreadingFactor
        self.preRepeatCodingRate = preRepeatCodingRate
        self.manualAddContacts = manualAddContacts
        self.autoAddConfig = autoAddConfig
        self.multiAcks = multiAcks
        self.telemetryModeBase = telemetryModeBase
        self.telemetryModeLoc = telemetryModeLoc
        self.telemetryModeEnv = telemetryModeEnv
        self.advertLocationPolicy = advertLocationPolicy
        self.lastConnected = lastConnected
        self.lastContactSync = lastContactSync
        self.isActive = isActive
        self.ocvPreset = ocvPreset
        self.customOCVArrayString = customOCVArrayString
        self.connectionMethods = connectionMethods
    }

    public init(from device: Device) {
        self.id = device.id
        self.publicKey = device.publicKey
        self.nodeName = device.nodeName
        self.firmwareVersion = device.firmwareVersion
        self.firmwareVersionString = device.firmwareVersionString
        self.manufacturerName = device.manufacturerName
        self.buildDate = device.buildDate
        self.maxContacts = device.maxContacts
        self.maxChannels = device.maxChannels
        self.frequency = device.frequency
        self.bandwidth = device.bandwidth
        self.spreadingFactor = device.spreadingFactor
        self.codingRate = device.codingRate
        self.txPower = device.txPower
        self.maxTxPower = device.maxTxPower
        self.latitude = device.latitude
        self.longitude = device.longitude
        self.blePin = device.blePin
        self.clientRepeat = device.clientRepeat
        self.preRepeatFrequency = device.preRepeatFrequency
        self.preRepeatBandwidth = device.preRepeatBandwidth
        self.preRepeatSpreadingFactor = device.preRepeatSpreadingFactor
        self.preRepeatCodingRate = device.preRepeatCodingRate
        self.manualAddContacts = device.manualAddContacts
        self.autoAddConfig = device.autoAddConfig
        self.multiAcks = device.multiAcks
        self.telemetryModeBase = device.telemetryModeBase
        self.telemetryModeLoc = device.telemetryModeLoc
        self.telemetryModeEnv = device.telemetryModeEnv
        self.advertLocationPolicy = device.advertLocationPolicy
        self.lastConnected = device.lastConnected
        self.lastContactSync = device.lastContactSync
        self.isActive = device.isActive
        self.ocvPreset = device.ocvPreset
        self.customOCVArrayString = device.customOCVArrayString
        self.connectionMethods = device.connectionMethods
    }

    /// The 6-byte public key prefix used for identifying messages
    public var publicKeyPrefix: Data {
        publicKey.prefix(6)
    }

    /// Returns a new DeviceDTO with the given mutations applied.
    public func copy(_ mutations: (inout DeviceDTO) -> Void) -> DeviceDTO {
        var copy = self
        mutations(&copy)
        return copy
    }

    /// The active OCV array for this device (preset or custom)
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

    /// Returns a new DeviceDTO with settings updated from SelfInfo.
    /// Used after device settings are changed via SettingsService.
    public func updating(from selfInfo: MeshCore.SelfInfo) -> DeviceDTO {
        copy {
            $0.nodeName = selfInfo.name
            $0.frequency = UInt32(selfInfo.radioFrequency * 1000)
            $0.bandwidth = UInt32(selfInfo.radioBandwidth * 1000)
            $0.spreadingFactor = selfInfo.radioSpreadingFactor
            $0.codingRate = selfInfo.radioCodingRate
            $0.txPower = selfInfo.txPower
            $0.latitude = selfInfo.latitude
            $0.longitude = selfInfo.longitude
            $0.manualAddContacts = selfInfo.manualAddContacts
            $0.multiAcks = selfInfo.multiAcks
            $0.telemetryModeBase = selfInfo.telemetryModeBase
            $0.telemetryModeLoc = selfInfo.telemetryModeLocation
            $0.telemetryModeEnv = selfInfo.telemetryModeEnvironment
            $0.advertLocationPolicy = selfInfo.advertisementLocationPolicy
        }
    }

    /// Returns a new DeviceDTO with current radio settings saved as pre-repeat settings.
    public func savingPreRepeatSettings() -> DeviceDTO {
        copy {
            $0.preRepeatFrequency = frequency
            $0.preRepeatBandwidth = bandwidth
            $0.preRepeatSpreadingFactor = spreadingFactor
            $0.preRepeatCodingRate = codingRate
        }
    }

    /// Returns a new DeviceDTO with pre-repeat settings cleared.
    public func clearingPreRepeatSettings() -> DeviceDTO {
        copy {
            $0.preRepeatFrequency = nil
            $0.preRepeatBandwidth = nil
            $0.preRepeatSpreadingFactor = nil
            $0.preRepeatCodingRate = nil
        }
    }
}

// MARK: - Version String Comparison

extension String {
    /// Checks if this version string is at least the specified version.
    /// Handles formats like "v1.12.0", "1.12", "v1.12"
    /// - Parameters:
    ///   - major: Required major version
    ///   - minor: Required minor version
    /// - Returns: true if this version >= major.minor
    func isAtLeast(major requiredMajor: Int, minor requiredMinor: Int) -> Bool {
        let cleaned = trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let components = cleaned.split(separator: ".")
        guard components.count >= 2,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return false
        }
        if major > requiredMajor { return true }
        if major < requiredMajor { return false }
        return minor >= requiredMinor
    }
}
