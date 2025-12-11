import CryptoKit
import Foundation

public enum FrameCodec {

    // MARK: - Encoding

    public static func encodeDeviceQuery(protocolVersion: UInt8) -> Data {
        Data([CommandCode.deviceQuery.rawValue, protocolVersion])
    }

    public static func encodeAppStart(appName: String) -> Data {
        var data = Data([CommandCode.appStart.rawValue])
        data.append(Data(repeating: 0, count: 7))
        data.append(appName.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeSendTextMessage(
        textType: TextType,
        attempt: UInt8,
        timestamp: UInt32,
        recipientKeyPrefix: Data,
        text: String
    ) -> Data {
        var data = Data([CommandCode.sendTextMessage.rawValue])
        data.append(textType.rawValue)
        data.append(attempt)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        data.append(recipientKeyPrefix.prefix(6))
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeSendChannelMessage(
        textType: TextType,
        channelIndex: UInt8,
        timestamp: UInt32,
        text: String
    ) -> Data {
        var data = Data([CommandCode.sendChannelTextMessage.rawValue])
        data.append(textType.rawValue)
        data.append(channelIndex)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeGetContacts(since: UInt32? = nil) -> Data {
        var data = Data([CommandCode.getContacts.rawValue])
        if let since {
            data.append(contentsOf: withUnsafeBytes(of: since.littleEndian) { Array($0) })
        }
        return data
    }

    public static func encodeSyncNextMessage() -> Data {
        Data([CommandCode.syncNextMessage.rawValue])
    }

    public static func encodeSendSelfAdvert(flood: Bool) -> Data {
        Data([CommandCode.sendSelfAdvert.rawValue, flood ? 1 : 0])
    }

    public static func encodeSetRadioParams(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) -> Data {
        var data = Data([CommandCode.setRadioParams.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: frequencyKHz.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bandwidthKHz.littleEndian) { Array($0) })
        data.append(spreadingFactor)
        data.append(codingRate)
        return data
    }

    public static func encodeSetRadioTxPower(_ power: UInt8) -> Data {
        Data([CommandCode.setRadioTxPower.rawValue, power])
    }

    public static func encodeGetBatteryAndStorage() -> Data {
        Data([CommandCode.getBatteryAndStorage.rawValue])
    }

    public static func encodeSetAdvertName(_ name: String) -> Data {
        var data = Data([CommandCode.setAdvertName.rawValue])
        let nameData = name.data(using: .utf8) ?? Data()
        data.append(nameData.prefix(ProtocolLimits.maxNameLength - 1))
        return data
    }

    public static func encodeSetAdvertLatLon(latitude: Int32, longitude: Int32) -> Data {
        var data = Data([CommandCode.setAdvertLatLon.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: latitude.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: longitude.littleEndian) { Array($0) })
        return data
    }

    public static func encodeGetChannel(index: UInt8) -> Data {
        Data([CommandCode.getChannel.rawValue, index])
    }

    public static func encodeSetChannel(index: UInt8, name: String, secret: Data) -> Data {
        var data = Data([CommandCode.setChannel.rawValue, index])
        var nameBytes = (name.data(using: .utf8) ?? Data()).prefix(32)
        nameBytes.append(Data(repeating: 0, count: 32 - nameBytes.count))
        data.append(nameBytes)
        data.append(secret.prefix(16))
        return data
    }

    public static func encodeSetDeviceTime(_ timestamp: UInt32) -> Data {
        var data = Data([CommandCode.setDeviceTime.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        return data
    }

    public static func encodeGetDeviceTime() -> Data {
        Data([CommandCode.getDeviceTime.rawValue])
    }

    public static func encodeSendLogin(publicKey: Data, password: String) -> Data {
        var data = Data([CommandCode.sendLogin.rawValue])
        data.append(publicKey.prefix(32))
        data.append(password.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeReboot() -> Data {
        var data = Data([CommandCode.reboot.rawValue])
        data.append("reboot".data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeRemoveContact(publicKey: Data) -> Data {
        var data = Data([CommandCode.removeContact.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func encodeGetContactByKey(publicKey: Data) -> Data {
        var data = Data([CommandCode.getContactByKey.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func encodeSetDevicePin(_ pin: UInt32) -> Data {
        var data = Data([CommandCode.setDevicePin.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: pin.littleEndian) { Array($0) })
        return data
    }

    public static func encodeSetOtherParams(
        manualAddContacts: UInt8,
        telemetryModes: UInt8,
        advertLocationPolicy: UInt8,
        multiAcks: UInt8
    ) -> Data {
        var data = Data([CommandCode.setOtherParams.rawValue])
        data.append(manualAddContacts)
        data.append(telemetryModes)
        data.append(advertLocationPolicy)
        data.append(multiAcks)
        return data
    }

    public static func encodeGetTuningParams() -> Data {
        Data([CommandCode.getTuningParams.rawValue])
    }

    public static func encodeSetTuningParams(rxDelayBase: Float, airtimeFactor: Float) -> Data {
        var data = Data([CommandCode.setTuningParams.rawValue])
        let rxDelayInt = UInt32(rxDelayBase * 1000)
        let airtimeInt = UInt32(airtimeFactor * 1000)
        data.append(contentsOf: withUnsafeBytes(of: rxDelayInt.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: airtimeInt.littleEndian) { Array($0) })
        return data
    }

    public static func encodeGetStats(type: StatsType) -> Data {
        Data([CommandCode.getStats.rawValue, type.rawValue])
    }

    public static func encodeFactoryReset() -> Data {
        var data = Data([CommandCode.factoryReset.rawValue])
        data.append("factory".data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeAddUpdateContact(_ contact: ContactFrame) -> Data {
        var data = Data([CommandCode.addUpdateContact.rawValue])
        data.append(contact.publicKey.prefix(32))
        data.append(contact.type.rawValue)
        data.append(contact.flags)
        data.append(UInt8(bitPattern: Int8(contact.outPathLength)))

        // Pad path to 64 bytes
        var pathData = contact.outPath.prefix(64)
        pathData.append(Data(repeating: 0, count: max(0, 64 - pathData.count)))
        data.append(pathData)

        // Pad name to 32 bytes
        var nameData = (contact.name.data(using: .utf8) ?? Data()).prefix(32)
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        data.append(nameData)

        data.append(contentsOf: withUnsafeBytes(of: contact.lastAdvertTimestamp.littleEndian) { Array($0) })
        let latInt = Int32(contact.latitude * 1_000_000)
        let lonInt = Int32(contact.longitude * 1_000_000)
        data.append(contentsOf: withUnsafeBytes(of: latInt.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: lonInt.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: contact.lastModified.littleEndian) { Array($0) })

        return data
    }

    public static func encodeResetPath(publicKey: Data) -> Data {
        var data = Data([CommandCode.resetPath.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func encodeShareContact(publicKey: Data) -> Data {
        var data = Data([CommandCode.shareContact.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    // MARK: - Binary Protocol Encoding

    /// Encode a binary protocol request
    /// - Parameters:
    ///   - recipientPublicKey: Full 32-byte public key of recipient
    ///   - requestType: Type of binary request
    ///   - additionalData: Optional additional data for the request
    /// - Returns: Encoded frame data
    public static func encodeBinaryRequest(
        recipientPublicKey: Data,
        requestType: BinaryRequestType,
        additionalData: Data? = nil
    ) -> Data {
        var data = Data([CommandCode.sendBinaryRequest.rawValue])
        data.append(recipientPublicKey.prefix(32))
        data.append(requestType.rawValue)
        if let additional = additionalData {
            data.append(additional)
        }
        return data
    }

    /// Encode a neighbours request with pagination
    /// - Parameters:
    ///   - recipientPublicKey: Full 32-byte public key of recipient
    ///   - count: Number of neighbours to return (max 255)
    ///   - offset: Offset for pagination
    ///   - orderBy: Sort order (0 = default)
    ///   - pubkeyPrefixLength: Length of public key prefix in response (4-32)
    ///   - tag: Optional correlation tag (random if not provided)
    /// - Returns: Encoded frame data
    public static func encodeNeighboursRequest(
        recipientPublicKey: Data,
        count: UInt8 = 255,
        offset: UInt16 = 0,
        orderBy: UInt8 = 0,
        pubkeyPrefixLength: UInt8 = 4,
        tag: UInt32? = nil
    ) -> Data {
        var additionalData = Data()
        additionalData.append(0x00)  // version
        additionalData.append(count)
        additionalData.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        additionalData.append(orderBy)
        additionalData.append(pubkeyPrefixLength)
        // Random tag for correlation if not provided
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)
        additionalData.append(contentsOf: withUnsafeBytes(of: actualTag.littleEndian) { Array($0) })

        return encodeBinaryRequest(
            recipientPublicKey: recipientPublicKey,
            requestType: .neighbours,
            additionalData: additionalData
        )
    }

    // MARK: - Telemetry Encoding

    /// Encode telemetry request (get self telemetry)
    public static func encodeSelfTelemetryRequest() -> Data {
        // 0x27 0x00 0x00 0x00 - request own telemetry
        Data([CommandCode.sendTelemetryRequest.rawValue, 0x00, 0x00, 0x00])
    }

    /// Encode telemetry request to a remote node
    /// - Parameter recipientPublicKey: Full 32-byte public key of recipient
    public static func encodeTelemetryRequest(recipientPublicKey: Data) -> Data {
        var data = Data([CommandCode.sendTelemetryRequest.rawValue, 0x00, 0x00, 0x00])
        data.append(recipientPublicKey.prefix(32))
        return data
    }

    // MARK: - Path Discovery Encoding

    /// Encode path discovery request
    /// - Parameter recipientPublicKey: Full 32-byte public key of recipient
    /// - Returns: Encoded frame data
    public static func encodePathDiscovery(recipientPublicKey: Data) -> Data {
        var data = Data([CommandCode.sendPathDiscoveryRequest.rawValue, 0x00])
        data.append(recipientPublicKey.prefix(32))
        return data
    }

    // MARK: - Trace Encoding

    /// Encode trace packet request for route diagnostics
    /// - Parameters:
    ///   - tag: Optional correlation tag (random if not provided)
    ///   - authCode: Authentication code (default 0)
    ///   - flags: Trace flags (default 0)
    ///   - path: Optional path data to trace through
    /// - Returns: Encoded frame data
    public static func encodeTrace(
        tag: UInt32? = nil,
        authCode: UInt32 = 0,
        flags: UInt8 = 0,
        path: Data? = nil
    ) -> Data {
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)

        var data = Data([CommandCode.sendTracePath.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: actualTag.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: authCode.littleEndian) { Array($0) })
        data.append(flags)

        if let pathData = path {
            data.append(pathData)
        }

        return data
    }

    // MARK: - Decoding

    public static func decodeDeviceInfo(from data: Data) throws -> DeviceInfo {
        guard data.count >= 80, data[0] == ResponseCode.deviceInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let firmwareVersion = data[1]
        let maxContacts = data[2]
        let maxChannels = data[3]
        let blePin = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let buildDate = String(data: data.subdata(in: 8..<20), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let manufacturerName = String(data: data.subdata(in: 20..<60), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let firmwareVersionString = String(data: data.subdata(in: 60..<80), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

        return DeviceInfo(
            firmwareVersion: firmwareVersion,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            blePin: blePin,
            buildDate: buildDate,
            manufacturerName: manufacturerName,
            firmwareVersionString: firmwareVersionString
        )
    }

    public static func decodeSelfInfo(from data: Data) throws -> SelfInfo {
        guard data.count >= 58, data[0] == ResponseCode.selfInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let nodeType = data[1]
        let txPower = data[2]
        let maxTxPower = data[3]
        let publicKey = data.subdata(in: 4..<36)

        let latRaw = data.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lonRaw = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let latitude = Double(latRaw) / 1_000_000.0
        let longitude = Double(lonRaw) / 1_000_000.0

        let multiAcks = data[44]
        let advertLocPolicy = AdvertLocationPolicy(rawValue: data[45]) ?? .none
        let telemetryModes = data[46]
        let manualAddContacts = data[47]

        let frequency = data.subdata(in: 48..<52).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bandwidth = data.subdata(in: 52..<56).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let sf = data[56]
        let cr = data[57]

        let nodeName = data.count > 58 ? (String(data: data.suffix(from: 58), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? "") : ""

        return SelfInfo(
            nodeType: nodeType,
            txPower: txPower,
            maxTxPower: maxTxPower,
            publicKey: publicKey,
            latitude: latitude,
            longitude: longitude,
            multiAcks: multiAcks,
            advertLocationPolicy: advertLocPolicy,
            telemetryModes: telemetryModes,
            manualAddContacts: manualAddContacts,
            frequency: frequency,
            bandwidth: bandwidth,
            spreadingFactor: sf,
            codingRate: cr,
            nodeName: nodeName
        )
    }

    public static func decodeContact(from data: Data) throws -> ContactFrame {
        guard data.count >= 147,
              (data[0] == ResponseCode.contact.rawValue ||
               data[0] == PushCode.newAdvert.rawValue) else {
            throw ProtocolError.illegalArgument
        }

        var offset = 1
        let publicKey = data.subdata(in: offset..<(offset + 32))
        offset += 32

        let type = ContactType(rawValue: data[offset]) ?? .chat
        offset += 1

        let flags = data[offset]
        offset += 1

        let pathLen = Int8(bitPattern: data[offset])
        offset += 1

        let path = data.subdata(in: offset..<(offset + 64))
        offset += 64

        let nameData = data.subdata(in: offset..<(offset + 32))
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        offset += 32

        let timestamp = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let latRaw = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        offset += 4

        let lonRaw = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        offset += 4

        let lat = Float(latRaw) / 1_000_000.0
        let lon = Float(lonRaw) / 1_000_000.0

        let lastMod = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return ContactFrame(
            publicKey: publicKey,
            type: type,
            flags: flags,
            outPathLength: pathLen,
            outPath: path,
            name: name,
            lastAdvertTimestamp: timestamp,
            latitude: lat,
            longitude: lon,
            lastModified: lastMod
        )
    }

    public static func decodeSentResponse(from data: Data) throws -> SentResponse {
        guard data.count >= 10, data[0] == ResponseCode.sent.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let isFlood = data[1] == 1
        let ackCode = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let timeout = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return SentResponse(isFlood: isFlood, ackCode: ackCode, estimatedTimeout: timeout)
    }

    public static func decodeBatteryAndStorage(from data: Data) throws -> BatteryAndStorage {
        guard data.count >= 11, data[0] == ResponseCode.batteryAndStorage.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let battery = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let used = data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let total = data.subdata(in: 7..<11).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return BatteryAndStorage(batteryMillivolts: battery, storageUsedKB: used, storageTotalKB: total)
    }

    public static func decodeMessageV3(from data: Data) throws -> MessageFrame {
        guard data.count >= 16, data[0] == ResponseCode.contactMessageReceivedV3.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let snr = Int8(bitPattern: data[1])

        let senderPrefix = data.subdata(in: 4..<10)
        let pathLen = data[10]
        let txtType = TextType(rawValue: data[11]) ?? .plain
        let timestamp = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        let textData = data.suffix(from: 16)
        let text = String(data: textData, encoding: .utf8) ?? ""

        return MessageFrame(
            senderPublicKeyPrefix: senderPrefix,
            pathLength: pathLen,
            textType: txtType,
            timestamp: timestamp,
            text: text,
            snr: snr
        )
    }

    public static func decodeChannelMessageV3(from data: Data) throws -> ChannelMessageFrame {
        guard data.count >= 12, data[0] == ResponseCode.channelMessageReceivedV3.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let snr = Int8(bitPattern: data[1])

        let channelIdx = data[4]
        let pathLen = data[5]
        let txtType = TextType(rawValue: data[6]) ?? .plain
        let timestamp = data.subdata(in: 7..<11).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        let textData = data.suffix(from: 11)
        let rawText = String(data: textData, encoding: .utf8) ?? ""

        // Parse "NodeName: MessageText" format
        let (senderNodeName, text) = parseChannelMessageText(rawText)

        return ChannelMessageFrame(
            channelIndex: channelIdx,
            pathLength: pathLen,
            textType: txtType,
            timestamp: timestamp,
            text: text,
            snr: snr,
            senderNodeName: senderNodeName
        )
    }

    /// Parses channel message text in "NodeName: MessageText" format
    /// Returns (senderNodeName, messageText) tuple
    private static func parseChannelMessageText(_ rawText: String) -> (String?, String) {
        // Find the first occurrence of ": " (colon followed by space)
        guard let separatorRange = rawText.range(of: ": ") else {
            // No separator found - return full text with nil sender
            return (nil, rawText)
        }

        let senderName = String(rawText[..<separatorRange.lowerBound])
        let messageText = String(rawText[separatorRange.upperBound...])

        // Validate sender name is reasonable (not empty, not too long)
        // MeshCore node names are typically 1-32 characters
        guard !senderName.isEmpty, senderName.count <= 32 else {
            return (nil, rawText)
        }

        return (senderName, messageText)
    }

    public static func decodeSendConfirmation(from data: Data) throws -> SendConfirmation {
        guard data.count >= 9, data[0] == PushCode.sendConfirmed.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let ackCode = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let rtt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return SendConfirmation(ackCode: ackCode, roundTripTime: rtt)
    }

    public static func decodeChannelInfo(from data: Data) throws -> ChannelInfo {
        guard data.count >= 50, data[0] == ResponseCode.channelInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let index = data[1]
        let nameData = data.subdata(in: 2..<34)
        let nullTerminatedData: Data
        if let nullIndex = nameData.firstIndex(of: 0) {
            nullTerminatedData = nameData.prefix(upTo: nullIndex)
        } else {
            nullTerminatedData = nameData
        }
        let name = String(data: nullTerminatedData, encoding: .utf8) ?? ""
        let secret = data.subdata(in: 34..<50)

        return ChannelInfo(index: index, name: name, secret: secret)
    }

    public static func decodeCurrentTime(from data: Data) throws -> UInt32 {
        guard data.count >= 5, data[0] == ResponseCode.currentTime.rawValue else {
            throw ProtocolError.illegalArgument
        }

        return data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    public static func decodeTuningParams(from data: Data) throws -> TuningParams {
        guard data.count >= 9, data[0] == ResponseCode.tuningParams.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let rxDelayInt = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let airtimeInt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return TuningParams(
            rxDelayBase: Float(rxDelayInt) / 1000.0,
            airtimeFactor: Float(airtimeInt) / 1000.0
        )
    }

    public static func decodeCoreStats(from data: Data) throws -> CoreStats {
        guard data.count >= 11,
              data[0] == ResponseCode.stats.rawValue,
              data[1] == StatsType.core.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let battery = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let uptime = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let errors = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let queue = data[10]

        return CoreStats(batteryMillivolts: battery, uptimeSeconds: uptime, errorFlags: errors, queueLength: queue)
    }

    public static func decodeRadioStats(from data: Data) throws -> RadioStats {
        guard data.count >= 14,
              data[0] == ResponseCode.stats.rawValue,
              data[1] == StatsType.radio.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let noise = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        let rssi = Int8(bitPattern: data[4])
        let snr = Int8(bitPattern: data[5])
        let txAir = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let rxAir = data.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return RadioStats(noiseFloor: noise, lastRSSI: rssi, lastSNR: snr, txAirSeconds: txAir, rxAirSeconds: rxAir)
    }

    public static func decodePacketStats(from data: Data) throws -> PacketStats {
        guard data.count >= 26,
              data[0] == ResponseCode.stats.rawValue,
              data[1] == StatsType.packets.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let recv = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let sent = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let floodSent = data.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let directSent = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let floodRecv = data.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let directRecv = data.subdata(in: 22..<26).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return PacketStats(
            packetsReceived: recv,
            packetsSent: sent,
            floodSent: floodSent,
            directSent: directSent,
            floodReceived: floodRecv,
            directReceived: directRecv
        )
    }

    public static func decodeLoginResult(from data: Data) throws -> LoginResult {
        // Login success: 0x85 + isAdmin(1) + pubKeyPrefix(6) + timestamp(4) + aclPerms(1) + fwLevel(1)
        // Login fail: 0x86
        guard !data.isEmpty else {
            throw ProtocolError.illegalArgument
        }

        let code = data[0]

        if code == PushCode.loginFail.rawValue {
            return LoginResult(
                success: false,
                isAdmin: false,
                publicKeyPrefix: Data()
            )
        }

        guard code == PushCode.loginSuccess.rawValue, data.count >= 14 else {
            throw ProtocolError.illegalArgument
        }

        let isAdmin = data[1] != 0
        let publicKeyPrefix = data.subdata(in: 2..<8)
        let serverTimestamp = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let aclPermissions = data[12]
        let firmwareLevel = data[13]

        return LoginResult(
            success: true,
            isAdmin: isAdmin,
            publicKeyPrefix: publicKeyPrefix,
            serverTimestamp: serverTimestamp,
            aclPermissions: aclPermissions,
            firmwareLevel: firmwareLevel
        )
    }

    // MARK: - Binary Protocol Decoding

    /// Decode a binary response push
    /// - Parameter data: Raw push data starting with PushCode.binaryResponse
    /// - Returns: Parsed BinaryResponse with tag and raw data
    public static func decodeBinaryResponse(from data: Data) throws -> BinaryResponse {
        guard data.count >= 6, data[0] == PushCode.binaryResponse.rawValue else {
            throw ProtocolError.illegalArgument
        }

        // Skip reserved byte at index 1
        let tag = data.subdata(in: 2..<6)
        let rawData = data.suffix(from: 6)

        return BinaryResponse(tag: tag, rawData: Data(rawData))
    }

    /// Decode remote node status from binary response data
    /// - Parameters:
    ///   - data: Raw response data (without tag)
    ///   - publicKeyPrefix: Public key prefix of the responding node
    /// - Returns: Parsed RemoteNodeStatus
    public static func decodeRemoteNodeStatus(from data: Data, publicKeyPrefix: Data) throws -> RemoteNodeStatus {
        guard data.count >= 52 else {
            throw ProtocolError.illegalArgument
        }

        var offset = 0

        let batteryMillivolts = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        offset += 2

        let txQueueLength = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        offset += 2

        let noiseFloor = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        offset += 2

        let lastRssi = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        offset += 2

        let packetsReceived = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let packetsSent = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let airtimeSeconds = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let uptimeSeconds = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let sentFlood = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let sentDirect = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let receivedFlood = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let receivedDirect = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let fullEvents = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        offset += 2

        let lastSnrRaw = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        let lastSnr = Float(lastSnrRaw) / 4.0
        offset += 2

        let directDuplicates = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        offset += 2

        let floodDuplicates = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        offset += 2

        let rxAirtimeSeconds = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return RemoteNodeStatus(
            publicKeyPrefix: publicKeyPrefix,
            batteryMillivolts: batteryMillivolts,
            txQueueLength: txQueueLength,
            noiseFloor: noiseFloor,
            lastRssi: lastRssi,
            packetsReceived: packetsReceived,
            packetsSent: packetsSent,
            airtimeSeconds: airtimeSeconds,
            uptimeSeconds: uptimeSeconds,
            sentFlood: sentFlood,
            sentDirect: sentDirect,
            receivedFlood: receivedFlood,
            receivedDirect: receivedDirect,
            fullEvents: fullEvents,
            lastSnr: lastSnr,
            directDuplicates: directDuplicates,
            floodDuplicates: floodDuplicates,
            rxAirtimeSeconds: rxAirtimeSeconds
        )
    }

    /// Decode neighbours response from binary response data
    /// - Parameters:
    ///   - data: Raw response data (without tag)
    ///   - tag: Response tag for correlation
    ///   - pubkeyPrefixLength: Expected length of public key prefixes
    /// - Returns: Parsed NeighboursResponse
    public static func decodeNeighboursResponse(
        from data: Data,
        tag: Data,
        pubkeyPrefixLength: Int
    ) throws -> NeighboursResponse {
        guard data.count >= 4 else {
            throw ProtocolError.illegalArgument
        }

        let totalCount = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
        let resultsCount = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: Int16.self).littleEndian }

        var neighbours: [NeighbourInfo] = []
        var offset = 4
        let entrySize = pubkeyPrefixLength + 5  // pubkey + 4 bytes secondsAgo + 1 byte SNR

        for _ in 0..<resultsCount {
            guard offset + entrySize <= data.count else { break }

            let pubkey = data.subdata(in: offset..<(offset + pubkeyPrefixLength))
            offset += pubkeyPrefixLength

            let secondsAgo = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
            offset += 4

            let snrRaw = Int8(bitPattern: data[offset])
            let snr = Float(snrRaw) / 4.0
            offset += 1

            neighbours.append(NeighbourInfo(
                publicKeyPrefix: pubkey,
                secondsAgo: secondsAgo,
                snr: snr
            ))
        }

        return NeighboursResponse(
            tag: tag,
            totalCount: totalCount,
            resultsCount: resultsCount,
            neighbours: neighbours
        )
    }

    // MARK: - Status Response Decoding

    /// Decode status response push (0x87)
    /// - Parameter data: Raw push data starting with PushCode.statusResponse
    /// - Returns: Parsed RemoteNodeStatus
    public static func decodeStatusResponse(from data: Data) throws -> RemoteNodeStatus {
        guard data.count >= 60, data[0] == PushCode.statusResponse.rawValue else {
            throw ProtocolError.illegalArgument
        }

        // Format: 0x87, reserved(1), pubkey_prefix(6), status_data(52)
        let publicKeyPrefix = data.subdata(in: 2..<8)
        let statusData = data.suffix(from: 8)

        return try decodeRemoteNodeStatus(from: Data(statusData), publicKeyPrefix: publicKeyPrefix)
    }

    // MARK: - Telemetry Decoding

    /// Decode telemetry response push
    /// - Parameter data: Raw push data starting with PushCode.telemetryResponse
    /// - Returns: Parsed TelemetryResponse with LPP data points
    public static func decodeTelemetryResponse(from data: Data) throws -> TelemetryResponse {
        guard data.count >= 8, data[0] == PushCode.telemetryResponse.rawValue else {
            throw ProtocolError.illegalArgument
        }

        // Format: 0x8B, reserved(1), pubkey_prefix(6), lpp_data(...)
        let publicKeyPrefix = data.subdata(in: 2..<8)
        let lppData = data.suffix(from: 8)

        let dataPoints = LPPDecoder.decode(Data(lppData))

        return TelemetryResponse(
            publicKeyPrefix: publicKeyPrefix,
            dataPoints: dataPoints
        )
    }

    // MARK: - Path Discovery Decoding

    /// Decode path discovery response push
    /// - Parameter data: Raw push data starting with PushCode.pathDiscoveryResponse
    /// - Returns: Parsed PathDiscoveryResponse with outbound and inbound paths
    public static func decodePathDiscoveryResponse(from data: Data) throws -> PathDiscoveryResponse {
        guard data.count >= 10, data[0] == PushCode.pathDiscoveryResponse.rawValue else {
            throw ProtocolError.illegalArgument
        }

        // Format: 0x8D, reserved(1), pubkey_prefix(6), outPathLen(1), outPath(...), inPathLen(1), inPath(...)
        let publicKeyPrefix = data.subdata(in: 2..<8)
        var offset = 8

        let outPathLen = Int(data[offset])
        offset += 1

        guard offset + outPathLen < data.count else {
            throw ProtocolError.illegalArgument
        }

        let outPath = data.subdata(in: offset..<(offset + outPathLen))
        offset += outPathLen

        guard offset < data.count else {
            throw ProtocolError.illegalArgument
        }

        let inPathLen = Int(data[offset])
        offset += 1

        guard offset + inPathLen <= data.count else {
            throw ProtocolError.illegalArgument
        }

        let inPath = data.subdata(in: offset..<(offset + inPathLen))

        return PathDiscoveryResponse(
            publicKeyPrefix: publicKeyPrefix,
            outboundPath: outPath,
            inboundPath: inPath
        )
    }

    // MARK: - Trace Decoding

    /// Decode trace data push containing path diagnostics
    /// - Parameter data: Raw push data starting with PushCode.traceData
    /// - Returns: Parsed TraceData with path nodes and SNR values
    public static func decodeTraceData(from data: Data) throws -> TraceData {
        // Format: 0x89, reserved(1), pathLen(1), flags(1), tag(4), authCode(4), [hashBytes...], [snrBytes...], finalSnr(1)
        guard data.count >= 12, data[0] == PushCode.traceData.rawValue else {
            throw ProtocolError.illegalArgument
        }

        // Skip reserved byte at index 1
        let pathLen = Int(data[2])
        let flags = data[3]
        let tag = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let authCode = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        var path: [TracePathNode] = []

        // Parse path nodes: hashBytes followed by snrBytes
        if pathLen > 0 && data.count >= 12 + pathLen * 2 + 1 {
            for i in 0..<pathLen {
                let hashByte = data[12 + i]
                let snrRaw = Int8(bitPattern: data[12 + pathLen + i])
                let snr = Float(snrRaw) / 4.0
                path.append(TracePathNode(hashByte: hashByte, snr: snr))
            }
        }

        // Final SNR is the last byte after all path data
        let finalSnrIndex = 12 + pathLen * 2
        let finalSnrByte = data.count > finalSnrIndex ? Int8(bitPattern: data[finalSnrIndex]) : 0
        let finalSnr = Float(finalSnrByte) / 4.0

        return TraceData(tag: tag, authCode: authCode, flags: flags, path: path, finalSnr: finalSnr)
    }

    // MARK: - Control Data Encoding

    /// Encode control data packet
    /// - Parameters:
    ///   - controlType: Control data type byte
    ///   - payload: Payload data for the control message
    /// - Returns: Encoded frame data
    public static func encodeControlData(controlType: UInt8, payload: Data) -> Data {
        var data = Data([CommandCode.sendControlData.rawValue, controlType])
        data.append(payload)
        return data
    }

    /// Encode node discover request for finding nodes in the mesh
    /// - Parameters:
    ///   - filter: Node type filter (0 = all types)
    ///   - prefixOnly: If true, responses contain only public key prefix; otherwise full key
    ///   - tag: Optional correlation tag (random if not provided)
    ///   - since: Optional timestamp to filter nodes seen after this time
    /// - Returns: Encoded frame data
    public static func encodeNodeDiscoverRequest(
        filter: UInt8 = 0,
        prefixOnly: Bool = true,
        tag: UInt32? = nil,
        since: UInt32? = nil
    ) -> Data {
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)

        var payload = Data()
        payload.append(filter)
        payload.append(contentsOf: withUnsafeBytes(of: actualTag.littleEndian) { Array($0) })

        if let sinceValue = since {
            payload.append(contentsOf: withUnsafeBytes(of: sinceValue.littleEndian) { Array($0) })
        }

        let flags: UInt8 = prefixOnly ? 1 : 0
        let controlType = ControlDataType.nodeDiscoverRequest.rawValue | flags

        return encodeControlData(controlType: controlType, payload: payload)
    }

    // MARK: - Flood Scope Encoding

    /// Encode set flood scope command to limit flood routing
    /// - Parameter scope: Scope identifier with the following behaviors:
    ///   - If starts with "#": Hash the scope string using SHA256 and use first 16 bytes
    ///   - If empty, "0", "None", or "*": Disable scope (16 zero bytes)
    ///   - Otherwise: Use as raw key (padded to 16 bytes or truncated)
    /// - Returns: Encoded frame data
    public static func encodeSetFloodScope(_ scope: String) -> Data {
        let scopeKey: Data

        if scope.hasPrefix("#") {
            // Hash the scope string
            let hash = SHA256.hash(data: Data(scope.utf8))
            scopeKey = Data(hash.prefix(16))
        } else if scope.isEmpty || scope == "0" || scope == "None" || scope == "*" {
            // Disable scope
            scopeKey = Data(repeating: 0, count: 16)
        } else {
            // Use as raw key (padded/truncated to 16 bytes)
            var keyData = Data(scope.utf8)
            if keyData.count < 16 {
                keyData.append(Data(repeating: 0, count: 16 - keyData.count))
            } else if keyData.count > 16 {
                keyData = keyData.prefix(16)
            }
            scopeKey = keyData
        }

        var data = Data([CommandCode.setFloodScope.rawValue, 0x00])
        data.append(scopeKey)
        return data
    }

    // MARK: - Custom Variables Encoding/Decoding

    /// Encode get custom variables request
    /// - Returns: Encoded frame data
    public static func encodeGetCustomVars() -> Data {
        Data([CommandCode.getCustomVars.rawValue])
    }

    /// Encode set custom variable command
    /// - Parameters:
    ///   - key: Variable key name
    ///   - value: Variable value
    /// - Returns: Encoded frame data
    public static func encodeSetCustomVar(key: String, value: String) -> Data {
        var data = Data([CommandCode.setCustomVar.rawValue])
        data.append(Data("\(key):\(value)".utf8))
        return data
    }

    /// Decode custom variables response
    /// - Parameter data: Response data starting with ResponseCode.customVars
    /// - Returns: Dictionary of key-value pairs
    public static func decodeCustomVars(from data: Data) throws -> [String: String] {
        guard data.count >= 1, data[0] == ResponseCode.customVars.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let rawData = data.suffix(from: 1)
        guard let rawString = String(data: Data(rawData), encoding: .utf8), !rawString.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        for pair in rawString.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }

        return result
    }

    // MARK: - Status Request Encoding

    /// Encode status request to a contact
    /// - Parameter recipientPublicKey: Full 32-byte public key of the recipient
    /// - Returns: Encoded frame data
    public static func encodeStatusRequest(recipientPublicKey: Data) -> Data {
        var data = Data([CommandCode.sendStatusRequest.rawValue])
        data.append(recipientPublicKey.prefix(32))
        return data
    }

    // MARK: - Has Connection Encoding/Decoding

    /// Encode has connection query to check if a contact has an active persistent connection
    /// - Parameter recipientPublicKey: Full 32-byte public key of the contact
    /// - Returns: Encoded frame data
    public static func encodeHasConnection(recipientPublicKey: Data) -> Data {
        var data = Data([CommandCode.hasConnection.rawValue])
        data.append(recipientPublicKey.prefix(32))
        return data
    }

    /// Decode has connection response
    /// - Parameter data: Response data starting with ResponseCode.hasConnection
    /// - Returns: true if the contact has an active connection, false otherwise
    public static func decodeHasConnectionResponse(from data: Data) throws -> Bool {
        guard data.count >= 2, data[0] == ResponseCode.hasConnection.rawValue else {
            throw ProtocolError.illegalArgument
        }
        return data[1] != 0
    }

    // MARK: - Logout Encoding

    /// Encode logout command to terminate a persistent connection with a contact
    /// - Parameter recipientPublicKey: Full 32-byte public key of the contact
    /// - Returns: Encoded frame data
    public static func encodeLogout(recipientPublicKey: Data) -> Data {
        var data = Data([CommandCode.logout.rawValue])
        data.append(recipientPublicKey.prefix(32))
        return data
    }

    // MARK: - Control Data Decoding

    /// Decode control data push
    /// - Parameter data: Raw push data starting with PushCode.controlData
    /// - Returns: Parsed ControlDataPacket
    public static func decodeControlData(from data: Data) throws -> ControlDataPacket {
        // Format: 0x8E, snr(1), rssi(1), pathLength(1), payload(...)
        guard data.count >= 4, data[0] == PushCode.controlData.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let snrRaw = Int8(bitPattern: data[1])
        let snr = Float(snrRaw) / 4.0
        let rssi = Int8(bitPattern: data[2])
        let pathLength = data[3]
        let payload = Data(data.suffix(from: 4))
        let payloadType = payload.first ?? 0

        return ControlDataPacket(
            snr: snr,
            rssi: rssi,
            pathLength: pathLength,
            payloadType: payloadType,
            payload: payload
        )
    }

    /// Decode node discover response from control data packet
    /// - Parameter controlData: Previously decoded ControlDataPacket
    /// - Returns: Parsed NodeDiscoverResponse if this is a node discover response, nil otherwise
    public static func decodeNodeDiscoverResponse(from controlData: ControlDataPacket) throws -> NodeDiscoverResponse? {
        // Check if this is a node discover response (high nibble = 0x90)
        guard controlData.payloadType & 0xF0 == ControlDataType.nodeDiscoverResponse.rawValue else {
            return nil
        }

        let payload = controlData.payload
        // Minimum: type(1) + snrIn(1) + tag(4) = 6 bytes
        guard payload.count >= 6 else {
            throw ProtocolError.illegalArgument
        }

        let nodeType = controlData.payloadType & 0x0F
        let snrInRaw = Int8(bitPattern: payload[1])
        let snrIn = Float(snrInRaw) / 4.0
        let tag = payload.subdata(in: 2..<6)
        let publicKey = Data(payload.suffix(from: 6))

        return NodeDiscoverResponse(
            snr: controlData.snr,
            rssi: controlData.rssi,
            pathLength: controlData.pathLength,
            nodeType: nodeType,
            snrIn: snrIn,
            tag: tag,
            publicKey: publicKey
        )
    }
}
