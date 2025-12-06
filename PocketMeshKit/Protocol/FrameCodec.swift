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

        let lat = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        offset += 4

        let lon = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        offset += 4

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
        let text = String(data: textData, encoding: .utf8) ?? ""

        return ChannelMessageFrame(
            channelIndex: channelIdx,
            pathLength: pathLen,
            textType: txtType,
            timestamp: timestamp,
            text: text,
            snr: snr
        )
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
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
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
}
