import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Protocol Codec Tests")
struct ProtocolCodecTests {

    // MARK: - Encoding Tests

    @Test("Encode device query with protocol version")
    func encodeDeviceQuery() {
        let data = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        #expect(data.count == 2)
        #expect(data[0] == CommandCode.deviceQuery.rawValue)
        #expect(data[1] == 8)
    }

    @Test("Encode app start with app name")
    func encodeAppStart() {
        let data = FrameCodec.encodeAppStart(appName: "PocketMesh")
        #expect(data.count == 18)
        #expect(data[0] == CommandCode.appStart.rawValue)
        // 7 reserved bytes
        #expect(data[1] == 0)
        #expect(data[7] == 0)
        #expect(String(data: data.suffix(from: 8), encoding: .utf8) == "PocketMesh")
    }

    @Test("Encode send text message with all fields")
    func encodeSendTextMessage() {
        let recipientKey = Data(repeating: 0xAB, count: 6)
        let data = FrameCodec.encodeSendTextMessage(
            textType: .plain,
            attempt: 1,
            timestamp: 1234567890,
            recipientKeyPrefix: recipientKey,
            text: "Hello"
        )

        #expect(data[0] == CommandCode.sendTextMessage.rawValue)
        #expect(data[1] == TextType.plain.rawValue)
        #expect(data[2] == 1)
        // Verify recipient key prefix is included
        #expect(data.subdata(in: 7..<13) == recipientKey)
        // Verify text is at the end
        #expect(String(data: data.suffix(from: 13), encoding: .utf8) == "Hello")
    }

    @Test("Encode send channel message")
    func encodeSendChannelMessage() {
        let data = FrameCodec.encodeSendChannelMessage(
            textType: .plain,
            channelIndex: 2,
            timestamp: 1234567890,
            text: "Channel message"
        )

        #expect(data[0] == CommandCode.sendChannelTextMessage.rawValue)
        #expect(data[1] == TextType.plain.rawValue)
        #expect(data[2] == 2)
    }

    @Test("Encode get contacts without filter")
    func encodeGetContactsWithoutFilter() {
        let data = FrameCodec.encodeGetContacts()
        #expect(data.count == 1)
        #expect(data[0] == CommandCode.getContacts.rawValue)
    }

    @Test("Encode get contacts with since filter")
    func encodeGetContactsWithFilter() {
        let data = FrameCodec.encodeGetContacts(since: 1000)
        #expect(data.count == 5)
        #expect(data[0] == CommandCode.getContacts.rawValue)
        let since = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(since == 1000)
    }

    @Test("Encode radio params with valid values")
    func encodeRadioParams() {
        let data = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 10,
            codingRate: 5
        )

        #expect(data[0] == CommandCode.setRadioParams.rawValue)
        #expect(data.count == 11)

        let freq = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bw = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(freq == 915000)
        #expect(bw == 250000)
        #expect(data[9] == 10)
        #expect(data[10] == 5)
    }

    @Test("Encode set TX power")
    func encodeSetTxPower() {
        let data = FrameCodec.encodeSetRadioTxPower(15)
        #expect(data.count == 2)
        #expect(data[0] == CommandCode.setRadioTxPower.rawValue)
        #expect(data[1] == 15)
    }

    @Test("Encode set advert name")
    func encodeSetAdvertName() {
        let data = FrameCodec.encodeSetAdvertName("TestNode")
        #expect(data[0] == CommandCode.setAdvertName.rawValue)
        #expect(String(data: data.suffix(from: 1), encoding: .utf8) == "TestNode")
    }

    @Test("Encode set advert lat/lon")
    func encodeSetAdvertLatLon() {
        let data = FrameCodec.encodeSetAdvertLatLon(latitude: 37_774_900, longitude: -122_419_400)
        #expect(data[0] == CommandCode.setAdvertLatLon.rawValue)
        #expect(data.count == 9)
        let lat = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lon = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        #expect(lat == 37_774_900)
        #expect(lon == -122_419_400)
    }

    @Test("Encode get channel")
    func encodeGetChannel() {
        let data = FrameCodec.encodeGetChannel(index: 3)
        #expect(data.count == 2)
        #expect(data[0] == CommandCode.getChannel.rawValue)
        #expect(data[1] == 3)
    }

    @Test("Encode set channel with name and secret")
    func encodeSetChannel() {
        let secret = Data(repeating: 0xAB, count: 16)
        let data = FrameCodec.encodeSetChannel(index: 1, name: "Private", secret: secret)

        #expect(data[0] == CommandCode.setChannel.rawValue)
        #expect(data[1] == 1)
        // Name should be padded to 32 bytes
        let nameData = data.subdata(in: 2..<34)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        #expect(name == "Private")
        // Secret should be 16 bytes
        #expect(data.subdata(in: 34..<50) == secret)
    }

    @Test("Encode reboot command")
    func encodeReboot() {
        let data = FrameCodec.encodeReboot()
        #expect(data[0] == CommandCode.reboot.rawValue)
        #expect(String(data: data.suffix(from: 1), encoding: .utf8) == "reboot")
    }

    @Test("Encode get stats for each type")
    func encodeGetStats() {
        let coreData = FrameCodec.encodeGetStats(type: .core)
        #expect(coreData.count == 2)
        #expect(coreData[0] == CommandCode.getStats.rawValue)
        #expect(coreData[1] == StatsType.core.rawValue)

        let radioData = FrameCodec.encodeGetStats(type: .radio)
        #expect(radioData[1] == StatsType.radio.rawValue)

        let packetData = FrameCodec.encodeGetStats(type: .packets)
        #expect(packetData[1] == StatsType.packets.rawValue)
    }

    // MARK: - Decoding Tests

    @Test("Decode battery and storage response")
    func decodeBatteryAndStorage() throws {
        var testData = Data([ResponseCode.batteryAndStorage.rawValue])
        let battery: UInt16 = 4200
        let used: UInt32 = 128
        let total: UInt32 = 1024
        testData.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
        testData.append(contentsOf: withUnsafeBytes(of: used.littleEndian) { Array($0) })
        testData.append(contentsOf: withUnsafeBytes(of: total.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeBatteryAndStorage(from: testData)
        #expect(result.batteryMillivolts == 4200)
        #expect(result.storageUsedKB == 128)
        #expect(result.storageTotalKB == 1024)
    }

    @Test("Decode device info response")
    func decodeDeviceInfo() throws {
        var testData = Data([ResponseCode.deviceInfo.rawValue])
        testData.append(8) // firmware version
        testData.append(50) // max contacts
        testData.append(8) // max channels

        let pin: UInt32 = 123456
        testData.append(contentsOf: withUnsafeBytes(of: pin.littleEndian) { Array($0) })

        // Build date (12 bytes)
        var buildDate = "06 Dec 2025".data(using: .utf8)!
        buildDate.append(Data(repeating: 0, count: 12 - buildDate.count))
        testData.append(buildDate)

        // Manufacturer (40 bytes)
        var manufacturer = "TestMfg".data(using: .utf8)!
        manufacturer.append(Data(repeating: 0, count: 40 - manufacturer.count))
        testData.append(manufacturer)

        // Firmware version string (20 bytes)
        var fwVersion = "v1.0.0".data(using: .utf8)!
        fwVersion.append(Data(repeating: 0, count: 20 - fwVersion.count))
        testData.append(fwVersion)

        let result = try FrameCodec.decodeDeviceInfo(from: testData)
        #expect(result.firmwareVersion == 8)
        #expect(result.maxContacts == 50)
        #expect(result.maxChannels == 8)
        #expect(result.blePin == 123456)
        #expect(result.buildDate == "06 Dec 2025")
        #expect(result.manufacturerName == "TestMfg")
        #expect(result.firmwareVersionString == "v1.0.0")
    }

    @Test("Decode sent response")
    func decodeSentResponse() throws {
        var testData = Data([ResponseCode.sent.rawValue])
        testData.append(0) // not flood
        let ackCode: UInt32 = 12345
        testData.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        let timeout: UInt32 = 5000
        testData.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeSentResponse(from: testData)
        #expect(result.isFlood == false)
        #expect(result.ackCode == 12345)
        #expect(result.estimatedTimeout == 5000)
    }

    @Test("Decode send confirmation push")
    func decodeSendConfirmation() throws {
        var testData = Data([PushCode.sendConfirmed.rawValue])
        let ackCode: UInt32 = 12345
        testData.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        let rtt: UInt32 = 500
        testData.append(contentsOf: withUnsafeBytes(of: rtt.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeSendConfirmation(from: testData)
        #expect(result.ackCode == 12345)
        #expect(result.roundTripTime == 500)
    }

    @Test("Decode channel info response")
    func decodeChannelInfo() throws {
        var testData = Data([ResponseCode.channelInfo.rawValue])
        testData.append(1) // index

        var nameData = "TestChannel".data(using: .utf8)!
        nameData.append(Data(repeating: 0, count: 32 - nameData.count))
        testData.append(nameData)

        let secret = Data(repeating: 0xAB, count: 16)
        testData.append(secret)

        let result = try FrameCodec.decodeChannelInfo(from: testData)
        #expect(result.index == 1)
        #expect(result.name == "TestChannel")
        #expect(result.secret == secret)
    }

    @Test("Decode current time response")
    func decodeCurrentTime() throws {
        var testData = Data([ResponseCode.currentTime.rawValue])
        let time: UInt32 = 1733500000
        testData.append(contentsOf: withUnsafeBytes(of: time.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeCurrentTime(from: testData)
        #expect(result == 1733500000)
    }

    @Test("Decode core stats response")
    func decodeCoreStats() throws {
        var testData = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
        let battery: UInt16 = 4200
        testData.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
        let uptime: UInt32 = 3600
        testData.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })
        let errors: UInt16 = 0
        testData.append(contentsOf: withUnsafeBytes(of: errors.littleEndian) { Array($0) })
        testData.append(5) // queue length

        let result = try FrameCodec.decodeCoreStats(from: testData)
        #expect(result.batteryMillivolts == 4200)
        #expect(result.uptimeSeconds == 3600)
        #expect(result.errorFlags == 0)
        #expect(result.queueLength == 5)
    }

    @Test("Decode radio stats response")
    func decodeRadioStats() throws {
        var testData = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
        let noise: Int16 = -120
        testData.append(contentsOf: withUnsafeBytes(of: noise.littleEndian) { Array($0) })
        testData.append(UInt8(bitPattern: Int8(-60))) // rssi
        testData.append(UInt8(bitPattern: Int8(40))) // snr
        let txAir: UInt32 = 100
        testData.append(contentsOf: withUnsafeBytes(of: txAir.littleEndian) { Array($0) })
        let rxAir: UInt32 = 200
        testData.append(contentsOf: withUnsafeBytes(of: rxAir.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeRadioStats(from: testData)
        #expect(result.noiseFloor == -120)
        #expect(result.lastRSSI == -60)
        #expect(result.lastSNR == 10.0)
        #expect(result.txAirSeconds == 100)
        #expect(result.rxAirSeconds == 200)
    }

    @Test("Decode packet stats response")
    func decodePacketStats() throws {
        var testData = Data([ResponseCode.stats.rawValue, StatsType.packets.rawValue])
        let values: [UInt32] = [50, 30, 10, 20, 25, 25]
        for value in values {
            testData.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }

        let result = try FrameCodec.decodePacketStats(from: testData)
        #expect(result.packetsReceived == 50)
        #expect(result.packetsSent == 30)
        #expect(result.floodSent == 10)
        #expect(result.directSent == 20)
        #expect(result.floodReceived == 25)
        #expect(result.directReceived == 25)
    }

    @Test("Decode contact with location coordinates")
    func decodeContactWithLocation() throws {
        var testData = Data([ResponseCode.contact.rawValue])

        // Public key (32 bytes)
        testData.append(Data(repeating: 0xAB, count: 32))

        // Type, flags, path length
        testData.append(ContactType.chat.rawValue)
        testData.append(0) // flags
        testData.append(0xFF) // path length (-1 = flood)

        // Path (64 bytes)
        testData.append(Data(repeating: 0, count: 64))

        // Name (32 bytes)
        var nameData = "TestContact".data(using: .utf8)!
        nameData.append(Data(repeating: 0, count: 32 - nameData.count))
        testData.append(nameData)

        // Last advert timestamp
        let timestamp: UInt32 = 1733500000
        testData.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })

        // Latitude as Int32 * 1E6 (37.7749 = 37774900)
        let latInt: Int32 = 37_774_900
        testData.append(contentsOf: withUnsafeBytes(of: latInt.littleEndian) { Array($0) })

        // Longitude as Int32 * 1E6 (-122.4194 = -122419400)
        let lonInt: Int32 = -122_419_400
        testData.append(contentsOf: withUnsafeBytes(of: lonInt.littleEndian) { Array($0) })

        // Last modified timestamp
        testData.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeContact(from: testData)

        // Verify coordinates are decoded correctly
        #expect(abs(result.latitude - 37.7749) < 0.0001)
        #expect(abs(result.longitude - (-122.4194)) < 0.0001)
    }

    @Test("Encode contact preserves location coordinates")
    func encodeContactWithLocation() throws {
        let contact = ContactFrame(
            publicKey: Data(repeating: 0xAB, count: 32),
            type: .chat,
            flags: 0,
            outPathLength: -1,
            outPath: Data(repeating: 0, count: 64),
            name: "TestContact",
            lastAdvertTimestamp: 1733500000,
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: 1733500000
        )

        let encoded = FrameCodec.encodeAddUpdateContact(contact)

        // Latitude should be at bytes 136-139 (1 + 32 + 1 + 1 + 1 + 64 + 32 + 4 = 136)
        let latInt = encoded.subdata(in: 136..<140).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lonInt = encoded.subdata(in: 140..<144).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }

        #expect(latInt == 37_774_900)
        #expect(lonInt == -122_419_400)
    }

    // MARK: - Error Cases

    @Test("Decode with wrong response code throws error")
    func decodeWrongResponseCode() {
        let testData = Data([ResponseCode.ok.rawValue])
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeBatteryAndStorage(from: testData)
        }
    }

    @Test("Decode with insufficient data throws error")
    func decodeInsufficientData() {
        let testData = Data([ResponseCode.batteryAndStorage.rawValue, 0x00])
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeBatteryAndStorage(from: testData)
        }
    }

    // MARK: - Command Code Values

    @Test("Command codes have correct raw values matching firmware")
    func commandCodeValues() {
        #expect(CommandCode.appStart.rawValue == 0x01)
        #expect(CommandCode.sendTextMessage.rawValue == 0x02)
        #expect(CommandCode.sendChannelTextMessage.rawValue == 0x03)
        #expect(CommandCode.getContacts.rawValue == 0x04)
        #expect(CommandCode.getDeviceTime.rawValue == 0x05)
        #expect(CommandCode.setDeviceTime.rawValue == 0x06)
        #expect(CommandCode.sendSelfAdvert.rawValue == 0x07)
        #expect(CommandCode.setAdvertName.rawValue == 0x08)
        #expect(CommandCode.addUpdateContact.rawValue == 0x09)
        #expect(CommandCode.syncNextMessage.rawValue == 0x0A)
        #expect(CommandCode.setRadioParams.rawValue == 0x0B)
        #expect(CommandCode.setRadioTxPower.rawValue == 0x0C)
        #expect(CommandCode.resetPath.rawValue == 0x0D)
        #expect(CommandCode.setAdvertLatLon.rawValue == 0x0E)
        #expect(CommandCode.removeContact.rawValue == 0x0F)
        #expect(CommandCode.shareContact.rawValue == 0x10)
        #expect(CommandCode.exportContact.rawValue == 0x11)
        #expect(CommandCode.importContact.rawValue == 0x12)
        #expect(CommandCode.reboot.rawValue == 0x13)
        #expect(CommandCode.getBatteryAndStorage.rawValue == 0x14)
        #expect(CommandCode.setTuningParams.rawValue == 0x15)
        #expect(CommandCode.deviceQuery.rawValue == 0x16)
        #expect(CommandCode.getStats.rawValue == 0x38)
    }

    @Test("Response codes have correct raw values matching firmware")
    func responseCodeValues() {
        #expect(ResponseCode.ok.rawValue == 0x00)
        #expect(ResponseCode.error.rawValue == 0x01)
        #expect(ResponseCode.contactsStart.rawValue == 0x02)
        #expect(ResponseCode.contact.rawValue == 0x03)
        #expect(ResponseCode.endOfContacts.rawValue == 0x04)
        #expect(ResponseCode.selfInfo.rawValue == 0x05)
        #expect(ResponseCode.sent.rawValue == 0x06)
        #expect(ResponseCode.deviceInfo.rawValue == 0x0D)
        #expect(ResponseCode.channelInfo.rawValue == 0x12)
        #expect(ResponseCode.stats.rawValue == 0x18)
    }

    @Test("Push codes have correct raw values matching firmware")
    func pushCodeValues() {
        #expect(PushCode.advert.rawValue == 0x80)
        #expect(PushCode.pathUpdated.rawValue == 0x81)
        #expect(PushCode.sendConfirmed.rawValue == 0x82)
        #expect(PushCode.messageWaiting.rawValue == 0x83)
        #expect(PushCode.loginSuccess.rawValue == 0x85)
        #expect(PushCode.loginFail.rawValue == 0x86)
        #expect(PushCode.newAdvert.rawValue == 0x8A)
    }

    @Test("Error codes have correct raw values matching firmware")
    func errorCodeValues() {
        #expect(ProtocolError.unsupportedCommand.rawValue == 0x01)
        #expect(ProtocolError.notFound.rawValue == 0x02)
        #expect(ProtocolError.tableFull.rawValue == 0x03)
        #expect(ProtocolError.badState.rawValue == 0x04)
        #expect(ProtocolError.fileIOError.rawValue == 0x05)
        #expect(ProtocolError.illegalArgument.rawValue == 0x06)
    }

    // MARK: - Binary Protocol Tests

    @Test("Binary request types have correct raw values")
    func binaryRequestTypeValues() {
        #expect(BinaryRequestType.status.rawValue == 0x01)
        #expect(BinaryRequestType.keepAlive.rawValue == 0x02)
        #expect(BinaryRequestType.telemetry.rawValue == 0x03)
        #expect(BinaryRequestType.mma.rawValue == 0x04)
        #expect(BinaryRequestType.acl.rawValue == 0x05)
        #expect(BinaryRequestType.neighbours.rawValue == 0x06)
    }

    @Test("Encode binary request with status type")
    func encodeBinaryRequest() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let data = FrameCodec.encodeBinaryRequest(
            recipientPublicKey: publicKey,
            requestType: .status
        )

        #expect(data.count == 34)
        #expect(data[0] == CommandCode.sendBinaryRequest.rawValue)
        #expect(data.subdata(in: 1..<33) == publicKey)
        #expect(data[33] == BinaryRequestType.status.rawValue)
    }

    @Test("Encode binary request with additional data")
    func encodeBinaryRequestWithAdditionalData() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let additionalData = Data([0x01, 0x02, 0x03])
        let data = FrameCodec.encodeBinaryRequest(
            recipientPublicKey: publicKey,
            requestType: .telemetry,
            additionalData: additionalData
        )

        #expect(data.count == 37)
        #expect(data[0] == CommandCode.sendBinaryRequest.rawValue)
        #expect(data[33] == BinaryRequestType.telemetry.rawValue)
        #expect(data.suffix(3) == additionalData)
    }

    @Test("Encode neighbours request with pagination")
    func encodeNeighboursRequest() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let data = FrameCodec.encodeNeighboursRequest(
            recipientPublicKey: publicKey,
            count: 100,
            offset: 50,
            pubkeyPrefixLength: 6,
            tag: 0x12345678
        )

        #expect(data[0] == CommandCode.sendBinaryRequest.rawValue)
        #expect(data[33] == BinaryRequestType.neighbours.rawValue)

        // Additional data: version(1) + count(1) + offset(2) + orderBy(1) + prefixLen(1) + tag(4) = 10 bytes
        #expect(data.count == 44)
        #expect(data[34] == 0x00)  // version
        #expect(data[35] == 100)   // count
        // offset is little-endian
        let offset = data.subdata(in: 36..<38).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        #expect(offset == 50)
        #expect(data[38] == 0)     // orderBy
        #expect(data[39] == 6)     // pubkeyPrefixLength
        // tag is little-endian
        let tag = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(tag == 0x12345678)
    }

    @Test("Decode binary response push")
    func decodeBinaryResponse() throws {
        var testData = Data([PushCode.binaryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(contentsOf: [0x78, 0x56, 0x34, 0x12])  // tag (little-endian)
        testData.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])  // raw data

        let result = try FrameCodec.decodeBinaryResponse(from: testData)

        #expect(result.tag == Data([0x78, 0x56, 0x34, 0x12]))
        #expect(result.rawData == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    @Test("Decode remote node status")
    func decodeRemoteNodeStatus() throws {
        var testData = Data()

        // batteryMillivolts (2)
        let battery: UInt16 = 4200
        testData.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })

        // txQueueLength (2)
        let txQueue: UInt16 = 5
        testData.append(contentsOf: withUnsafeBytes(of: txQueue.littleEndian) { Array($0) })

        // noiseFloor (2)
        let noise: Int16 = -120
        testData.append(contentsOf: withUnsafeBytes(of: noise.littleEndian) { Array($0) })

        // lastRssi (2)
        let rssi: Int16 = -80
        testData.append(contentsOf: withUnsafeBytes(of: rssi.littleEndian) { Array($0) })

        // packetsReceived (4)
        let packetsRx: UInt32 = 1000
        testData.append(contentsOf: withUnsafeBytes(of: packetsRx.littleEndian) { Array($0) })

        // packetsSent (4)
        let packetsTx: UInt32 = 800
        testData.append(contentsOf: withUnsafeBytes(of: packetsTx.littleEndian) { Array($0) })

        // airtimeSeconds (4)
        let airtime: UInt32 = 3600
        testData.append(contentsOf: withUnsafeBytes(of: airtime.littleEndian) { Array($0) })

        // uptimeSeconds (4)
        let uptime: UInt32 = 86400
        testData.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })

        // sentFlood (4)
        let sentFlood: UInt32 = 100
        testData.append(contentsOf: withUnsafeBytes(of: sentFlood.littleEndian) { Array($0) })

        // sentDirect (4)
        let sentDirect: UInt32 = 700
        testData.append(contentsOf: withUnsafeBytes(of: sentDirect.littleEndian) { Array($0) })

        // receivedFlood (4)
        let receivedFlood: UInt32 = 200
        testData.append(contentsOf: withUnsafeBytes(of: receivedFlood.littleEndian) { Array($0) })

        // receivedDirect (4)
        let receivedDirect: UInt32 = 800
        testData.append(contentsOf: withUnsafeBytes(of: receivedDirect.littleEndian) { Array($0) })

        // fullEvents (2)
        let fullEvents: UInt16 = 3
        testData.append(contentsOf: withUnsafeBytes(of: fullEvents.littleEndian) { Array($0) })

        // lastSnr as Int16 * 4 (2)
        let snrRaw: Int16 = 48  // 12.0 dB * 4
        testData.append(contentsOf: withUnsafeBytes(of: snrRaw.littleEndian) { Array($0) })

        // directDuplicates (2)
        let directDups: UInt16 = 10
        testData.append(contentsOf: withUnsafeBytes(of: directDups.littleEndian) { Array($0) })

        // floodDuplicates (2)
        let floodDups: UInt16 = 20
        testData.append(contentsOf: withUnsafeBytes(of: floodDups.littleEndian) { Array($0) })

        // rxAirtimeSeconds (4)
        let rxAirtime: UInt32 = 1800
        testData.append(contentsOf: withUnsafeBytes(of: rxAirtime.littleEndian) { Array($0) })

        let publicKeyPrefix = Data(repeating: 0xAB, count: 6)
        let result = try FrameCodec.decodeRemoteNodeStatus(from: testData, publicKeyPrefix: publicKeyPrefix)

        #expect(result.publicKeyPrefix == publicKeyPrefix)
        #expect(result.batteryMillivolts == 4200)
        #expect(result.txQueueLength == 5)
        #expect(result.noiseFloor == -120)
        #expect(result.lastRssi == -80)
        #expect(result.packetsReceived == 1000)
        #expect(result.packetsSent == 800)
        #expect(result.airtimeSeconds == 3600)
        #expect(result.uptimeSeconds == 86400)
        #expect(result.sentFlood == 100)
        #expect(result.sentDirect == 700)
        #expect(result.receivedFlood == 200)
        #expect(result.receivedDirect == 800)
        #expect(result.fullEvents == 3)
        #expect(abs(result.lastSnr - 12.0) < 0.01)
        #expect(result.directDuplicates == 10)
        #expect(result.floodDuplicates == 20)
        #expect(result.rxAirtimeSeconds == 1800)
    }

    @Test("Decode neighbours response")
    func decodeNeighboursResponse() throws {
        var testData = Data()

        // totalCount (2)
        let totalCount: Int16 = 10
        testData.append(contentsOf: withUnsafeBytes(of: totalCount.littleEndian) { Array($0) })

        // resultsCount (2)
        let resultsCount: Int16 = 2
        testData.append(contentsOf: withUnsafeBytes(of: resultsCount.littleEndian) { Array($0) })

        // Neighbour 1: pubkey(4) + secondsAgo(4) + snr(1) = 9 bytes
        testData.append(Data([0x01, 0x02, 0x03, 0x04]))  // pubkey prefix
        let secsAgo1: Int32 = 60
        testData.append(contentsOf: withUnsafeBytes(of: secsAgo1.littleEndian) { Array($0) })
        testData.append(UInt8(bitPattern: Int8(32)))  // SNR = 8.0 * 4

        // Neighbour 2
        testData.append(Data([0x05, 0x06, 0x07, 0x08]))  // pubkey prefix
        let secsAgo2: Int32 = 120
        testData.append(contentsOf: withUnsafeBytes(of: secsAgo2.littleEndian) { Array($0) })
        testData.append(UInt8(bitPattern: Int8(-20)))  // SNR = -5.0 * 4

        let tag = Data([0x78, 0x56, 0x34, 0x12])
        let result = try FrameCodec.decodeNeighboursResponse(
            from: testData,
            tag: tag,
            pubkeyPrefixLength: 4
        )

        #expect(result.tag == tag)
        #expect(result.totalCount == 10)
        #expect(result.resultsCount == 2)
        #expect(result.neighbours.count == 2)

        #expect(result.neighbours[0].publicKeyPrefix == Data([0x01, 0x02, 0x03, 0x04]))
        #expect(result.neighbours[0].secondsAgo == 60)
        #expect(abs(result.neighbours[0].snr - 8.0) < 0.01)

        #expect(result.neighbours[1].publicKeyPrefix == Data([0x05, 0x06, 0x07, 0x08]))
        #expect(result.neighbours[1].secondsAgo == 120)
        #expect(abs(result.neighbours[1].snr - (-5.0)) < 0.01)
    }

    @Test("Decode binary response with insufficient data throws error")
    func decodeBinaryResponseInsufficientData() {
        let testData = Data([PushCode.binaryResponse.rawValue, 0x00, 0x01])  // Only 3 bytes
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeBinaryResponse(from: testData)
        }
    }

    @Test("Decode binary response with wrong push code throws error")
    func decodeBinaryResponseWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(contentsOf: Data(repeating: 0, count: 10))
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeBinaryResponse(from: testData)
        }
    }

    @Test("Decode remote node status with insufficient data throws error")
    func decodeRemoteNodeStatusInsufficientData() {
        let testData = Data(repeating: 0, count: 40)  // Less than 52 bytes
        let publicKeyPrefix = Data(repeating: 0xAB, count: 6)
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeRemoteNodeStatus(from: testData, publicKeyPrefix: publicKeyPrefix)
        }
    }

    @Test("Decode neighbours response with insufficient data throws error")
    func decodeNeighboursResponseInsufficientData() {
        let testData = Data([0x01, 0x00])  // Less than 4 bytes
        let tag = Data([0x01, 0x02, 0x03, 0x04])
        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeNeighboursResponse(from: testData, tag: tag, pubkeyPrefixLength: 4)
        }
    }

    @Test("Binary protocol push codes have correct values")
    func binaryProtocolPushCodes() {
        #expect(PushCode.binaryResponse.rawValue == 0x8C)
    }

    // MARK: - LPP Decoder Tests

    @Test("LPP type data sizes are correct")
    func lppTypeDataSizes() {
        // 1-byte types
        #expect(LPPType.digitalInput.dataSize == 1)
        #expect(LPPType.digitalOutput.dataSize == 1)
        #expect(LPPType.presence.dataSize == 1)
        #expect(LPPType.percentage.dataSize == 1)
        #expect(LPPType.switchValue.dataSize == 1)

        // 2-byte types
        #expect(LPPType.temperature.dataSize == 2)
        #expect(LPPType.humidity.dataSize == 2)
        #expect(LPPType.barometer.dataSize == 2)
        #expect(LPPType.voltage.dataSize == 2)
        #expect(LPPType.illuminance.dataSize == 2)
        #expect(LPPType.altitude.dataSize == 2)

        // 3-byte types
        #expect(LPPType.colour.dataSize == 3)

        // 4-byte types
        #expect(LPPType.genericSensor.dataSize == 4)

        // 6-byte types
        #expect(LPPType.accelerometer.dataSize == 6)
        #expect(LPPType.gyrometer.dataSize == 6)

        // 9-byte types
        #expect(LPPType.gps.dataSize == 9)
    }

    @Test("LPP decode temperature sensor")
    func lppDecodeTemperature() {
        // Channel 1, Temperature (103), 25.5C = 255 in Int16 (value * 10)
        var data = Data()
        data.append(0x01)  // channel
        data.append(LPPType.temperature.rawValue)  // type
        let tempRaw: Int16 = 255  // 25.5 * 10
        data.append(contentsOf: withUnsafeBytes(of: tempRaw.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].channel == 1)
        #expect(result[0].type == .temperature)
        if case .float(let value) = result[0].value {
            #expect(abs(value - 25.5) < 0.01)
        } else {
            Issue.record("Expected float value for temperature")
        }
    }

    @Test("LPP decode negative temperature")
    func lppDecodeNegativeTemperature() {
        var data = Data()
        data.append(0x02)  // channel
        data.append(LPPType.temperature.rawValue)
        let tempRaw: Int16 = -105  // -10.5 * 10
        data.append(contentsOf: withUnsafeBytes(of: tempRaw.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        if case .float(let value) = result[0].value {
            #expect(abs(value - (-10.5)) < 0.01)
        } else {
            Issue.record("Expected float value for temperature")
        }
    }

    @Test("LPP decode humidity sensor")
    func lppDecodeHumidity() {
        var data = Data()
        data.append(0x03)  // channel
        data.append(LPPType.humidity.rawValue)
        let humidityRaw: UInt16 = 130  // 65.0 * 2
        data.append(contentsOf: withUnsafeBytes(of: humidityRaw.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .humidity)
        if case .float(let value) = result[0].value {
            #expect(abs(value - 65.0) < 0.01)
        } else {
            Issue.record("Expected float value for humidity")
        }
    }

    @Test("LPP decode voltage sensor")
    func lppDecodeVoltage() {
        var data = Data()
        data.append(0x04)  // channel
        data.append(LPPType.voltage.rawValue)
        let voltageRaw: UInt16 = 420  // 4.20V * 100
        data.append(contentsOf: withUnsafeBytes(of: voltageRaw.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .voltage)
        if case .float(let value) = result[0].value {
            #expect(abs(value - 4.20) < 0.01)
        } else {
            Issue.record("Expected float value for voltage")
        }
    }

    @Test("LPP decode barometer sensor")
    func lppDecodeBarometer() {
        var data = Data()
        data.append(0x05)  // channel
        data.append(LPPType.barometer.rawValue)
        let baroRaw: UInt16 = 10132  // 1013.2 hPa * 10
        data.append(contentsOf: withUnsafeBytes(of: baroRaw.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .barometer)
        if case .float(let value) = result[0].value {
            #expect(abs(value - 1013.2) < 0.1)
        } else {
            Issue.record("Expected float value for barometer")
        }
    }

    @Test("LPP decode GPS coordinates")
    func lppDecodeGps() {
        var data = Data()
        data.append(0x06)  // channel
        data.append(LPPType.gps.rawValue)

        // Latitude: 37.7749 * 10000 = 377749
        let lat: Int32 = 377749
        data.append(UInt8(truncatingIfNeeded: lat))
        data.append(UInt8(truncatingIfNeeded: lat >> 8))
        data.append(UInt8(truncatingIfNeeded: lat >> 16))

        // Longitude: -122.4194 * 10000 = -1224194
        let lon: Int32 = -1224194
        data.append(UInt8(truncatingIfNeeded: lon))
        data.append(UInt8(truncatingIfNeeded: lon >> 8))
        data.append(UInt8(truncatingIfNeeded: lon >> 16))

        // Altitude: 10.5m * 100 = 1050
        let alt: Int32 = 1050
        data.append(UInt8(truncatingIfNeeded: alt))
        data.append(UInt8(truncatingIfNeeded: alt >> 8))
        data.append(UInt8(truncatingIfNeeded: alt >> 16))

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .gps)
        if case .gps(let latitude, let longitude, let altitude) = result[0].value {
            #expect(abs(latitude - 37.7749) < 0.001)
            #expect(abs(longitude - (-122.4194)) < 0.001)
            #expect(abs(altitude - 10.5) < 0.01)
        } else {
            Issue.record("Expected GPS value")
        }
    }

    @Test("LPP decode accelerometer")
    func lppDecodeAccelerometer() {
        var data = Data()
        data.append(0x07)  // channel
        data.append(LPPType.accelerometer.rawValue)

        // X: 0.5g = 500
        let x: Int16 = 500
        data.append(contentsOf: withUnsafeBytes(of: x.littleEndian) { Array($0) })

        // Y: -0.25g = -250
        let y: Int16 = -250
        data.append(contentsOf: withUnsafeBytes(of: y.littleEndian) { Array($0) })

        // Z: 1.0g = 1000
        let z: Int16 = 1000
        data.append(contentsOf: withUnsafeBytes(of: z.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .accelerometer)
        if case .vector3(let xVal, let yVal, let zVal) = result[0].value {
            #expect(abs(xVal - 0.5) < 0.001)
            #expect(abs(yVal - (-0.25)) < 0.001)
            #expect(abs(zVal - 1.0) < 0.001)
        } else {
            Issue.record("Expected vector3 value for accelerometer")
        }
    }

    @Test("LPP decode colour RGB")
    func lppDecodeColour() {
        var data = Data()
        data.append(0x08)  // channel
        data.append(LPPType.colour.rawValue)
        data.append(255)  // red
        data.append(128)  // green
        data.append(64)   // blue

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .colour)
        if case .rgb(let r, let g, let b) = result[0].value {
            #expect(r == 255)
            #expect(g == 128)
            #expect(b == 64)
        } else {
            Issue.record("Expected RGB value for colour")
        }
    }

    @Test("LPP decode digital input")
    func lppDecodeDigitalInput() {
        var data = Data()
        data.append(0x01)  // channel
        data.append(LPPType.digitalInput.rawValue)
        data.append(1)  // value = 1 (on)

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].type == .digitalInput)
        if case .integer(let value) = result[0].value {
            #expect(value == 1)
        } else {
            Issue.record("Expected integer value for digital input")
        }
    }

    @Test("LPP decode multiple sensors")
    func lppDecodeMultipleSensors() {
        var data = Data()

        // Temperature on channel 1
        data.append(0x01)
        data.append(LPPType.temperature.rawValue)
        let temp: Int16 = 200  // 20.0C
        data.append(contentsOf: withUnsafeBytes(of: temp.littleEndian) { Array($0) })

        // Humidity on channel 2
        data.append(0x02)
        data.append(LPPType.humidity.rawValue)
        let humidity: UInt16 = 100  // 50.0%
        data.append(contentsOf: withUnsafeBytes(of: humidity.littleEndian) { Array($0) })

        // Voltage on channel 3
        data.append(0x03)
        data.append(LPPType.voltage.rawValue)
        let voltage: UInt16 = 330  // 3.30V
        data.append(contentsOf: withUnsafeBytes(of: voltage.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        #expect(result.count == 3)
        #expect(result[0].channel == 1)
        #expect(result[0].type == .temperature)
        #expect(result[1].channel == 2)
        #expect(result[1].type == .humidity)
        #expect(result[2].channel == 3)
        #expect(result[2].type == .voltage)
    }

    @Test("LPP decode empty data returns empty array")
    func lppDecodeEmptyData() {
        let result = LPPDecoder.decode(Data())
        #expect(result.isEmpty)
    }

    @Test("LPP decode null-terminated data")
    func lppDecodeNullTerminated() {
        var data = Data()

        // Temperature on channel 1
        data.append(0x01)
        data.append(LPPType.temperature.rawValue)
        let temp: Int16 = 200
        data.append(contentsOf: withUnsafeBytes(of: temp.littleEndian) { Array($0) })

        // Null terminator
        data.append(0x00)

        // This should be ignored
        data.append(0x02)
        data.append(LPPType.humidity.rawValue)
        data.append(contentsOf: [0x64, 0x00])

        let result = LPPDecoder.decode(data)

        #expect(result.count == 1)
        #expect(result[0].channel == 1)
    }

    @Test("LPP decode skips unknown sensor type")
    func lppDecodeUnknownType() {
        var data = Data()

        // Unknown type (99)
        data.append(0x01)
        data.append(99)  // Unknown type

        // Valid temperature after unknown
        data.append(0x02)
        data.append(LPPType.temperature.rawValue)
        let temp: Int16 = 200
        data.append(contentsOf: withUnsafeBytes(of: temp.littleEndian) { Array($0) })

        let result = LPPDecoder.decode(data)

        // Should skip unknown and parse temperature
        #expect(result.count == 1)
        #expect(result[0].channel == 2)
        #expect(result[0].type == .temperature)
    }

    // MARK: - Telemetry Encoding Tests

    @Test("Encode self telemetry request")
    func encodeSelfTelemetryRequest() {
        let data = FrameCodec.encodeSelfTelemetryRequest()

        #expect(data.count == 4)
        #expect(data[0] == CommandCode.sendTelemetryRequest.rawValue)
        #expect(data[1] == 0x00)
        #expect(data[2] == 0x00)
        #expect(data[3] == 0x00)
    }

    @Test("Encode remote telemetry request")
    func encodeTelemetryRequest() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let data = FrameCodec.encodeTelemetryRequest(recipientPublicKey: publicKey)

        #expect(data.count == 36)
        #expect(data[0] == CommandCode.sendTelemetryRequest.rawValue)
        #expect(data[1] == 0x00)
        #expect(data[2] == 0x00)
        #expect(data[3] == 0x00)
        #expect(data.subdata(in: 4..<36) == publicKey)
    }

    @Test("Encode telemetry request truncates long public key")
    func encodeTelemetryRequestTruncatesKey() {
        let publicKey = Data(repeating: 0xAB, count: 64)  // Too long
        let data = FrameCodec.encodeTelemetryRequest(recipientPublicKey: publicKey)

        #expect(data.count == 36)
        #expect(data.subdata(in: 4..<36) == Data(repeating: 0xAB, count: 32))
    }

    // MARK: - Telemetry Decoding Tests

    @Test("Decode telemetry response with temperature")
    func decodeTelemetryResponseWithTemperature() throws {
        var testData = Data([PushCode.telemetryResponse.rawValue])
        testData.append(0x00)  // reserved

        // Public key prefix (6 bytes)
        testData.append(Data(repeating: 0xAB, count: 6))

        // LPP data: temperature on channel 1
        testData.append(0x01)  // channel
        testData.append(LPPType.temperature.rawValue)
        let temp: Int16 = 225  // 22.5C
        testData.append(contentsOf: withUnsafeBytes(of: temp.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeTelemetryResponse(from: testData)

        #expect(result.publicKeyPrefix == Data(repeating: 0xAB, count: 6))
        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].channel == 1)
        #expect(result.dataPoints[0].type == .temperature)
        if case .float(let value) = result.dataPoints[0].value {
            #expect(abs(value - 22.5) < 0.01)
        } else {
            Issue.record("Expected float value")
        }
    }

    @Test("Decode telemetry response with multiple sensors")
    func decodeTelemetryResponseMultipleSensors() throws {
        var testData = Data([PushCode.telemetryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xCD, count: 6))  // pubkey prefix

        // Temperature
        testData.append(0x01)
        testData.append(LPPType.temperature.rawValue)
        let temp: Int16 = 250
        testData.append(contentsOf: withUnsafeBytes(of: temp.littleEndian) { Array($0) })

        // Humidity
        testData.append(0x02)
        testData.append(LPPType.humidity.rawValue)
        let humidity: UInt16 = 110  // 55%
        testData.append(contentsOf: withUnsafeBytes(of: humidity.littleEndian) { Array($0) })

        // Voltage (battery)
        testData.append(0x03)
        testData.append(LPPType.voltage.rawValue)
        let voltage: UInt16 = 385  // 3.85V
        testData.append(contentsOf: withUnsafeBytes(of: voltage.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeTelemetryResponse(from: testData)

        #expect(result.publicKeyPrefix == Data(repeating: 0xCD, count: 6))
        #expect(result.dataPoints.count == 3)

        #expect(result.dataPoints[0].type == .temperature)
        #expect(result.dataPoints[1].type == .humidity)
        #expect(result.dataPoints[2].type == .voltage)
    }

    @Test("Decode telemetry response with GPS")
    func decodeTelemetryResponseWithGps() throws {
        var testData = Data([PushCode.telemetryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xEF, count: 6))  // pubkey prefix

        // GPS
        testData.append(0x01)
        testData.append(LPPType.gps.rawValue)

        // Lat: 40.7128 * 10000 = 407128
        let lat: Int32 = 407128
        testData.append(UInt8(truncatingIfNeeded: lat))
        testData.append(UInt8(truncatingIfNeeded: lat >> 8))
        testData.append(UInt8(truncatingIfNeeded: lat >> 16))

        // Lon: -74.0060 * 10000 = -740060
        let lon: Int32 = -740060
        testData.append(UInt8(truncatingIfNeeded: lon))
        testData.append(UInt8(truncatingIfNeeded: lon >> 8))
        testData.append(UInt8(truncatingIfNeeded: lon >> 16))

        // Alt: 10m * 100 = 1000
        let alt: Int32 = 1000
        testData.append(UInt8(truncatingIfNeeded: alt))
        testData.append(UInt8(truncatingIfNeeded: alt >> 8))
        testData.append(UInt8(truncatingIfNeeded: alt >> 16))

        let result = try FrameCodec.decodeTelemetryResponse(from: testData)

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].type == .gps)
        if case .gps(let latitude, let longitude, let altitude) = result.dataPoints[0].value {
            #expect(abs(latitude - 40.7128) < 0.001)
            #expect(abs(longitude - (-74.0060)) < 0.001)
            #expect(abs(altitude - 10.0) < 0.01)
        } else {
            Issue.record("Expected GPS value")
        }
    }

    @Test("Decode telemetry response with empty LPP data")
    func decodeTelemetryResponseEmpty() throws {
        var testData = Data([PushCode.telemetryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xAB, count: 6))  // pubkey prefix
        // No LPP data

        let result = try FrameCodec.decodeTelemetryResponse(from: testData)

        #expect(result.publicKeyPrefix == Data(repeating: 0xAB, count: 6))
        #expect(result.dataPoints.isEmpty)
    }

    @Test("Decode telemetry response with wrong push code throws error")
    func decodeTelemetryResponseWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(Data(repeating: 0, count: 10))

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeTelemetryResponse(from: testData)
        }
    }

    @Test("Decode telemetry response with insufficient data throws error")
    func decodeTelemetryResponseInsufficientData() {
        let testData = Data([PushCode.telemetryResponse.rawValue, 0x00, 0xAB])  // Only 3 bytes

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeTelemetryResponse(from: testData)
        }
    }

    @Test("Telemetry push code has correct value")
    func telemetryPushCode() {
        #expect(PushCode.telemetryResponse.rawValue == 0x8B)
    }

    @Test("Telemetry command code has correct value")
    func telemetryCommandCode() {
        #expect(CommandCode.sendTelemetryRequest.rawValue == 0x27)
    }

    // MARK: - Status Response Tests

    @Test("Decode status response push")
    func decodeStatusResponse() throws {
        var testData = Data([PushCode.statusResponse.rawValue])
        testData.append(0x00)  // reserved byte

        // Public key prefix (6 bytes)
        let pubkeyPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        testData.append(pubkeyPrefix)

        // Status data (52 bytes) - same structure as RemoteNodeStatus
        // batteryMillivolts (2)
        let battery: UInt16 = 4100
        testData.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })

        // txQueueLength (2)
        let txQueue: UInt16 = 3
        testData.append(contentsOf: withUnsafeBytes(of: txQueue.littleEndian) { Array($0) })

        // noiseFloor (2)
        let noise: Int16 = -115
        testData.append(contentsOf: withUnsafeBytes(of: noise.littleEndian) { Array($0) })

        // lastRssi (2)
        let rssi: Int16 = -75
        testData.append(contentsOf: withUnsafeBytes(of: rssi.littleEndian) { Array($0) })

        // packetsReceived (4)
        let packetsRx: UInt32 = 500
        testData.append(contentsOf: withUnsafeBytes(of: packetsRx.littleEndian) { Array($0) })

        // packetsSent (4)
        let packetsTx: UInt32 = 400
        testData.append(contentsOf: withUnsafeBytes(of: packetsTx.littleEndian) { Array($0) })

        // airtimeSeconds (4)
        let airtime: UInt32 = 1800
        testData.append(contentsOf: withUnsafeBytes(of: airtime.littleEndian) { Array($0) })

        // uptimeSeconds (4)
        let uptime: UInt32 = 43200
        testData.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })

        // sentFlood (4)
        let sentFlood: UInt32 = 50
        testData.append(contentsOf: withUnsafeBytes(of: sentFlood.littleEndian) { Array($0) })

        // sentDirect (4)
        let sentDirect: UInt32 = 350
        testData.append(contentsOf: withUnsafeBytes(of: sentDirect.littleEndian) { Array($0) })

        // receivedFlood (4)
        let receivedFlood: UInt32 = 100
        testData.append(contentsOf: withUnsafeBytes(of: receivedFlood.littleEndian) { Array($0) })

        // receivedDirect (4)
        let receivedDirect: UInt32 = 400
        testData.append(contentsOf: withUnsafeBytes(of: receivedDirect.littleEndian) { Array($0) })

        // fullEvents (2)
        let fullEvents: UInt16 = 2
        testData.append(contentsOf: withUnsafeBytes(of: fullEvents.littleEndian) { Array($0) })

        // lastSnr as Int16 * 4 (2)
        let snrRaw: Int16 = 36  // 9.0 dB * 4
        testData.append(contentsOf: withUnsafeBytes(of: snrRaw.littleEndian) { Array($0) })

        // directDuplicates (2)
        let directDups: UInt16 = 5
        testData.append(contentsOf: withUnsafeBytes(of: directDups.littleEndian) { Array($0) })

        // floodDuplicates (2)
        let floodDups: UInt16 = 15
        testData.append(contentsOf: withUnsafeBytes(of: floodDups.littleEndian) { Array($0) })

        // rxAirtimeSeconds (4)
        let rxAirtime: UInt32 = 900
        testData.append(contentsOf: withUnsafeBytes(of: rxAirtime.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeStatusResponse(from: testData)

        #expect(result.publicKeyPrefix == pubkeyPrefix)
        #expect(result.batteryMillivolts == 4100)
        #expect(result.txQueueLength == 3)
        #expect(result.noiseFloor == -115)
        #expect(result.lastRssi == -75)
        #expect(result.packetsReceived == 500)
        #expect(result.packetsSent == 400)
        #expect(result.airtimeSeconds == 1800)
        #expect(result.uptimeSeconds == 43200)
        #expect(result.sentFlood == 50)
        #expect(result.sentDirect == 350)
        #expect(result.receivedFlood == 100)
        #expect(result.receivedDirect == 400)
        #expect(result.fullEvents == 2)
        #expect(abs(result.lastSnr - 9.0) < 0.01)
        #expect(result.directDuplicates == 5)
        #expect(result.floodDuplicates == 15)
        #expect(result.rxAirtimeSeconds == 900)
    }

    @Test("Decode status response with wrong push code throws error")
    func decodeStatusResponseWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(Data(repeating: 0, count: 70))

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeStatusResponse(from: testData)
        }
    }

    @Test("Decode status response with insufficient data throws error")
    func decodeStatusResponseInsufficientData() {
        var testData = Data([PushCode.statusResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xAB, count: 6))  // pubkey prefix
        testData.append(Data(repeating: 0, count: 40))  // Only 40 bytes of status (need 52)

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeStatusResponse(from: testData)
        }
    }

    @Test("Status response push code has correct value")
    func statusResponsePushCode() {
        #expect(PushCode.statusResponse.rawValue == 0x87)
    }

    // MARK: - Path Discovery Tests

    @Test("Encode path discovery request")
    func encodePathDiscoveryRequest() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let data = FrameCodec.encodePathDiscovery(recipientPublicKey: publicKey)

        #expect(data.count == 34)
        #expect(data[0] == CommandCode.sendPathDiscoveryRequest.rawValue)
        #expect(data[1] == 0x00)  // reserved byte
        #expect(data.subdata(in: 2..<34) == publicKey)
    }

    @Test("Encode path discovery request truncates long public key")
    func encodePathDiscoveryRequestTruncatesKey() {
        let publicKey = Data(repeating: 0xCD, count: 64)  // Too long
        let data = FrameCodec.encodePathDiscovery(recipientPublicKey: publicKey)

        #expect(data.count == 34)
        #expect(data.subdata(in: 2..<34) == Data(repeating: 0xCD, count: 32))
    }

    @Test("Decode path discovery response with paths")
    func decodePathDiscoveryResponse() throws {
        var testData = Data([PushCode.pathDiscoveryResponse.rawValue])
        testData.append(0x00)  // reserved byte

        // Public key prefix (6 bytes)
        let pubkeyPrefix = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        testData.append(pubkeyPrefix)

        // Outbound path: length(1) + path data
        let outPath = Data([0xAA, 0xBB, 0xCC])
        testData.append(UInt8(outPath.count))
        testData.append(outPath)

        // Inbound path: length(1) + path data
        let inPath = Data([0xDD, 0xEE])
        testData.append(UInt8(inPath.count))
        testData.append(inPath)

        let result = try FrameCodec.decodePathDiscoveryResponse(from: testData)

        #expect(result.publicKeyPrefix == pubkeyPrefix)
        #expect(result.outboundPath == outPath)
        #expect(result.inboundPath == inPath)
    }

    @Test("Decode path discovery response with empty paths")
    func decodePathDiscoveryResponseEmptyPaths() throws {
        var testData = Data([PushCode.pathDiscoveryResponse.rawValue])
        testData.append(0x00)  // reserved byte

        // Public key prefix (6 bytes)
        testData.append(Data(repeating: 0xAB, count: 6))

        // Outbound path: length = 0
        testData.append(0x00)

        // Inbound path: length = 0
        testData.append(0x00)

        let result = try FrameCodec.decodePathDiscoveryResponse(from: testData)

        #expect(result.publicKeyPrefix == Data(repeating: 0xAB, count: 6))
        #expect(result.outboundPath.isEmpty)
        #expect(result.inboundPath.isEmpty)
    }

    @Test("Decode path discovery response with long paths")
    func decodePathDiscoveryResponseLongPaths() throws {
        var testData = Data([PushCode.pathDiscoveryResponse.rawValue])
        testData.append(0x00)  // reserved byte

        // Public key prefix (6 bytes)
        testData.append(Data(repeating: 0xEF, count: 6))

        // Outbound path: 10 hop path (each hop is a hash byte)
        let outPath = Data(repeating: 0x11, count: 10)
        testData.append(UInt8(outPath.count))
        testData.append(outPath)

        // Inbound path: 8 hop path
        let inPath = Data(repeating: 0x22, count: 8)
        testData.append(UInt8(inPath.count))
        testData.append(inPath)

        let result = try FrameCodec.decodePathDiscoveryResponse(from: testData)

        #expect(result.outboundPath.count == 10)
        #expect(result.inboundPath.count == 8)
        #expect(result.outboundPath == outPath)
        #expect(result.inboundPath == inPath)
    }

    @Test("Decode path discovery response with wrong push code throws error")
    func decodePathDiscoveryResponseWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(Data(repeating: 0, count: 15))

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodePathDiscoveryResponse(from: testData)
        }
    }

    @Test("Decode path discovery response with insufficient data throws error")
    func decodePathDiscoveryResponseInsufficientData() {
        // Less than 10 bytes (1 + 1 + 6 + 1 + 1 = 10 minimum)
        let testData = Data([PushCode.pathDiscoveryResponse.rawValue, 0x00, 0x01, 0x02, 0x03])

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodePathDiscoveryResponse(from: testData)
        }
    }

    @Test("Decode path discovery response with truncated outbound path throws error")
    func decodePathDiscoveryResponseTruncatedOutPath() {
        var testData = Data([PushCode.pathDiscoveryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xAB, count: 6))  // pubkey prefix
        testData.append(0x05)  // outPath length = 5, but only 2 bytes follow
        testData.append(contentsOf: [0x01, 0x02])

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodePathDiscoveryResponse(from: testData)
        }
    }

    @Test("Decode path discovery response with truncated inbound path throws error")
    func decodePathDiscoveryResponseTruncatedInPath() {
        var testData = Data([PushCode.pathDiscoveryResponse.rawValue])
        testData.append(0x00)  // reserved
        testData.append(Data(repeating: 0xAB, count: 6))  // pubkey prefix
        testData.append(0x02)  // outPath length = 2
        testData.append(contentsOf: [0x01, 0x02])  // outPath data
        testData.append(0x05)  // inPath length = 5, but only 1 byte follows
        testData.append(0x03)

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodePathDiscoveryResponse(from: testData)
        }
    }

    @Test("Path discovery push code has correct value")
    func pathDiscoveryPushCode() {
        #expect(PushCode.pathDiscoveryResponse.rawValue == 0x8D)
    }

    @Test("Path discovery command code has correct value")
    func pathDiscoveryCommandCode() {
        #expect(CommandCode.sendPathDiscoveryRequest.rawValue == 0x34)
    }

    // MARK: - Trace Encoding Tests

    @Test("Encode trace packet with explicit tag")
    func encodeTraceWithTag() {
        let data = FrameCodec.encodeTrace(
            tag: 0x12345678,
            authCode: 0xABCDEF01,
            flags: 0x05
        )

        #expect(data.count == 10)
        #expect(data[0] == CommandCode.sendTracePath.rawValue)

        // Tag (little-endian)
        let tag = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(tag == 0x12345678)

        // AuthCode (little-endian)
        let authCode = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(authCode == 0xABCDEF01)

        // Flags
        #expect(data[9] == 0x05)
    }

    @Test("Encode trace packet with path data")
    func encodeTraceWithPath() {
        let path = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let data = FrameCodec.encodeTrace(
            tag: 0x11111111,
            authCode: 0x22222222,
            flags: 0x00,
            path: path
        )

        #expect(data.count == 14)
        #expect(data[0] == CommandCode.sendTracePath.rawValue)
        #expect(data.suffix(4) == path)
    }

    @Test("Encode trace packet generates random tag when not provided")
    func encodeTraceRandomTag() {
        let data1 = FrameCodec.encodeTrace()
        let data2 = FrameCodec.encodeTrace()

        // Tags should be different (random)
        let tag1 = data1.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let tag2 = data2.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        // Tags should be non-zero (random in 1...UInt32.max)
        #expect(tag1 != 0)
        #expect(tag2 != 0)
        // Very unlikely to be equal
        #expect(tag1 != tag2)
    }

    @Test("Encode trace packet with default values")
    func encodeTraceDefaults() {
        let data = FrameCodec.encodeTrace(tag: 0x99999999)

        #expect(data.count == 10)
        #expect(data[0] == CommandCode.sendTracePath.rawValue)

        // AuthCode should be 0
        let authCode = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(authCode == 0)

        // Flags should be 0
        #expect(data[9] == 0x00)
    }

    // MARK: - Trace Decoding Tests

    @Test("Decode trace data with path nodes")
    func decodeTraceDataWithPath() throws {
        var testData = Data([PushCode.traceData.rawValue])
        testData.append(0x00)  // reserved byte

        // Path length = 3 nodes
        testData.append(0x03)

        // Flags
        testData.append(0x01)

        // Tag (little-endian)
        let tag: UInt32 = 0x12345678
        testData.append(contentsOf: withUnsafeBytes(of: tag.littleEndian) { Array($0) })

        // AuthCode (little-endian)
        let authCode: UInt32 = 0xABCDEF01
        testData.append(contentsOf: withUnsafeBytes(of: authCode.littleEndian) { Array($0) })

        // Hash bytes for 3 nodes
        testData.append(0xAA)  // node 1 hash
        testData.append(0xBB)  // node 2 hash
        testData.append(0xCC)  // node 3 hash

        // SNR bytes for 3 nodes (as Int8 * 4)
        testData.append(UInt8(bitPattern: Int8(32)))   // 8.0 dB * 4
        testData.append(UInt8(bitPattern: Int8(-20)))  // -5.0 dB * 4
        testData.append(UInt8(bitPattern: Int8(48)))   // 12.0 dB * 4

        // Final SNR
        testData.append(UInt8(bitPattern: Int8(24)))   // 6.0 dB * 4

        let result = try FrameCodec.decodeTraceData(from: testData)

        #expect(result.tag == 0x12345678)
        #expect(result.authCode == 0xABCDEF01)
        #expect(result.flags == 0x01)
        #expect(result.path.count == 3)

        #expect(result.path[0].hashByte == 0xAA)
        #expect(abs(result.path[0].snr - 8.0) < 0.01)

        #expect(result.path[1].hashByte == 0xBB)
        #expect(abs(result.path[1].snr - (-5.0)) < 0.01)

        #expect(result.path[2].hashByte == 0xCC)
        #expect(abs(result.path[2].snr - 12.0) < 0.01)

        #expect(abs(result.finalSnr - 6.0) < 0.01)
    }

    @Test("Decode trace data with empty path")
    func decodeTraceDataEmptyPath() throws {
        var testData = Data([PushCode.traceData.rawValue])
        testData.append(0x00)  // reserved byte

        // Path length = 0
        testData.append(0x00)

        // Flags
        testData.append(0x00)

        // Tag (little-endian)
        let tag: UInt32 = 0x11111111
        testData.append(contentsOf: withUnsafeBytes(of: tag.littleEndian) { Array($0) })

        // AuthCode (little-endian)
        let authCode: UInt32 = 0x22222222
        testData.append(contentsOf: withUnsafeBytes(of: authCode.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeTraceData(from: testData)

        #expect(result.tag == 0x11111111)
        #expect(result.authCode == 0x22222222)
        #expect(result.flags == 0x00)
        #expect(result.path.isEmpty)
        #expect(result.finalSnr == 0.0)
    }

    @Test("Decode trace data with negative SNR values")
    func decodeTraceDataNegativeSnr() throws {
        var testData = Data([PushCode.traceData.rawValue])
        testData.append(0x00)  // reserved byte

        // Path length = 2 nodes
        testData.append(0x02)

        // Flags
        testData.append(0x00)

        // Tag
        let tag: UInt32 = 0x33333333
        testData.append(contentsOf: withUnsafeBytes(of: tag.littleEndian) { Array($0) })

        // AuthCode
        let authCode: UInt32 = 0x44444444
        testData.append(contentsOf: withUnsafeBytes(of: authCode.littleEndian) { Array($0) })

        // Hash bytes
        testData.append(0x11)
        testData.append(0x22)

        // SNR bytes (negative values)
        testData.append(UInt8(bitPattern: Int8(-40)))  // -10.0 dB * 4
        testData.append(UInt8(bitPattern: Int8(-8)))   // -2.0 dB * 4

        // Final SNR (negative)
        testData.append(UInt8(bitPattern: Int8(-24)))  // -6.0 dB * 4

        let result = try FrameCodec.decodeTraceData(from: testData)

        #expect(abs(result.path[0].snr - (-10.0)) < 0.01)
        #expect(abs(result.path[1].snr - (-2.0)) < 0.01)
        #expect(abs(result.finalSnr - (-6.0)) < 0.01)
    }

    @Test("Decode trace data with wrong push code throws error")
    func decodeTraceDataWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(Data(repeating: 0, count: 15))

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeTraceData(from: testData)
        }
    }

    @Test("Decode trace data with insufficient data throws error")
    func decodeTraceDataInsufficientData() {
        // Less than 12 bytes
        let testData = Data([PushCode.traceData.rawValue, 0x00, 0x00, 0x00, 0x01, 0x02])

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeTraceData(from: testData)
        }
    }

    @Test("Trace push code has correct value")
    func tracePushCode() {
        #expect(PushCode.traceData.rawValue == 0x89)
    }

    @Test("Trace command code has correct value")
    func traceCommandCode() {
        #expect(CommandCode.sendTracePath.rawValue == 0x24)
    }

    // MARK: - Control Data Protocol Tests

    @Test("Control data type values are correct")
    func controlDataTypeValues() {
        #expect(ControlDataType.nodeDiscoverRequest.rawValue == 0x80)
        #expect(ControlDataType.nodeDiscoverResponse.rawValue == 0x90)
    }

    @Test("Encode control data packet")
    func encodeControlData() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let data = FrameCodec.encodeControlData(controlType: 0x81, payload: payload)

        #expect(data.count == 6)
        #expect(data[0] == CommandCode.sendControlData.rawValue)
        #expect(data[1] == 0x81)
        #expect(data.suffix(4) == payload)
    }

    @Test("Encode control data with empty payload")
    func encodeControlDataEmptyPayload() {
        let data = FrameCodec.encodeControlData(controlType: 0x90, payload: Data())

        #expect(data.count == 2)
        #expect(data[0] == CommandCode.sendControlData.rawValue)
        #expect(data[1] == 0x90)
    }

    @Test("Encode node discover request with default values")
    func encodeNodeDiscoverRequestDefaults() {
        let data = FrameCodec.encodeNodeDiscoverRequest(tag: 0x12345678)

        // Format: command(1) + controlType(1) + filter(1) + tag(4) = 7 bytes
        #expect(data.count == 7)
        #expect(data[0] == CommandCode.sendControlData.rawValue)
        // controlType = 0x80 | 0x01 (prefixOnly flag)
        #expect(data[1] == 0x81)
        #expect(data[2] == 0x00)  // filter = 0

        let tag = data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(tag == 0x12345678)
    }

    @Test("Encode node discover request with filter")
    func encodeNodeDiscoverRequestWithFilter() {
        let data = FrameCodec.encodeNodeDiscoverRequest(
            filter: 0x02,  // Repeater nodes only
            prefixOnly: false,
            tag: 0xABCDEF01
        )

        #expect(data[0] == CommandCode.sendControlData.rawValue)
        // controlType = 0x80 | 0x00 (no prefixOnly flag)
        #expect(data[1] == 0x80)
        #expect(data[2] == 0x02)  // filter

        let tag = data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(tag == 0xABCDEF01)
    }

    @Test("Encode node discover request with since timestamp")
    func encodeNodeDiscoverRequestWithSince() {
        let data = FrameCodec.encodeNodeDiscoverRequest(
            filter: 0x01,
            prefixOnly: true,
            tag: 0x11111111,
            since: 1733500000
        )

        // Format: command(1) + controlType(1) + filter(1) + tag(4) + since(4) = 11 bytes
        #expect(data.count == 11)

        let tag = data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(tag == 0x11111111)

        let since = data.subdata(in: 7..<11).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        #expect(since == 1733500000)
    }

    @Test("Encode node discover request generates random tag")
    func encodeNodeDiscoverRequestRandomTag() {
        let data1 = FrameCodec.encodeNodeDiscoverRequest()
        let data2 = FrameCodec.encodeNodeDiscoverRequest()

        let tag1 = data1.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let tag2 = data2.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        // Tags should be non-zero
        #expect(tag1 != 0)
        #expect(tag2 != 0)
        // Very unlikely to be equal
        #expect(tag1 != tag2)
    }

    @Test("Decode control data push")
    func decodeControlData() throws {
        var testData = Data([PushCode.controlData.rawValue])
        testData.append(UInt8(bitPattern: Int8(32)))   // SNR = 8.0 * 4
        testData.append(UInt8(bitPattern: Int8(-70)))  // RSSI = -70
        testData.append(0x03)  // path length
        testData.append(contentsOf: [0x91, 0x01, 0x02, 0x03, 0x04, 0x05])  // payload

        let result = try FrameCodec.decodeControlData(from: testData)

        #expect(abs(result.snr - 8.0) < 0.01)
        #expect(result.rssi == -70)
        #expect(result.pathLength == 3)
        #expect(result.payloadType == 0x91)
        #expect(result.payload == Data([0x91, 0x01, 0x02, 0x03, 0x04, 0x05]))
    }

    @Test("Decode control data with empty payload")
    func decodeControlDataEmptyPayload() throws {
        var testData = Data([PushCode.controlData.rawValue])
        testData.append(UInt8(bitPattern: Int8(-20)))  // SNR = -5.0 * 4
        testData.append(UInt8(bitPattern: Int8(-80)))  // RSSI = -80
        testData.append(0x00)  // path length

        let result = try FrameCodec.decodeControlData(from: testData)

        #expect(abs(result.snr - (-5.0)) < 0.01)
        #expect(result.rssi == -80)
        #expect(result.pathLength == 0)
        #expect(result.payloadType == 0)
        #expect(result.payload.isEmpty)
    }

    @Test("Decode control data with negative SNR")
    func decodeControlDataNegativeSnr() throws {
        var testData = Data([PushCode.controlData.rawValue])
        testData.append(UInt8(bitPattern: Int8(-40)))  // SNR = -10.0 * 4
        testData.append(UInt8(bitPattern: Int8(-90)))  // RSSI
        testData.append(0x05)  // path length
        testData.append(0x80)  // payload type

        let result = try FrameCodec.decodeControlData(from: testData)

        #expect(abs(result.snr - (-10.0)) < 0.01)
    }

    @Test("Decode control data with wrong push code throws error")
    func decodeControlDataWrongCode() {
        var testData = Data([PushCode.advert.rawValue])  // Wrong code
        testData.append(Data(repeating: 0, count: 10))

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeControlData(from: testData)
        }
    }

    @Test("Decode control data with insufficient data throws error")
    func decodeControlDataInsufficientData() {
        let testData = Data([PushCode.controlData.rawValue, 0x00, 0x00])  // Only 3 bytes

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeControlData(from: testData)
        }
    }

    @Test("Decode node discover response from control data")
    func decodeNodeDiscoverResponse() throws {
        // Build a control data packet that contains a node discover response
        let controlData = ControlDataPacket(
            snr: 10.0,
            rssi: -65,
            pathLength: 2,
            payloadType: 0x92,  // 0x90 | 0x02 (node type = 2)
            payload: Data([
                0x92,        // type byte (included in payload)
                0x18,        // snrIn = 6.0 * 4
                0x78, 0x56, 0x34, 0x12,  // tag (little-endian)
                0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF  // public key prefix
            ])
        )

        let result = try FrameCodec.decodeNodeDiscoverResponse(from: controlData)

        #expect(result != nil)
        #expect(result!.snr == 10.0)
        #expect(result!.rssi == -65)
        #expect(result!.pathLength == 2)
        #expect(result!.nodeType == 2)
        #expect(abs(result!.snrIn - 6.0) < 0.01)
        #expect(result!.tag == Data([0x78, 0x56, 0x34, 0x12]))
        #expect(result!.publicKey == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
    }

    @Test("Decode node discover response with full public key")
    func decodeNodeDiscoverResponseFullKey() throws {
        let fullPublicKey = Data(repeating: 0xAB, count: 32)
        var payload = Data()
        payload.append(0x91)  // type: 0x90 | 0x01 (node type = 1)
        payload.append(UInt8(bitPattern: Int8(40)))  // snrIn = 10.0 * 4
        payload.append(contentsOf: [0x01, 0x02, 0x03, 0x04])  // tag
        payload.append(fullPublicKey)

        let controlData = ControlDataPacket(
            snr: 5.0,
            rssi: -75,
            pathLength: 0,
            payloadType: 0x91,
            payload: payload
        )

        let result = try FrameCodec.decodeNodeDiscoverResponse(from: controlData)

        #expect(result != nil)
        #expect(result!.nodeType == 1)
        #expect(result!.publicKey == fullPublicKey)
    }

    @Test("Decode node discover response with negative SNR values")
    func decodeNodeDiscoverResponseNegativeSnr() throws {
        let controlData = ControlDataPacket(
            snr: -8.0,
            rssi: -95,
            pathLength: 5,
            payloadType: 0x90,  // node type = 0
            payload: Data([
                0x90,        // type byte
                0xE0,        // snrIn = -8.0 * 4 = -32
                0x11, 0x22, 0x33, 0x44,  // tag
                0x01, 0x02, 0x03, 0x04   // public key prefix
            ])
        )

        let result = try FrameCodec.decodeNodeDiscoverResponse(from: controlData)

        #expect(result != nil)
        #expect(result!.snr == -8.0)
        #expect(abs(result!.snrIn - (-8.0)) < 0.01)
    }

    @Test("Decode node discover response returns nil for non-discover payload")
    func decodeNodeDiscoverResponseNonDiscover() throws {
        // Payload type 0x80 is node discover request, not response
        let controlData = ControlDataPacket(
            snr: 5.0,
            rssi: -70,
            pathLength: 1,
            payloadType: 0x80,  // This is a request, not response
            payload: Data([0x80, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        )

        let result = try FrameCodec.decodeNodeDiscoverResponse(from: controlData)

        #expect(result == nil)
    }

    @Test("Decode node discover response with insufficient payload throws error")
    func decodeNodeDiscoverResponseInsufficientPayload() {
        let controlData = ControlDataPacket(
            snr: 5.0,
            rssi: -70,
            pathLength: 1,
            payloadType: 0x91,
            payload: Data([0x91, 0x20, 0x01, 0x02])  // Only 4 bytes, need at least 6
        )

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeNodeDiscoverResponse(from: controlData)
        }
    }

    @Test("Control data push code has correct value")
    func controlDataPushCode() {
        #expect(PushCode.controlData.rawValue == 0x8E)
    }

    @Test("Control data command code has correct value")
    func controlDataCommandCode() {
        #expect(CommandCode.sendControlData.rawValue == 0x37)
    }

    // MARK: - Flood Scope Encoding Tests

    @Test("Encode flood scope with hash scope (starts with #)")
    func encodeFloodScopeWithHash() {
        let data = FrameCodec.encodeSetFloodScope("#my-network")

        // Format: command(1) + reserved(1) + scopeKey(16) = 18 bytes
        #expect(data.count == 18)
        #expect(data[0] == CommandCode.setFloodScope.rawValue)
        #expect(data[1] == 0x00)  // reserved byte

        // The scope key should be first 16 bytes of SHA256("#my-network")
        // Verify it's not all zeros (disabled)
        let scopeKey = data.suffix(16)
        #expect(scopeKey != Data(repeating: 0, count: 16))
    }

    @Test("Encode flood scope with empty string (disable)")
    func encodeFloodScopeEmpty() {
        let data = FrameCodec.encodeSetFloodScope("")

        #expect(data.count == 18)
        #expect(data[0] == CommandCode.setFloodScope.rawValue)
        #expect(data[1] == 0x00)

        // Scope key should be all zeros (disabled)
        let scopeKey = data.suffix(16)
        #expect(scopeKey == Data(repeating: 0, count: 16))
    }

    @Test("Encode flood scope with zero string (disable)")
    func encodeFloodScopeZero() {
        let data = FrameCodec.encodeSetFloodScope("0")

        #expect(data.count == 18)
        let scopeKey = data.suffix(16)
        #expect(scopeKey == Data(repeating: 0, count: 16))
    }

    @Test("Encode flood scope with None (disable)")
    func encodeFloodScopeNone() {
        let data = FrameCodec.encodeSetFloodScope("None")

        #expect(data.count == 18)
        let scopeKey = data.suffix(16)
        #expect(scopeKey == Data(repeating: 0, count: 16))
    }

    @Test("Encode flood scope with asterisk (disable)")
    func encodeFloodScopeAsterisk() {
        let data = FrameCodec.encodeSetFloodScope("*")

        #expect(data.count == 18)
        let scopeKey = data.suffix(16)
        #expect(scopeKey == Data(repeating: 0, count: 16))
    }

    @Test("Encode flood scope with raw key (short, padded)")
    func encodeFloodScopeRawKeyShort() {
        let data = FrameCodec.encodeSetFloodScope("test")

        #expect(data.count == 18)
        #expect(data[0] == CommandCode.setFloodScope.rawValue)

        // "test" = 4 bytes, should be padded to 16 bytes
        let scopeKey = data.suffix(16)
        let expectedKey = "test".data(using: .utf8)! + Data(repeating: 0, count: 12)
        #expect(scopeKey == expectedKey)
    }

    @Test("Encode flood scope with raw key (exact 16 bytes)")
    func encodeFloodScopeRawKeyExact() {
        let rawKey = "exactly16chars!!"  // 16 characters
        let data = FrameCodec.encodeSetFloodScope(rawKey)

        #expect(data.count == 18)
        let scopeKey = data.suffix(16)
        #expect(scopeKey == rawKey.data(using: .utf8)!)
    }

    @Test("Encode flood scope with raw key (truncated)")
    func encodeFloodScopeRawKeyLong() {
        let rawKey = "this is a very long key that needs truncation"
        let data = FrameCodec.encodeSetFloodScope(rawKey)

        #expect(data.count == 18)
        let scopeKey = data.suffix(16)
        // Should be truncated to first 16 bytes
        #expect(scopeKey == rawKey.data(using: .utf8)!.prefix(16))
    }

    @Test("Encode flood scope hash produces consistent results")
    func encodeFloodScopeHashConsistent() {
        let data1 = FrameCodec.encodeSetFloodScope("#my-scope")
        let data2 = FrameCodec.encodeSetFloodScope("#my-scope")

        // Same input should produce same output
        #expect(data1 == data2)
    }

    @Test("Encode flood scope hash produces different results for different inputs")
    func encodeFloodScopeHashDifferent() {
        let data1 = FrameCodec.encodeSetFloodScope("#scope-a")
        let data2 = FrameCodec.encodeSetFloodScope("#scope-b")

        // Different inputs should produce different outputs
        #expect(data1.suffix(16) != data2.suffix(16))
    }

    @Test("Flood scope command code has correct value")
    func floodScopeCommandCode() {
        #expect(CommandCode.setFloodScope.rawValue == 0x36)
    }

    // MARK: - Custom Variables Tests

    @Test("Encode get custom variables request")
    func encodeGetCustomVars() {
        let data = FrameCodec.encodeGetCustomVars()

        #expect(data.count == 1)
        #expect(data[0] == CommandCode.getCustomVars.rawValue)
    }

    @Test("Encode set custom variable")
    func encodeSetCustomVar() {
        let data = FrameCodec.encodeSetCustomVar(key: "myKey", value: "myValue")

        #expect(data[0] == CommandCode.setCustomVar.rawValue)
        let payload = String(data: data.suffix(from: 1), encoding: .utf8)
        #expect(payload == "myKey:myValue")
    }

    @Test("Encode set custom variable with special characters in value")
    func encodeSetCustomVarSpecialChars() {
        let data = FrameCodec.encodeSetCustomVar(key: "url", value: "https://example.com:8080")

        #expect(data[0] == CommandCode.setCustomVar.rawValue)
        let payload = String(data: data.suffix(from: 1), encoding: .utf8)
        #expect(payload == "url:https://example.com:8080")
    }

    @Test("Decode custom variables response with multiple pairs")
    func decodeCustomVarsMultiple() throws {
        var testData = Data([ResponseCode.customVars.rawValue])
        testData.append("key1:value1,key2:value2,key3:value3".data(using: .utf8)!)

        let result = try FrameCodec.decodeCustomVars(from: testData)

        #expect(result.count == 3)
        #expect(result["key1"] == "value1")
        #expect(result["key2"] == "value2")
        #expect(result["key3"] == "value3")
    }

    @Test("Decode custom variables response with single pair")
    func decodeCustomVarsSingle() throws {
        var testData = Data([ResponseCode.customVars.rawValue])
        testData.append("name:TestDevice".data(using: .utf8)!)

        let result = try FrameCodec.decodeCustomVars(from: testData)

        #expect(result.count == 1)
        #expect(result["name"] == "TestDevice")
    }

    @Test("Decode custom variables response with empty data")
    func decodeCustomVarsEmpty() throws {
        let testData = Data([ResponseCode.customVars.rawValue])

        let result = try FrameCodec.decodeCustomVars(from: testData)

        #expect(result.isEmpty)
    }

    @Test("Decode custom variables response with value containing colon")
    func decodeCustomVarsColonInValue() throws {
        var testData = Data([ResponseCode.customVars.rawValue])
        testData.append("url:http://example.com:8080".data(using: .utf8)!)

        let result = try FrameCodec.decodeCustomVars(from: testData)

        #expect(result.count == 1)
        #expect(result["url"] == "http://example.com:8080")
    }

    @Test("Decode custom variables response with wrong response code throws error")
    func decodeCustomVarsWrongCode() {
        var testData = Data([ResponseCode.ok.rawValue])
        testData.append("key:value".data(using: .utf8)!)

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeCustomVars(from: testData)
        }
    }

    @Test("Custom variables command codes have correct values")
    func customVarsCommandCodes() {
        #expect(CommandCode.getCustomVars.rawValue == 0x28)
        #expect(CommandCode.setCustomVar.rawValue == 0x29)
    }

    @Test("Custom variables response code has correct value")
    func customVarsResponseCode() {
        #expect(ResponseCode.customVars.rawValue == 0x15)
    }

    // MARK: - Status Request Tests

    @Test("Encode status request")
    func encodeStatusRequest() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let data = FrameCodec.encodeStatusRequest(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data[0] == CommandCode.sendStatusRequest.rawValue)
        #expect(data.subdata(in: 1..<33) == publicKey)
    }

    @Test("Encode status request truncates long public key")
    func encodeStatusRequestTruncatesKey() {
        let publicKey = Data(repeating: 0xCD, count: 64)  // Too long
        let data = FrameCodec.encodeStatusRequest(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data[0] == CommandCode.sendStatusRequest.rawValue)
        #expect(data.subdata(in: 1..<33) == Data(repeating: 0xCD, count: 32))
    }

    @Test("Status request command code has correct value")
    func statusRequestCommandCode() {
        #expect(CommandCode.sendStatusRequest.rawValue == 0x1B)
    }

    // MARK: - Has Connection Tests

    @Test("Encode has connection query")
    func encodeHasConnection() {
        let publicKey = Data(repeating: 0xEF, count: 32)
        let data = FrameCodec.encodeHasConnection(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data[0] == CommandCode.hasConnection.rawValue)
        #expect(data.subdata(in: 1..<33) == publicKey)
    }

    @Test("Encode has connection truncates long public key")
    func encodeHasConnectionTruncatesKey() {
        let publicKey = Data(repeating: 0x12, count: 48)  // Too long
        let data = FrameCodec.encodeHasConnection(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data.subdata(in: 1..<33) == Data(repeating: 0x12, count: 32))
    }

    @Test("Decode has connection response true")
    func decodeHasConnectionResponseTrue() throws {
        let testData = Data([ResponseCode.hasConnection.rawValue, 0x01])

        let result = try FrameCodec.decodeHasConnectionResponse(from: testData)

        #expect(result == true)
    }

    @Test("Decode has connection response false")
    func decodeHasConnectionResponseFalse() throws {
        let testData = Data([ResponseCode.hasConnection.rawValue, 0x00])

        let result = try FrameCodec.decodeHasConnectionResponse(from: testData)

        #expect(result == false)
    }

    @Test("Decode has connection response with non-zero value returns true")
    func decodeHasConnectionResponseNonZero() throws {
        let testData = Data([ResponseCode.hasConnection.rawValue, 0xFF])

        let result = try FrameCodec.decodeHasConnectionResponse(from: testData)

        #expect(result == true)
    }

    @Test("Decode has connection response with wrong response code throws error")
    func decodeHasConnectionResponseWrongCode() {
        let testData = Data([ResponseCode.ok.rawValue, 0x01])

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeHasConnectionResponse(from: testData)
        }
    }

    @Test("Decode has connection response with insufficient data throws error")
    func decodeHasConnectionResponseInsufficientData() {
        let testData = Data([ResponseCode.hasConnection.rawValue])  // Only 1 byte

        #expect(throws: ProtocolError.self) {
            _ = try FrameCodec.decodeHasConnectionResponse(from: testData)
        }
    }

    @Test("Has connection command code has correct value")
    func hasConnectionCommandCode() {
        #expect(CommandCode.hasConnection.rawValue == 0x1C)
    }

    @Test("Has connection response code has correct value")
    func hasConnectionResponseCode() {
        #expect(ResponseCode.hasConnection.rawValue == 0x19)
    }

    // MARK: - Logout Tests

    @Test("Encode logout command")
    func encodeLogout() {
        let publicKey = Data(repeating: 0x34, count: 32)
        let data = FrameCodec.encodeLogout(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data[0] == CommandCode.logout.rawValue)
        #expect(data.subdata(in: 1..<33) == publicKey)
    }

    @Test("Encode logout truncates long public key")
    func encodeLogoutTruncatesKey() {
        let publicKey = Data(repeating: 0x56, count: 40)  // Too long
        let data = FrameCodec.encodeLogout(recipientPublicKey: publicKey)

        #expect(data.count == 33)
        #expect(data.subdata(in: 1..<33) == Data(repeating: 0x56, count: 32))
    }

    @Test("Logout command code has correct value")
    func logoutCommandCode() {
        #expect(CommandCode.logout.rawValue == 0x1D)
    }
}
