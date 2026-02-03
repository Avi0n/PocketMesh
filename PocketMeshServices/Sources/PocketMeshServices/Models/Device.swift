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
    public var maxContacts: UInt8

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

    /// Transmit power in dBm
    public var txPower: UInt8

    /// Maximum transmit power in dBm
    public var maxTxPower: UInt8

    /// Node latitude (scaled by 1e6)
    public var latitude: Double

    /// Node longitude (scaled by 1e6)
    public var longitude: Double

    /// BLE PIN (0 = disabled, 100000-999999 = enabled)
    public var blePin: UInt32

    /// Manual add contacts mode
    public var manualAddContacts: Bool

    /// Auto-add configuration bitmask from device
    public var autoAddConfig: UInt8 = 0

    /// Computed auto-add mode based on manualAddContacts and autoAddConfig
    public var autoAddMode: AutoAddMode {
        AutoAddMode.mode(manualAddContacts: manualAddContacts, autoAddConfig: autoAddConfig)
    }

    /// Whether to auto-add Contact type nodes (bit 0x02)
    public var autoAddContacts: Bool {
        get { autoAddConfig & 0x02 != 0 }
        set {
            if newValue {
                autoAddConfig |= 0x02
            } else {
                autoAddConfig &= ~0x02
            }
        }
    }

    /// Whether to auto-add Repeater type nodes (bit 0x04)
    public var autoAddRepeaters: Bool {
        get { autoAddConfig & 0x04 != 0 }
        set {
            if newValue {
                autoAddConfig |= 0x04
            } else {
                autoAddConfig &= ~0x04
            }
        }
    }

    /// Whether to auto-add Room Server type nodes (bit 0x08)
    public var autoAddRoomServers: Bool {
        get { autoAddConfig & 0x08 != 0 }
        set {
            if newValue {
                autoAddConfig |= 0x08
            } else {
                autoAddConfig &= ~0x08
            }
        }
    }

    // Note: Sensor auto-add (0x10) not supported in this version - deferred per design doc

    /// Whether to overwrite oldest non-favorite when storage is full (bit 0x01)
    public var overwriteOldest: Bool {
        get { autoAddConfig & 0x01 != 0 }
        set {
            if newValue {
                autoAddConfig |= 0x01
            } else {
                autoAddConfig &= ~0x01
            }
        }
    }

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
        maxContacts: UInt8 = 100,
        maxChannels: UInt8 = 8,
        frequency: UInt32 = 915_000,
        bandwidth: UInt32 = 250_000,
        spreadingFactor: UInt8 = 10,
        codingRate: UInt8 = 5,
        txPower: UInt8 = 20,
        maxTxPower: UInt8 = 20,
        latitude: Double = 0,
        longitude: Double = 0,
        blePin: UInt32 = 0,
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
    public let id: UUID
    public let publicKey: Data
    public let nodeName: String
    public let firmwareVersion: UInt8
    public let firmwareVersionString: String
    public let manufacturerName: String
    public let buildDate: String
    public let maxContacts: UInt8
    public let maxChannels: UInt8
    public let frequency: UInt32
    public let bandwidth: UInt32
    public let spreadingFactor: UInt8
    public let codingRate: UInt8
    public let txPower: UInt8
    public let maxTxPower: UInt8
    public let latitude: Double
    public let longitude: Double
    public let blePin: UInt32
    public let manualAddContacts: Bool
    public let autoAddConfig: UInt8
    public let multiAcks: UInt8
    public let telemetryModeBase: UInt8
    public let telemetryModeLoc: UInt8
    public let telemetryModeEnv: UInt8
    public let advertLocationPolicy: UInt8
    public let lastConnected: Date
    public let lastContactSync: UInt32
    public let isActive: Bool
    public let ocvPreset: String?
    public let customOCVArrayString: String?
    public let connectionMethods: [ConnectionMethod]

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

    public init(
        id: UUID,
        publicKey: Data,
        nodeName: String,
        firmwareVersion: UInt8,
        firmwareVersionString: String,
        manufacturerName: String,
        buildDate: String,
        maxContacts: UInt8,
        maxChannels: UInt8,
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
        txPower: UInt8,
        maxTxPower: UInt8,
        latitude: Double,
        longitude: Double,
        blePin: UInt32,
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
        DeviceDTO(
            id: id,
            publicKey: publicKey,
            nodeName: selfInfo.name,
            firmwareVersion: firmwareVersion,
            firmwareVersionString: firmwareVersionString,
            manufacturerName: manufacturerName,
            buildDate: buildDate,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            frequency: UInt32(selfInfo.radioFrequency * 1000),
            bandwidth: UInt32(selfInfo.radioBandwidth * 1000),
            spreadingFactor: selfInfo.radioSpreadingFactor,
            codingRate: selfInfo.radioCodingRate,
            txPower: selfInfo.txPower,
            maxTxPower: maxTxPower,
            latitude: selfInfo.latitude,
            longitude: selfInfo.longitude,
            blePin: blePin,
            manualAddContacts: selfInfo.manualAddContacts,
            autoAddConfig: autoAddConfig,
            multiAcks: multiAcks,
            telemetryModeBase: telemetryModeBase,
            telemetryModeLoc: telemetryModeLoc,
            telemetryModeEnv: telemetryModeEnv,
            advertLocationPolicy: advertLocationPolicy,
            lastConnected: lastConnected,
            lastContactSync: lastContactSync,
            isActive: isActive,
            ocvPreset: ocvPreset,
            customOCVArrayString: customOCVArrayString,
            connectionMethods: connectionMethods
        )
    }

    /// Returns a new DeviceDTO with updated auto-add config.
    /// Used after auto-add settings are changed via SettingsService.
    public func withAutoAddConfig(_ config: UInt8) -> DeviceDTO {
        DeviceDTO(
            id: id,
            publicKey: publicKey,
            nodeName: nodeName,
            firmwareVersion: firmwareVersion,
            firmwareVersionString: firmwareVersionString,
            manufacturerName: manufacturerName,
            buildDate: buildDate,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            frequency: frequency,
            bandwidth: bandwidth,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate,
            txPower: txPower,
            maxTxPower: maxTxPower,
            latitude: latitude,
            longitude: longitude,
            blePin: blePin,
            manualAddContacts: manualAddContacts,
            autoAddConfig: config,
            multiAcks: multiAcks,
            telemetryModeBase: telemetryModeBase,
            telemetryModeLoc: telemetryModeLoc,
            telemetryModeEnv: telemetryModeEnv,
            advertLocationPolicy: advertLocationPolicy,
            lastConnected: lastConnected,
            lastContactSync: lastContactSync,
            isActive: isActive,
            ocvPreset: ocvPreset,
            customOCVArrayString: customOCVArrayString,
            connectionMethods: connectionMethods
        )
    }
}

// MARK: - Extensions

public extension Device {
    /// Updates device from MeshCore.DeviceCapabilities response
    func update(from info: MeshCore.DeviceCapabilities) {
        self.firmwareVersion = info.firmwareVersion
        self.firmwareVersionString = info.version
        self.manufacturerName = info.model
        self.buildDate = info.firmwareBuild
        self.maxContacts = UInt8(min(info.maxContacts, 255))
        self.maxChannels = UInt8(min(info.maxChannels, 255))
        self.blePin = info.blePin
    }

    /// Updates device from MeshCore.SelfInfo response
    func update(from info: MeshCore.SelfInfo) {
        self.publicKey = info.publicKey
        self.nodeName = info.name
        self.txPower = info.txPower
        self.maxTxPower = info.maxTxPower
        self.latitude = info.latitude
        self.longitude = info.longitude
        self.frequency = UInt32(info.radioFrequency * 1000)  // Convert MHz to kHz
        self.bandwidth = UInt32(info.radioBandwidth * 1000)  // Convert MHz to kHz
        self.spreadingFactor = info.radioSpreadingFactor
        self.codingRate = info.radioCodingRate
        self.multiAcks = info.multiAcks
        self.advertLocationPolicy = info.advertisementLocationPolicy
        self.manualAddContacts = info.manualAddContacts
        self.telemetryModeBase = info.telemetryModeBase
        self.telemetryModeLoc = info.telemetryModeLocation
        self.telemetryModeEnv = info.telemetryModeEnvironment
    }

    /// The 6-byte public key prefix used for identifying messages
    var publicKeyPrefix: Data {
        publicKey.prefix(6)
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
