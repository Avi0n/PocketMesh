import Foundation
import os

// MARK: - Packet Size Constants

/// Named constants for packet size validation (avoids magic numbers)
enum PacketSize {
    static let contact = 147
    static let selfInfoMinimum = 55
    static let messageSentMinimum = 9
    static let contactMessageV1Minimum = 12
    static let contactMessageV3Minimum = 15
    static let channelMessageV1Minimum = 8
    static let channelMessageV3Minimum = 11
    static let privateKeyMinimum = 64
    static let batteryMinimum = 2
    static let batteryExtended = 10
    static let signStartMinimum = 5
    static let deviceInfoV3Full = 79
    static let ackMinimum = 4
    static let contactsStartMinimum = 4
    static let coreStatsMinimum = 9
    static let radioStatsMinimum = 12
    static let packetStatsMinimum = 24
    static let channelInfoMinimum = 49
    static let statusResponseMinimum = 58
    static let traceDataMinimum = 11
    static let rawDataMinimum = 2
    static let controlDataMinimum = 4
    static let pathDiscoveryMinimum = 6
    static let loginSuccessMinimum = 8
}

// MARK: - Parser Logger

private let parserLogger = Logger(subsystem: "MeshCore", category: "Parsers")

/// Namespace for complex parsers that need direct unit testing
/// Internal visibility allows @testable import access
enum Parsers {

    // MARK: - Contact

    enum Contact {
        /// Parses a 147-byte contact structure
        /// Per Python reader.py: 32 (pubkey) + 1 (type) + 1 (flags) + 1 (path_len) + 64 (path) +
        /// 32 (name) + 4 (last_advert) + 4 (lat) + 4 (lon) + 4 (lastmod) = 147 bytes
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

    enum SelfInfo {
        /// Parses self info response (55+ bytes)
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

    enum DeviceInfo {
        /// Parses device info with version-specific handling
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
                maxContacts = Int(data[offset]) * 2  // Note: multiplied by 2
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

    enum ContactMessage {
        enum Version { case v1, v3 }

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

    enum ChannelMessage {
        enum Version { case v1, v3 }

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

    enum PrivateKey {
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

    enum Advertisement {
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 32 else {
                return .parseFailure(data: data, reason: "Advertisement too short: \(data.count) < 32")
            }
            let publicKey = Data(data.prefix(32))
            return .advertisement(publicKey: publicKey)
        }
    }

    // MARK: - NewAdvertisement

    enum NewAdvertisement {
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

    enum PathUpdate {
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 32 else {
                return .parseFailure(data: data, reason: "PathUpdate too short: \(data.count) < 32")
            }
            let publicKey = Data(data.prefix(32))
            return .pathUpdate(publicKey: publicKey)
        }
    }

    // MARK: - StatusResponse

    enum StatusResponse {
        /// Per Python parsing.py: StatusResponse uses 2-byte fields for several values
        /// Format (58 bytes total): pubkey(6) + bat(2) + tx_queue(2) + noise(2) + rssi(2) +
        /// recv(4) + sent(4) + airtime(4) + uptime(4) + flood_tx(4) + direct_tx(4) +
        /// flood_rx(4) + direct_rx(4) + full_evts(2) + snr(2) + direct_dups(2) + flood_dups(2) + rx_air(4)
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.statusResponseMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "StatusResponse too short: \(data.count) < \(PacketSize.statusResponseMinimum)"
                )
            }

            var offset = 0
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
    }

    // MARK: - TelemetryResponse

    enum TelemetryResponse {
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
    }

    // MARK: - BinaryResponse

    enum BinaryResponse {
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= 4 else {
                return .parseFailure(data: data, reason: "BinaryResponse too short")
            }
            let tag = Data(data.prefix(4))
            let responseData = Data(data.dropFirst(4))
            return .binaryResponse(tag: tag, data: responseData)
        }
    }

    // MARK: - PathDiscoveryResponse

    enum PathDiscoveryResponse {
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

    enum ControlData {
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

    enum Signature {
        static func parse(_ data: Data) -> MeshEvent {
            return .signature(data)
        }
    }

    // MARK: - CoreStats

    enum CoreStats {
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

    enum RadioStats {
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

    enum PacketStats {
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

    enum ChannelInfo {
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.channelInfoMinimum else {
                return .parseFailure(
                    data: data,
                    reason: "ChannelInfo too short: \(data.count) < \(PacketSize.channelInfoMinimum)"
                )
            }
            let index = data[0]
            let nameData = data[1..<33]
            let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters) ?? ""
            let secret = Data(data[33..<49])

            return .channelInfo(MeshCore.ChannelInfo(
                index: index,
                name: name,
                secret: secret
            ))
        }
    }

    // MARK: - CustomVars

    enum CustomVars {
        /// Parses custom vars response
        /// Per Python reader.py:282-291: comma-separated key:value pairs as UTF-8 text
        /// Format: "key1:value1,key2:value2,..."
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

    enum TraceData {
        /// Per Python reader.py:507-559: TraceData format
        /// [reserved(1)][path_len(1)][flags(1)][tag(4)][auth(4)][path_hashes...][path_snrs...][final_snr]
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

    enum RawData {
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

    enum LogData {
        /// Per Python reader.py:503-505: LOG_DATA (0x88) dispatches as RX_LOG_DATA event
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

    enum LoginSuccess {
        /// Per Python reader.py:433-434: admin bit is bit 0 (permissions & 1)
        static func parse(_ data: Data) -> MeshEvent {
            guard data.count >= PacketSize.loginSuccessMinimum else {
                return .loginSuccess(LoginInfo(permissions: 0, isAdmin: false, publicKeyPrefix: Data()))
            }
            let permissions = data[0]
            let isAdmin = (permissions & 0x01) != 0
            let pubkeyPrefix = Data(data[2..<8])
            return .loginSuccess(LoginInfo(
                permissions: permissions,
                isAdmin: isAdmin,
                publicKeyPrefix: pubkeyPrefix
            ))
        }
    }
}
