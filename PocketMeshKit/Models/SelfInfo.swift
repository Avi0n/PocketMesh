import Foundation

public struct SelfInfo: Codable, Sendable {
    public let advertisementType: UInt8 // adv_type
    public let txPower: Int8 // tx_power
    public let maxTxPower: Int8 // max_tx_power
    public let publicKey: Data // pub_key:32 bytes
    public let latitude: Int32 // lat:4 (scaled by 1,000,000)
    public let longitude: Int32 // lon:4 (scaled by 1,000,000)
    public let multiAcks: UInt8 // multi_acks
    public let advertLocationPolicy: UInt8 // advert_loc_policy
    public let telemetryModes: UInt8 // telemetry_modes (bitfield)
    public let manualAddContacts: UInt8 // manual_add
    public let frequency: UInt32 // freq:4 (in Hz)
    public let bandwidth: UInt32 // bw:4 (in Hz)
    public let spreadingFactor: UInt8 // sf
    public let codingRate: UInt8 // cr
    public let nodeName: String // node_name (null-terminated, variable length)

    // Computed properties for backward compatibility with existing code
    public var radioFrequency: UInt32 { frequency }
    public var radioBandwidth: UInt32 { bandwidth }
    public var radioSpreadingFactor: UInt8 { spreadingFactor }
    public var radioCodingRate: UInt8 { codingRate }

    // Computed properties for coordinate conversion
    public var latitudeDouble: Double { Double(latitude) / 1_000_000.0 }
    public var longitudeDouble: Double { Double(longitude) / 1_000_000.0 }

    public init(advertisementType: UInt8, txPower: Int8, maxTxPower: Int8, publicKey: Data,
                latitude: Int32, longitude: Int32, multiAcks: UInt8, advertLocationPolicy: UInt8,
                telemetryModes: UInt8, manualAddContacts: UInt8, frequency: UInt32, bandwidth: UInt32,
                spreadingFactor: UInt8, codingRate: UInt8, nodeName: String)
    {
        self.advertisementType = advertisementType
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.publicKey = publicKey
        self.latitude = latitude
        self.longitude = longitude
        self.multiAcks = multiAcks
        self.advertLocationPolicy = advertLocationPolicy
        self.telemetryModes = telemetryModes
        self.manualAddContacts = manualAddContacts
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.nodeName = nodeName
    }

    public static func decode(from payload: Data) throws -> SelfInfo {
        guard payload.count >= 59 else { // Minimum size without nodeName
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid SelfInfo payload length"))
        }

        let advertisementType = payload[0]
        let txPower = Int8(bitPattern: payload[1])
        let maxTxPower = Int8(bitPattern: payload[2])
        let publicKey = Data(payload[3 ..< 35]) // 32 bytes
        let latitude = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 35, as: Int32.self) }
        let longitude = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 39, as: Int32.self) }
        let multiAcks = payload[43]
        let advertLocationPolicy = payload[44]
        let telemetryModes = payload[45]
        let manualAddContacts = payload[46]
        let frequency = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 47, as: UInt32.self) }
        let bandwidth = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 51, as: UInt32.self) }
        let spreadingFactor = payload[55]
        let codingRate = payload[56]
        let nodeName = String(data: Data(payload[57...]), encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

        return SelfInfo(advertisementType: advertisementType, txPower: txPower, maxTxPower: maxTxPower,
                        publicKey: publicKey, latitude: latitude, longitude: longitude, multiAcks: multiAcks,
                        advertLocationPolicy: advertLocationPolicy, telemetryModes: telemetryModes,
                        manualAddContacts: manualAddContacts, frequency: frequency, bandwidth: bandwidth,
                        spreadingFactor: spreadingFactor, codingRate: codingRate, nodeName: nodeName)
    }

    /// Default test configuration for SelfInfo
    public static let `default` = SelfInfo(
        advertisementType: 0, // adv_type: none
        txPower: 20, // 20 dBm
        maxTxPower: 30, // 30 dBm max
        publicKey: Data(repeating: 0x01, count: 32), // Expected test public key
        latitude: 37_774_900, // San Francisco latitude * 1E6
        longitude: -122_419_400, // San Francisco longitude * 1E6
        multiAcks: 1, // Enable multi-acks
        advertLocationPolicy: 1, // Include location in adverts
        telemetryModes: 1, // Enable telemetry
        manualAddContacts: 0, // No manual contact additions
        frequency: 915_000_000, // 915 MHz
        bandwidth: 125_000, // 125 kHz
        spreadingFactor: 7, // SF7
        codingRate: 5, // 4/5 coding rate
        nodeName: "TestNode", // Test node name
    )
}
