import Foundation
import os

// MARK: - Packet Size Constants

/// Named constants for packet size validation to avoid magic numbers.
enum PacketSize {
    /// Full contact structure size.
    static let contact = 147
    /// Minimum size for self info response.
    static let selfInfoMinimum = 55
    /// Minimum size for message sent confirmation.
    static let messageSentMinimum = 9
    /// Minimum size for version 1 contact messages.
    static let contactMessageV1Minimum = 12
    /// Minimum size for version 3 contact messages.
    static let contactMessageV3Minimum = 15
    /// Minimum size for version 1 channel messages.
    static let channelMessageV1Minimum = 8
    /// Minimum size for version 3 channel messages.
    static let channelMessageV3Minimum = 11
    /// Minimum size for private key export.
    static let privateKeyMinimum = 64
    /// Minimum size for basic battery info.
    static let batteryMinimum = 2
    /// Size for battery info with storage statistics.
    static let batteryExtended = 10
    /// Minimum size for signing session start.
    static let signStartMinimum = 5
    /// Full size for version 3 device info.
    static let deviceInfoV3Full = 79
    /// Minimum size for acknowledgement packets.
    static let ackMinimum = 4
    /// Minimum size for contact synchronization start.
    static let contactsStartMinimum = 4
    /// Minimum size for core system statistics.
    static let coreStatsMinimum = 9
    /// Minimum size for radio statistics.
    static let radioStatsMinimum = 12
    /// Minimum size for packet counters.
    static let packetStatsMinimum = 24
    /// Minimum size for channel configuration info.
    static let channelInfoMinimum = 49
    /// Minimum size for status response push notification.
    /// Format: `reserved(1) + pubkey(6) + fields(51) = 58 bytes`
    static let statusResponseMinimum = 58
    /// Minimum size for trace route data.
    static let traceDataMinimum = 11
    /// Minimum size for raw packet data.
    static let rawDataMinimum = 2
    /// Minimum size for control protocol data.
    static let controlDataMinimum = 4
    /// Minimum size for path discovery results.
    static let pathDiscoveryMinimum = 6
    /// Minimum size for login success response.
    /// Format: `[permissions:1][pubkeyPrefix:6]`
    static let loginSuccessMinimum = 7
    /// Size for binary response status payload without rxAirtime field (48 bytes).
    static let binaryResponseStatusBase = 48
    /// Minimum size for binary response status payload with rxAirtime field (52 bytes).
    static let binaryResponseStatusWithRxAirtime = 52
}

// MARK: - Parser Logger

private let parserLogger = Logger(subsystem: "MeshCore", category: "Parsers")

/// Namespace for complex protocol parsers.
///
/// This enum contains specialized parsers for various mesh protocol data structures.
/// Each sub-parser is responsible for validating the input data size and correctly
/// interpreting multi-byte fields (mostly little-endian).
enum Parsers {

    // MARK: - Contact

    /// Parser for mesh contact structures.
    enum Contact {
        /// Parses a 147-byte contact structure.
        ///
        /// - Parameter data: Raw contact data.
        /// - Returns: A `.contact` event or `.parseFailure`.
        ///
        /// ### Binary Format
        /// (Per Python reader.py)
        /// - Offset 0 (32 bytes): Public Key
        /// - Offset 32 (1 byte): Contact Type
        /// - Offset 33 (1 byte): Flags
        /// - Offset 34 (1 byte): Path Length (signed Int8)
        /// - Offset 35 (64 bytes): Routing Path
        /// - Offset 99 (32 bytes): Advertised Name (UTF-8, padded)
        /// - Offset 131 (4 bytes): Last Advertisement Time (UInt32 LE)
        /// - Offset 135 (4 bytes): Latitude scaled by 1e6 (Int32 LE)
        /// - Offset 139 (4 bytes): Longitude scaled by 1e6 (Int32 LE)
        /// - Offset 143 (4 bytes): Last Modified Time (UInt32 LE)
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.contact else {
                return .parseFailure(
                    data: data,
                    reason: "Contact response too short: \(data.count) < \(PacketSize.contact)"
                )
            }

            var offset = 0
            let publicKey = Data(data[offset..<offset+32]); offset += 32
            let type = data[offset]; offset += 1
            let flags = data[offset]; offset += 1
            let pathLen = Int8(bitPattern: data[offset]); offset += 1
            let actualPathLen = pathLen == -1 ? 0 : Int(pathLen)
            // Read full 64-byte path field, but only use first actualPathLen bytes
            let pathBytes = Data(data[offset..<offset+64])
            let path = actualPathLen > 0 ? Data(pathBytes.prefix(actualPathLen)) : Data()
            offset += 64
            let nameData = data[offset..<offset+32]
            let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters) ?? ""
            offset += 32
            let lastAdvert = Date(timeIntervalSince1970: TimeInterval(data.readUInt32LE(at: offset))); offset += 4
            let lat = Double(data.readInt32LE(at: offset)) / 1_000_000; offset += 4
            let lon = Double(data.readInt32LE(at: offset)) / 1_000_000; offset += 4
            let lastMod = Date(timeIntervalSince1970: TimeInterval(data.readUInt32LE(at: offset)))

            let contact = MeshContact(
                id: publicKey.hexString,
                publicKey: publicKey,
                type: type,
                flags: flags,
                outPathLength: pathLen,
                outPath: path,
                advertisedName: name,
                lastAdvertisement: lastAdvert,
                latitude: lat,
                longitude: lon,
                lastModified: lastMod
            )
            return .contact(contact)
        }
    }

    // MARK: - SelfInfo

    /// Parser for local device configuration info.
    enum SelfInfo {
        /// Parses self info response (55+ bytes).
        ///
        /// - Parameter data: Raw self info data.
        /// - Returns: A `.selfInfo` event or `.parseFailure`.
        ///
        /// ### Binary Format
        /// - Offset 0-2 (3 bytes): Adv type, Tx power, Max Tx power
        /// - Offset 3 (32 bytes): Public Key
        /// - Offset 35 (8 bytes): Lat/Lon scaled by 1e6 (Int32 LE)
        /// - Offset 43-45 (3 bytes): Multi-ACKs, Adv policy, Telemetry mode
        /// - Offset 46 (1 byte): Manual add contacts flag
        /// - Offset 47 (8 bytes): Radio Freq/BW scaled by 1000 (UInt32 LE)
        /// - Offset 55-56 (2 bytes): Spreading factor, Coding rate
        /// - Offset 57+ (N bytes): Local name (UTF-8)
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.selfInfoMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "SelfInfo response too short: \(data.count) < \(PacketSize.selfInfoMinimum)"
                )
            }

            var offset = 0
            let advType = data[offset]; offset += 1
            let txPower = data[offset]; offset += 1
            let maxTxPower = data[offset]; offset += 1
            let publicKey = Data(data[offset..<offset+32]); offset += 32
            let lat = Double(data.readInt32LE(at: offset)) / 1_000_000; offset += 4
            let lon = Double(data.readInt32LE(at: offset)) / 1_000_000; offset += 4
            let multiAcks = data[offset]; offset += 1
            let advLocPolicy = data[offset]; offset += 1
            let telemetryMode = data[offset]; offset += 1
            let manualAdd = data[offset] > 0; offset += 1
            let radioFreq = Double(data.readUInt32LE(at: offset)) / 1000; offset += 4
            let radioBW = Double(data.readUInt32LE(at: offset)) / 1000; offset += 4
            let radioSF = data[offset]; offset += 1
            let radioCR = data[offset]; offset += 1
            let name = String(data: data[offset...], encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters) ?? ""

            let info = MeshCore.SelfInfo(
                advertisementType: advType,
                txPower: txPower,
                maxTxPower: maxTxPower,
                publicKey: publicKey,
                latitude: lat,
                longitude: lon,
                multiAcks: multiAcks,
                advertisementLocationPolicy: advLocPolicy,
                telemetryModeEnvironment: (telemetryMode >> 4) & 0b11,
                telemetryModeLocation: (telemetryMode >> 2) & 0b11,
                telemetryModeBase: telemetryMode & 0b11,
                manualAddContacts: manualAdd,
                radioFrequency: radioFreq,
                radioBandwidth: radioBW,
                radioSpreadingFactor: radioSF,
                radioCodingRate: radioCR,
                name: name
            )
            return .selfInfo(info)
        }
    }

    // MARK: - DeviceInfo

    /// Parser for device capabilities and versioning.
    enum DeviceInfo {
        /// Parses device info with version-specific handling.
        ///
        /// - Parameter data: Raw device info data.
        /// - Returns: A `.deviceInfo` event.
        ///
        /// ### Binary Format (v3+)
        /// - Offset 0 (1 byte): Firmware version
        /// - Offset 1 (1 byte): Max contacts (stored as count/2)
        /// - Offset 2 (1 byte): Max channels
        /// - Offset 3 (4 bytes): BLE PIN (UInt32 LE)
        /// - Offset 7 (12 bytes): Firmware build string (UTF-8)
        /// - Offset 19 (40 bytes): Model string (UTF-8)
        /// - Offset 59 (20 bytes): Hardware version string (UTF-8)
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 1 else {
                return .parseFailure(data: data, reason: "DeviceInfo response empty")
            }

            let fwVer = data[0]
            var offset = 1
            var maxContacts: Int? = nil
            var maxChannels: Int? = nil
            var blePin: UInt32? = nil
            var fwBuild: String? = nil
            var model: String? = nil
            var version: String? = nil

            // v3+ format: fwBuild=12, model=40, version=20 bytes
            if fwVer >= 3 && data.count >= PacketSize.deviceInfoV3Full {
                maxContacts = Int(data[offset]) * 2  /// Stored as count/2 in firmware.
                offset += 1
                maxChannels = Int(data[offset])
                offset += 1
                blePin = data.readUInt32LE(at: offset)
                offset += 4
                let fwBuildData = data[offset..<offset+12]
                fwBuild = String(data: fwBuildData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
                offset += 12
                let modelData = data[offset..<offset+40]
                model = String(data: modelData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
                offset += 40
                let versionData = data[offset..<offset+20]
                version = String(data: versionData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
            }

            return .deviceInfo(DeviceCapabilities(
                firmwareVersion: fwVer,
                maxContacts: maxContacts ?? 0,
                maxChannels: maxChannels ?? 0,
                blePin: blePin ?? 0,
                firmwareBuild: fwBuild ?? "",
                model: model ?? "",
                version: version ?? ""
            ))
        }
    }

    // MARK: - ContactMessage

    /// Parser for incoming direct messages.
    enum ContactMessage {
        /// Supported protocol versions for message parsing.
        enum Version { case v1, v3 }

        /// Parses a contact message.
        ///
        /// - Parameters:
        ///   - data: Raw message data.
        ///   - version: Protocol version (v1 or v3).
        /// - Returns: A `.contactMessageReceived` event or `.parseFailure`.
        ///
        /// ### Binary Format (v3)
        /// - Offset 0 (1 byte): SNR scaled by 4 (Int8)
        /// - Offset 1 (2 bytes): Reserved
        /// - Offset 3 (6 bytes): Sender Public Key Prefix
        /// - Offset 9 (1 byte): Path Length
        /// - Offset 10 (1 byte): Text Type
        /// - Offset 11 (4 bytes): Sender Timestamp (UInt32 LE)
        /// - Offset 15+ (N bytes): Message payload (UTF-8)
        static func parse(_ data: Data, version: Version) -> MeshEvent {
            var offset = 0
            var snr: Double? = nil

            let minSize = version == .v3 ? PacketSize.contactMessageV3Minimum : PacketSize.contactMessageV1Minimum
            guard data.count >= minSize else {
                return .parseFailure(
                    data: data,
                    reason: "ContactMessage response too short: \(data.count) < \(minSize)"
                )
            }

            if version == .v3 {
                snr = Double(Int8(bitPattern: data[offset])) / 4.0
                offset += 1
                offset += 2 // reserved
            }

            let pubkeyPrefix = Data(data[offset..<offset+6]); offset += 6
            let pathLen = data[offset]; offset += 1
            let txtType = data[offset]; offset += 1
            let timestamp = Date(timeIntervalSince1970: TimeInterval(data.readUInt32LE(at: offset))); offset += 4

            var signature: Data? = nil
            if txtType == 2 && data.count >= offset + 4 {
                signature = Data(data[offset..<offset+4]); offset += 4
            }

            // Handle UTF-8 decoding with explicit failure logging
            let textData = Data(data[offset...])
            let text: String
            if let decoded = String(data: textData, encoding: .utf8) {
                text = decoded
            } else {
                parserLogger.warning("ContactMessage: Invalid UTF-8 in message payload, using lossy conversion")
                text = String(decoding: textData, as: UTF8.self)  // Replaces invalid sequences with replacement char
            }

            return .contactMessageReceived(MeshCore.ContactMessage(
                senderPublicKeyPrefix: pubkeyPrefix,
                pathLength: pathLen,
                textType: txtType,
                senderTimestamp: timestamp,
                signature: signature,
                text: text,
                snr: snr
            ))
        }
    }

    // MARK: - ChannelMessage

    /// Parser for incoming channel (broadcast) messages.
    enum ChannelMessage {
        /// Supported protocol versions for message parsing.
        enum Version { case v1, v3 }

        /// Parses a channel message.
        ///
        /// - Parameters:
        ///   - data: Raw message data.
        ///   - version: Protocol version.
        /// - Returns: A `.channelMessageReceived` event or `.parseFailure`.
        ///
        /// ### Binary Format (v3)
        /// - Offset 0 (1 byte): SNR scaled by 4 (Int8)
        /// - Offset 1 (2 bytes): Reserved
        /// - Offset 3 (1 byte): Channel Index
        /// - Offset 4 (1 byte): Path Length
        /// - Offset 5 (1 byte): Text Type
        /// - Offset 6 (4 bytes): Sender Timestamp (UInt32 LE)
        /// - Offset 10+ (N bytes): Message payload (UTF-8)
        static func parse(_ data: Data, version: Version) -> MeshEvent {
            var offset = 0
            var snr: Double? = nil

            let minSize = version == .v3 ? PacketSize.channelMessageV3Minimum : PacketSize.channelMessageV1Minimum
            guard data.count >= minSize else {
                return .parseFailure(
                    data: data,
                    reason: "ChannelMessage response too short: \(data.count) < \(minSize)"
                )
            }

            if version == .v3 {
                snr = Double(Int8(bitPattern: data[offset])) / 4.0
                offset += 1
                offset += 2 // reserved
            }

            let channelIndex = data[offset]; offset += 1
            let pathLen = data[offset]; offset += 1
            let txtType = data[offset]; offset += 1
            let timestamp = Date(timeIntervalSince1970: TimeInterval(data.readUInt32LE(at: offset))); offset += 4

            // Handle UTF-8 decoding
            let textData = Data(data[offset...])
            let text: String
            if let decoded = String(data: textData, encoding: .utf8) {
                text = decoded
            } else {
                parserLogger.warning("ChannelMessage: Invalid UTF-8 in message payload, using lossy conversion")
                text = String(decoding: textData, as: UTF8.self)
            }

            return .channelMessageReceived(MeshCore.ChannelMessage(
                channelIndex: channelIndex,
                pathLength: pathLen,
                textType: txtType,
                senderTimestamp: timestamp,
                text: text,
                snr: snr
            ))
        }
    }

    // MARK: - PrivateKey

    /// Parser for exported private key data.
    enum PrivateKey {
        /// Parses the 64-byte private key.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.privateKeyMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "PrivateKey response too short: \(data.count) < \(PacketSize.privateKeyMinimum)"
                )
            }
            return .privateKey(Data(data.prefix(PacketSize.privateKeyMinimum)))
        }
    }

    // MARK: - Advertisement

    /// Parser for node advertisement (beacon) data.
    enum Advertisement {
        /// Parses a 32-byte public key advertisement.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 32 else {
                return .parseFailure(data: data, reason: "Advertisement too short: \(data.count) < 32")
            }
            let publicKey = Data(data.prefix(32))
            return .advertisement(publicKey: publicKey)
        }
    }

    // MARK: - NewAdvertisement

    /// Parser for advertisements from previously unknown nodes.
    enum NewAdvertisement {
        /// Parses a new node advertisement.
        static func parse(_ data: Data) -> MeshEvent {
            // NewAdvertisement has same format as Advertisement but indicates a new contact
            // For now, parse as contact if we have full contact data, otherwise just extract key
            if data.count >= PacketSize.contact {
                return Contact.parse(data)
            } else if data.count >= 32 {
                return .advertisement(publicKey: Data(data.prefix(32)))
            }
            return .parseFailure(data: data, reason: "NewAdvertisement too short: \(data.count)")
        }
    }

    // MARK: - PathUpdate

    /// Parser for routing path update notifications.
    enum PathUpdate {
        /// Parses a 32-byte public key path update.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 32 else {
                return .parseFailure(data: data, reason: "PathUpdate too short: \(data.count) < 32")
            }
            let publicKey = Data(data.prefix(32))
            return .pathUpdate(publicKey: publicKey)
        }
    }

    // MARK: - StatusResponse

    /// Parser for remote node status reports.
    enum StatusResponse {
        /// Parses remote node status (58 bytes).
        ///
        /// ### Binary Format
        /// - Offset 0 (1 byte): Reserved (skipped)
        /// - Offset 1 (6 bytes): Public Key Prefix
        /// - Offset 7 (2 bytes): Battery level in mV (UInt16 LE)
        /// - Offset 9 (2 bytes): Tx queue length (UInt16 LE)
        /// - Offset 11 (2 bytes): Noise floor (Int16 LE)
        /// - Offset 13 (2 bytes): Last RSSI (Int16 LE)
        /// - Offset 15 (8 bytes): Total packets recv/sent (UInt32 LE)
        /// - Offset 23 (8 bytes): Airtime/Uptime in seconds (UInt32 LE)
        /// - Offset 31 (16 bytes): Stats for flood/direct comms (UInt32 LE)
        /// - Offset 47 (2 bytes): Full events counter
        /// - Offset 49 (2 bytes): Last SNR scaled by 4 (Int16 LE)
        /// - Offset 51 (4 bytes): Duplicate counters
        /// - Offset 55 (4 bytes): Receive airtime
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.statusResponseMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "StatusResponse too short: \(data.count) < \(PacketSize.statusResponseMinimum)"
                )
            }

            var offset = 0
            offset += 1  // Skip reserved byte (per firmware and Python parsing.py)
            let pubkeyPrefix = Data(data[offset..<offset+6]); offset += 6
            let battery = Int(data.readUInt16LE(at: offset)); offset += 2
            let txQueueLen = Int(data.readUInt16LE(at: offset)); offset += 2
            let noiseFloor = Int(data.readInt16LE(at: offset)); offset += 2
            let lastRSSI = Int(data.readInt16LE(at: offset)); offset += 2
            let packetsRecv = data.readUInt32LE(at: offset); offset += 4
            let packetsSent = data.readUInt32LE(at: offset); offset += 4
            let airtime = data.readUInt32LE(at: offset); offset += 4
            let uptime = data.readUInt32LE(at: offset); offset += 4
            let sentFlood = data.readUInt32LE(at: offset); offset += 4
            let sentDirect = data.readUInt32LE(at: offset); offset += 4
            let recvFlood = data.readUInt32LE(at: offset); offset += 4
            let recvDirect = data.readUInt32LE(at: offset); offset += 4
            let fullEvents = Int(data.readUInt16LE(at: offset)); offset += 2
            let lastSNR = Double(data.readInt16LE(at: offset)) / 4.0; offset += 2
            let directDups = Int(data.readUInt16LE(at: offset)); offset += 2
            let floodDups = Int(data.readUInt16LE(at: offset)); offset += 2
            let rxAirtime = data.readUInt32LE(at: offset)

            return .statusResponse(MeshCore.StatusResponse(
                publicKeyPrefix: pubkeyPrefix,
                battery: battery,
                txQueueLength: txQueueLen,
                noiseFloor: noiseFloor,
                lastRSSI: lastRSSI,
                packetsReceived: packetsRecv,
                packetsSent: packetsSent,
                airtime: airtime,
                uptime: uptime,
                sentFlood: sentFlood,
                sentDirect: sentDirect,
                receivedFlood: recvFlood,
                receivedDirect: recvDirect,
                fullEvents: fullEvents,
                lastSNR: lastSNR,
                directDuplicates: directDups,
                floodDuplicates: floodDups,
                rxAirtime: rxAirtime
            ))
        }

        /// Parses status data from a BINARY_RESPONSE (0x8C) payload.
        ///
        /// ### Binary Format (Format 2 - no pubkey header)
        /// Fields start at offset 0:
        /// - Offset 0 (2 bytes): Battery level in mV (UInt16 LE)
        /// - Offset 2 (2 bytes): Tx queue length (UInt16 LE)
        /// - Offset 4 (2 bytes): Noise floor (Int16 LE)
        /// - Offset 6 (2 bytes): Last RSSI (Int16 LE)
        /// - Offset 8 (4 bytes): Packets received (UInt32 LE)
        /// - Offset 12 (4 bytes): Packets sent (UInt32 LE)
        /// - Offset 16 (4 bytes): Airtime in seconds (UInt32 LE)
        /// - Offset 20 (4 bytes): Uptime in seconds (UInt32 LE)
        /// - Offset 24 (4 bytes): Sent flood (UInt32 LE)
        /// - Offset 28 (4 bytes): Sent direct (UInt32 LE)
        /// - Offset 32 (4 bytes): Received flood (UInt32 LE)
        /// - Offset 36 (4 bytes): Received direct (UInt32 LE)
        /// - Offset 40 (2 bytes): Full events counter (UInt16 LE)
        /// - Offset 42 (2 bytes): Last SNR scaled by 4 (Int16 LE)
        /// - Offset 44 (2 bytes): Direct duplicates (UInt16 LE)
        /// - Offset 46 (2 bytes): Flood duplicates (UInt16 LE)
        /// - Offset 48 (4 bytes): Rx airtime (UInt32 LE, optional)
        ///
        /// - Parameters:
        ///   - data: Raw binary response payload (without the 4-byte tag).
        ///   - publicKeyPrefix: The 6-byte public key prefix from the pending request context.
        /// - Returns: A `StatusResponse` if parsing succeeds, `nil` otherwise.
        static func parseFromBinaryResponse(_ data: Data, publicKeyPrefix: Data) -> MeshCore.StatusResponse? {
            // Accept exactly 48 bytes (no rxAirtime) or 52+ bytes (with rxAirtime)
            // Reject malformed payloads with incomplete rxAirtime field
            guard data.count == PacketSize.binaryResponseStatusBase ||
                  data.count >= PacketSize.binaryResponseStatusWithRxAirtime else { return nil }

            var offset = 0
            let battery = Int(data.readUInt16LE(at: offset)); offset += 2
            let txQueueLen = Int(data.readUInt16LE(at: offset)); offset += 2
            let noiseFloor = Int(data.readInt16LE(at: offset)); offset += 2
            let lastRSSI = Int(data.readInt16LE(at: offset)); offset += 2
            let packetsRecv = data.readUInt32LE(at: offset); offset += 4
            let packetsSent = data.readUInt32LE(at: offset); offset += 4
            let airtime = data.readUInt32LE(at: offset); offset += 4
            let uptime = data.readUInt32LE(at: offset); offset += 4
            let sentFlood = data.readUInt32LE(at: offset); offset += 4
            let sentDirect = data.readUInt32LE(at: offset); offset += 4
            let recvFlood = data.readUInt32LE(at: offset); offset += 4
            let recvDirect = data.readUInt32LE(at: offset); offset += 4
            let fullEvents = Int(data.readUInt16LE(at: offset)); offset += 2
            let lastSNR = Double(data.readInt16LE(at: offset)) / 4.0; offset += 2
            let directDups = Int(data.readUInt16LE(at: offset)); offset += 2
            let floodDups = Int(data.readUInt16LE(at: offset)); offset += 2
            let rxAirtime = data.count >= PacketSize.binaryResponseStatusWithRxAirtime ? data.readUInt32LE(at: offset) : 0

            return MeshCore.StatusResponse(
                publicKeyPrefix: publicKeyPrefix,
                battery: battery,
                txQueueLength: txQueueLen,
                noiseFloor: noiseFloor,
                lastRSSI: lastRSSI,
                packetsReceived: packetsRecv,
                packetsSent: packetsSent,
                airtime: airtime,
                uptime: uptime,
                sentFlood: sentFlood,
                sentDirect: sentDirect,
                receivedFlood: recvFlood,
                receivedDirect: recvDirect,
                fullEvents: fullEvents,
                lastSNR: lastSNR,
                directDuplicates: directDups,
                floodDuplicates: floodDups,
                rxAirtime: rxAirtime
            )
        }
    }

    // MARK: - TelemetryResponse

    /// Parser for remote sensor telemetry.
    enum TelemetryResponse {
        /// Parses telemetry data.
        ///
        /// Format: `pubkey_prefix[6] + optional_tag[4] + raw_lpp_payload[N]`
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 6 else {
                return .parseFailure(data: data, reason: "TelemetryResponse too short")
            }
            let pubkeyPrefix = Data(data.prefix(6))
            let tag: Data? = data.count >= 10 ? Data(data[6..<10]) : nil
            let rawData = Data(data.dropFirst(tag != nil ? 10 : 6))

            return .telemetryResponse(MeshCore.TelemetryResponse(
                publicKeyPrefix: pubkeyPrefix,
                tag: tag,
                rawData: rawData
            ))
        }

        /// Parses telemetry data from a BINARY_RESPONSE (0x8C) payload.
        ///
        /// ### Binary Format (Format 2 - no pubkey header)
        /// Raw LPP data starts at offset 0.
        ///
        /// - Parameters:
        ///   - data: Raw binary response payload (without the 4-byte tag).
        ///   - publicKeyPrefix: The 6-byte public key prefix from the pending request context.
        /// - Returns: A `TelemetryResponse` with the raw data for LPP decoding.
        static func parseFromBinaryResponse(_ data: Data, publicKeyPrefix: Data) -> MeshCore.TelemetryResponse {
            MeshCore.TelemetryResponse(
                publicKeyPrefix: publicKeyPrefix,
                tag: nil,
                rawData: data
            )
        }
    }

    // MARK: - BinaryResponse

    /// Parser for generic binary protocol responses.
    enum BinaryResponse {
        /// Parses a generic binary response.
        ///
        /// - Parameter data: Raw response data.
        /// - Returns: A `.binaryResponse` event.
        ///
        /// Note: This returns a generic `.binaryResponse` event. The caller should
        /// use specialized parsers (like ``ACLParser`` or ``MMAParser``) to decode
        /// the `responseData` based on the request context.
        static func parse(_ data: Data) -> MeshEvent {
            // Binary response format:
            // - Byte 0: Request type (unused, skip)
            // - Bytes 1-4: Tag (matches expectedAck from messageSent)
            // - Bytes 5+: Response data
            guard data.count >= 5 else {
                return .parseFailure(data: data, reason: "BinaryResponse too short: \(data.count) < 5")
            }
            let tag = Data(data[1..<5])
            let responseData = Data(data.dropFirst(5))
            return .binaryResponse(tag: tag, data: responseData)
        }
    }

    // MARK: - PathDiscoveryResponse

    /// Parser for path discovery results.
    enum PathDiscoveryResponse {
        /// Parses path info including out-bound and in-bound mesh routes.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.pathDiscoveryMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "PathDiscoveryResponse too short: \(data.count) < \(PacketSize.pathDiscoveryMinimum)"
                )
            }
            let pubkeyPrefix = Data(data.prefix(6))
            // Parse out and in paths if present
            var offset = 6
            var outPath = Data()
            var inPath = Data()
            if data.count > offset {
                let pathLen = Int(data[offset]); offset += 1
                if pathLen > 0 && data.count >= offset + pathLen {
                    outPath = Data(data[offset..<offset+pathLen]); offset += pathLen
                }
            }
            if data.count > offset {
                let pathLen = Int(data[offset]); offset += 1
                if pathLen > 0 && data.count >= offset + pathLen {
                    inPath = Data(data[offset..<offset+pathLen])
                }
            }
            return .pathResponse(PathInfo(
                publicKeyPrefix: pubkeyPrefix,
                outPath: outPath,
                inPath: inPath
            ))
        }
    }

    // MARK: - ControlData

    /// Parser for low-level protocol control data.
    enum ControlData {
        /// Parses SNR, RSSI, and payload from a control packet.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.controlDataMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "ControlData too short: \(data.count) < \(PacketSize.controlDataMinimum)"
                )
            }
            let snr = Double(Int8(bitPattern: data[0])) / 4.0
            let rssi = Int(Int8(bitPattern: data[1]))
            let pathLen = data[2]
            let payloadType = data[3]
            let payload = Data(data.dropFirst(4))

            return .controlData(ControlDataInfo(
                snr: snr,
                rssi: rssi,
                pathLength: pathLen,
                payloadType: payloadType,
                payload: payload
            ))
        }
    }

    // MARK: - Signature

    /// Parser for cryptographic signature responses.
    enum Signature {
        /// Wraps the signature data in a `.signature` event.
        static func parse(_ data: Data) -> MeshEvent {
            return .signature(data)
        }
    }

    // MARK: - CoreStats

    /// Parser for core system statistics.
    enum CoreStats {
        /// Parses battery, uptime, errors, and queue length.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.coreStatsMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "CoreStats too short: \(data.count) < \(PacketSize.coreStatsMinimum)"
                )
            }
            let batteryMV = data.readUInt16LE(at: 0)
            let uptime = data.readUInt32LE(at: 2)
            let errors = data.readUInt16LE(at: 6)
            let queueLen = data[8]

            return .statsCore(MeshCore.CoreStats(
                batteryMV: batteryMV,
                uptimeSeconds: uptime,
                errors: errors,
                queueLength: queueLen
            ))
        }
    }

    // MARK: - RadioStats

    /// Parser for radio performance statistics.
    enum RadioStats {
        /// Parses noise floor, SNR, and radio airtime.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.radioStatsMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "RadioStats too short: \(data.count) < \(PacketSize.radioStatsMinimum)"
                )
            }
            let noiseFloor = data.readInt16LE(at: 0)
            let lastRSSI = Int8(bitPattern: data[2])
            let lastSNR = Double(Int8(bitPattern: data[3])) / 4.0
            let txAir = data.readUInt32LE(at: 4)
            let rxAir = data.readUInt32LE(at: 8)

            return .statsRadio(MeshCore.RadioStats(
                noiseFloor: noiseFloor,
                lastRSSI: lastRSSI,
                lastSNR: lastSNR,
                txAirtimeSeconds: txAir,
                rxAirtimeSeconds: rxAir
            ))
        }
    }

    // MARK: - PacketStats

    /// Parser for packet counters.
    enum PacketStats {
        /// Parses total sent/received and flood/direct packet counts.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.packetStatsMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "PacketStats too short: \(data.count) < \(PacketSize.packetStatsMinimum)"
                )
            }
            return .statsPackets(MeshCore.PacketStats(
                received: data.readUInt32LE(at: 0),
                sent: data.readUInt32LE(at: 4),
                floodTx: data.readUInt32LE(at: 8),
                directTx: data.readUInt32LE(at: 12),
                floodRx: data.readUInt32LE(at: 16),
                directRx: data.readUInt32LE(at: 20)
            ))
        }
    }

    // MARK: - ChannelInfo

    /// Parser for channel configuration data.
    enum ChannelInfo {
        /// Parses channel index, name, and PSK secret.
        ///
        /// The channel name is a null-terminated C string in a 32-byte buffer.
        /// Bytes after the null terminator may be uninitialized garbage from the firmware,
        /// so we must find the null and decode only the bytes before it.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.channelInfoMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "ChannelInfo too short: \(data.count) < \(PacketSize.channelInfoMinimum)"
                )
            }
            let index = data[0]
            let nameData = data[1..<33]

            // Find first null byte - firmware uses strcpy which leaves garbage after the null
            let nullIndex = nameData.firstIndex(of: 0) ?? nameData.endIndex
            let validNameData = nameData[nameData.startIndex..<nullIndex]
            let name = String(data: validNameData, encoding: .utf8) ?? ""

            let secret = Data(data[33..<49])

            return .channelInfo(MeshCore.ChannelInfo(
                index: index,
                name: name,
                secret: secret
            ))
        }
    }

    // MARK: - CustomVars

    /// Parser for user-defined custom variables.
    enum CustomVars {
        /// Parses custom vars from a comma-separated key:value string.
        ///
        /// Format: `key1:value1,key2:value2,...`
        static func parse(_ data: Data) -> MeshEvent {
            var vars: [String: String] = [:]

            guard let rawString = String(data: data, encoding: .utf8),
                  !rawString.isEmpty else {
                return .customVars(vars)
            }

            let pairs = rawString.split(separator: ",")
            for pair in pairs {
                let parts = pair.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let value = String(parts[1])
                    vars[key] = value
                }
            }
            return .customVars(vars)
        }
    }

    // MARK: - TraceData

    /// Parser for full trace route results.
    enum TraceData {
        /// Parses detailed trace info including hop hashes and per-hop SNR.
        ///
        /// ### Binary Format
        /// (Per Python reader.py)
        /// `[reserved(1)][path_len(1)][flags(1)][tag(4)][auth(4)][path_hashes...][path_snrs...][final_snr]`
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.traceDataMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "TraceData too short: \(data.count) < \(PacketSize.traceDataMinimum)"
                )
            }

            let pathLength = data[1]
            let flags = data[2]
            let tag = data.readUInt32LE(at: 3)
            let authCode = data.readUInt32LE(at: 7)

            var path: [TraceNode] = []
            let pathStartOffset = 11

            if pathLength > 0 && data.count >= pathStartOffset + Int(pathLength) * 2 + 1 {
                for i in 0..<Int(pathLength) {
                    let hashOffset = pathStartOffset + i
                    let snrOffset = pathStartOffset + Int(pathLength) + i
                    guard hashOffset < data.count && snrOffset < data.count else { break }

                    let hash: UInt8? = data[hashOffset] == 0xFF ? nil : data[hashOffset]
                    let snr = Double(Int8(bitPattern: data[snrOffset])) / 4.0
                    path.append(TraceNode(hash: hash, snr: snr))
                }

                let finalSnrOffset = pathStartOffset + Int(pathLength) * 2
                if finalSnrOffset < data.count {
                    let finalSnr = Double(Int8(bitPattern: data[finalSnrOffset])) / 4.0
                    path.append(TraceNode(hash: nil, snr: finalSnr))
                }
            }

            return .traceData(TraceInfo(
                tag: tag,
                authCode: authCode,
                flags: flags,
                pathLength: pathLength,
                path: path
            ))
        }
    }

    // MARK: - RawData

    /// Parser for generic raw packet notifications.
    enum RawData {
        /// Parses SNR and RSSI for a raw packet.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.rawDataMinimum else {
                return .parseFailure(data: data, reason: "RawData too short")
            }
            let snr = Double(Int8(bitPattern: data[0])) / 4.0
            let rssi = Int(Int8(bitPattern: data[1]))
            let payload = Data(data.dropFirst(2))

            return .rawData(RawDataInfo(snr: snr, rssi: rssi, payload: payload))
        }
    }

    // MARK: - LogData

    /// Parser for remote debug log entries.
    enum LogData {
        /// Parses log messages with optional signal metadata.
        static func parse(_ data: Data) -> MeshEvent {
            if data.count >= 2 {
                let snr = Double(Int8(bitPattern: data[0])) / 4.0
                let rssi = Int(Int8(bitPattern: data[1]))
                let payload = Data(data.dropFirst(2))
                return .rxLogData(LogDataInfo(snr: snr, rssi: rssi, payload: payload))
            }
            return .rxLogData(LogDataInfo(snr: nil, rssi: nil, payload: data))
        }
    }

    // MARK: - LoginSuccess

    /// Parser for successful login responses.
    enum LoginSuccess {
        /// Parses permissions and admin status.
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.loginSuccessMinimum else {
                return .loginSuccess(LoginInfo(permissions: 0, isAdmin: false, publicKeyPrefix: Data()))
            }
            let permissions = data[0]
            let isAdmin = (permissions & 0x01) != 0
            let pubkeyPrefix = Data(data[1..<7])
            return .loginSuccess(LoginInfo(
                permissions: permissions,
                isAdmin: isAdmin,
                publicKeyPrefix: pubkeyPrefix
            ))
        }
    }
}

// MARK: - ACL Parser

/// Specialized parser for Access Control List data.
enum ACLParser {
    /// Parses ACL entries from binary protocol data.
    ///
    /// - Parameter data: Raw ACL data.
    /// - Returns: An array of ``ACLEntry`` structs.
    ///
    /// ### Binary Format
    /// (Per entry): `[pubkey_prefix:6][permissions:1]` (7 bytes total)
    static func parse(_ data: Data) -> [ACLEntry] {
        var entries: [ACLEntry] = []
        var offset = 0

        while offset + 7 <= data.count {
            let keyPrefix = Data(data[offset..<offset+6])
            let permissions = data[offset + 6]
            offset += 7

            // Skip null entries (all zeros)
            if keyPrefix.allSatisfy({ $0 == 0 }) {
                continue
            }

            entries.append(ACLEntry(keyPrefix: keyPrefix, permissions: permissions))
        }

        return entries
    }
}

// MARK: - MMA Parser

/// Specialized parser for MMA (Min/Max/Average) sensor data.
enum MMAParser {
    /// Parses MMA entries from binary protocol data.
    ///
    /// - Parameter data: Raw MMA data.
    /// - Returns: An array of ``MMAEntry`` structs.
    ///
    /// ### Binary Format
    /// `[channel:1][type:1][min:N][max:N][avg:N]`... where N is sensor data size.
    ///
    /// LPP sensor values use **Big-Endian** byte order.
    static func parse(_ data: Data) -> [MMAEntry] {
        var entries: [MMAEntry] = []
        var offset = 0

        while offset < data.count {
            guard offset + 2 <= data.count else { break }

            let channel = data[offset]
            let typeCode = data[offset + 1]
            offset += 2

            guard let sensorType = LPPSensorType(rawValue: typeCode) else { break }

            let valueSize = sensorType.dataSize
            guard offset + valueSize * 3 <= data.count else { break }

            let minData = data.subdata(in: offset..<(offset + valueSize))
            offset += valueSize
            let maxData = data.subdata(in: offset..<(offset + valueSize))
            offset += valueSize
            let avgData = data.subdata(in: offset..<(offset + valueSize))
            offset += valueSize

            let minValue = decodeToDouble(type: sensorType, data: minData)
            let maxValue = decodeToDouble(type: sensorType, data: maxData)
            let avgValue = decodeToDouble(type: sensorType, data: avgData)

            entries.append(MMAEntry(
                channel: channel,
                type: sensorType.name,
                min: minValue,
                max: maxValue,
                avg: avgValue
            ))
        }

        return entries
    }

    /// Decodes an LPP value to a double for MMA entries.
    ///
    /// - Parameters:
    ///   - type: The sensor type.
    ///   - data: Raw sensor data (Big-Endian).
    /// - Returns: Decoded floating point value.
    private static func decodeToDouble(type: LPPSensorType, data: Data) -> Double {
        switch type {
        case .digitalInput, .digitalOutput, .presence, .switchValue:
            return Double(data[0])
        case .percentage:
            return Double(data[0])
        case .humidity:
            return Double(data[0]) * 0.5
        case .temperature:
            return Double(readInt16BE(data)) / 10.0
        case .barometer:
            return Double(readUInt16BE(data)) / 10.0
        case .voltage:
            return Double(readUInt16BE(data)) / 100.0
        case .current:
            return Double(readUInt16BE(data)) / 1000.0
        case .illuminance, .concentration, .power, .direction:
            return Double(readUInt16BE(data))
        case .altitude:
            return Double(readInt16BE(data))
        case .load:
            return Double(readUInt16BE(data)) / 100.0
        case .analogInput, .analogOutput:
            return Double(readInt16BE(data)) / 100.0
        case .genericSensor:
            return Double(readInt32BE(data))
        case .frequency:
            return Double(readUInt32BE(data))
        case .distance, .energy:
            return Double(readUInt32BE(data)) / 1000.0
        case .unixTime:
            return Double(readUInt32BE(data))
        case .accelerometer, .gyrometer, .colour, .gps:
            // Complex types - return first component only for MMA
            return Double(readInt16BE(data)) / (type == .accelerometer ? 1000.0 : 100.0)
        }
    }

    /// Reads a 16-bit signed integer (Big-Endian).
    private static func readInt16BE(_ data: Data, offset: Int = 0) -> Int16 {
        guard offset + 2 <= data.count else { return 0 }
        return Int16(data[offset]) << 8 | Int16(data[offset + 1])
    }

    /// Reads a 16-bit unsigned integer (Big-Endian).
    private static func readUInt16BE(_ data: Data, offset: Int = 0) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    /// Reads a 32-bit signed integer (Big-Endian).
    private static func readInt32BE(_ data: Data, offset: Int = 0) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        return Int32(data[offset]) << 24 | Int32(data[offset + 1]) << 16
             | Int32(data[offset + 2]) << 8 | Int32(data[offset + 3])
    }

    /// Reads a 32-bit unsigned integer (Big-Endian).
    private static func readUInt32BE(_ data: Data, offset: Int = 0) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
             | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}

// MARK: - Neighbours Parser

/// Specialized parser for remote node neighbour lists.
enum NeighboursParser {
    /// Parses Neighbours response data from binary protocol.
    ///
    /// - Parameters:
    ///   - data: Raw response data.
    ///   - publicKeyPrefix: Target node's public key prefix.
    ///   - tag: Request tag.
    ///   - prefixLength: Expected length of neighbour pubkey prefixes (default 4).
    /// - Returns: A ``NeighboursResponse`` containing the parsed list.
    ///
    /// ### Binary Format
    /// - Offset 0 (2 bytes): Total neighbours count (Int16 LE)
    /// - Offset 2 (2 bytes): Results count in this response (Int16 LE)
    /// - Entries: `[prefix:N][secs_ago:4][snr:1]` where N = `prefixLength`.
    static func parse(
        _ data: Data,
        publicKeyPrefix: Data,
        tag: Data,
        prefixLength: Int = 4
    ) -> NeighboursResponse {
        guard data.count >= 4 else {
            return NeighboursResponse(
                publicKeyPrefix: publicKeyPrefix,
                tag: tag,
                totalCount: 0,
                neighbours: []
            )
        }

        let totalCount = Int(data.readInt16LE(at: 0))
        let resultsCount = Int(data.readInt16LE(at: 2))

        var neighbours: [Neighbour] = []
        let entrySize = prefixLength + 4 + 1 // pubkey + secs_ago + snr
        var offset = 4

        for _ in 0..<resultsCount {
            guard offset + entrySize <= data.count else { break }

            let keyPrefix = Data(data[offset..<(offset + prefixLength)])
            offset += prefixLength

            let secondsAgo = Int(data.readInt32LE(at: offset))
            offset += 4

            let snr = Double(Int8(bitPattern: data[offset])) / 4.0
            offset += 1

            neighbours.append(Neighbour(
                publicKeyPrefix: keyPrefix,
                secondsAgo: secondsAgo,
                snr: snr
            ))
        }

        return NeighboursResponse(
            publicKeyPrefix: publicKeyPrefix,
            tag: tag,
            totalCount: totalCount,
            neighbours: neighbours
        )
    }
}
