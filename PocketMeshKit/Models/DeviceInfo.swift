import Foundation

/// Matches MyMesh.cpp:815-828 (79 bytes exact).
/// Firmware reference: MeshCore-firmware-examples/companion_radio/MyMesh.cpp#L815
public struct DeviceInfo: Codable, Sendable {
    public let firmwareVersionCode: UInt8 // firmware_ver_code
    public let maxContacts: UInt8 // max_contacts/2
    public let maxGroupChannels: UInt8 // max_group_channels
    public let blePin: UInt32 // ble_pin (4 bytes)
    public let buildDate: String // build_date:12 bytes, null-terminated (offset 7-18)
    public let manufacturer: String // manufacturer:40 bytes, null-terminated (offset 19-58)
    public let firmwareVersion: String // firmware_version:20 bytes, null-terminated (offset 59-78)

    public init(firmwareVersionCode: UInt8, maxContacts: UInt8, maxGroupChannels: UInt8,
                blePin: UInt32, buildDate: String, manufacturer: String, firmwareVersion: String)
    {
        self.firmwareVersionCode = firmwareVersionCode
        self.maxContacts = maxContacts
        self.maxGroupChannels = maxGroupChannels
        self.blePin = blePin
        self.buildDate = buildDate
        self.manufacturer = manufacturer
        self.firmwareVersion = firmwareVersion
    }

    public static func decode(from payload: Data) throws -> DeviceInfo {
        guard payload.count >= 79 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid DeviceInfo payload length: minimum 79 bytes required"))
        }

        let firmwareVersionCode = payload[0]
        let maxContacts = payload[1]
        let maxGroupChannels = payload[2]
        let blePin = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 3, as: UInt32.self) }

        // Firmware layout: offsets 7-18 (12B), 19-58 (40B), 59-78 (20B)
        let buildDate = String(data: payload[7 ..< 19], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let manufacturer = String(data: payload[19 ..< 59], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let firmwareVersion = String(data: payload[59 ..< 79], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

        return DeviceInfo(
            firmwareVersionCode: firmwareVersionCode,
            maxContacts: maxContacts,
            maxGroupChannels: maxGroupChannels,
            blePin: blePin,
            buildDate: buildDate,
            manufacturer: manufacturer,
            firmwareVersion: firmwareVersion,
        )
    }

    /// Default test configuration for DeviceInfo
    public static let `default` = DeviceInfo(
        firmwareVersionCode: 8, // FIRMWARE_VER_CODE [MyMesh.h:8]
        maxContacts: 50, // MAX_CONTACTS/2 = 100/2 = 50
        maxGroupChannels: 8, // MAX_GROUP_CHANNELS = 8
        blePin: 0, // No PIN by default
        buildDate: "13 Nov 2025", // FIRMWARE_BUILD_DATE [MyMesh.h:11]
        manufacturer: "PocketMesh", // board.getManufacturerName()
        firmwareVersion: "v1.10.0", // FIRMWARE_VERSION [MyMesh.h:15]
    )
}
