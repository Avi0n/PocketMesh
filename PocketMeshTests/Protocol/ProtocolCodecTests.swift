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
        #expect(result.lastSNR == 40)
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
}
