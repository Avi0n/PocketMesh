import Foundation
import Testing
@testable import MeshCore

// MARK: - Full Parse Tests (via PacketParser.parse)

@Suite("PacketParser Integration Tests")
struct PacketParserIntegrationTests {

    @Test("Parse OK response without value")
    func parseOKWithoutValue() {
        let data = Data([0x00])
        let event = PacketParser.parse(data)

        guard case .ok(let value) = event else {
            Issue.record("Expected .ok event, got \(event)")
            return
        }
        #expect(value == nil)
    }

    @Test("Parse OK response with value")
    func parseOKWithValue() {
        let data = Data([0x00, 0x2A, 0x00, 0x00, 0x00]) // value = 42
        let event = PacketParser.parse(data)

        guard case .ok(let value) = event else {
            Issue.record("Expected .ok event, got \(event)")
            return
        }
        #expect(value == 42)
    }

    @Test("Parse error response")
    func parseError() {
        let data = Data([0x01, 0x05]) // error code 5
        let event = PacketParser.parse(data)

        guard case .error(let code) = event else {
            Issue.record("Expected .error event, got \(event)")
            return
        }
        #expect(code == 5)
    }

    @Test("Parse message sent")
    func parseMessageSent() {
        let data = Data([0x06, 0x00, 0xDE, 0xAD, 0xBE, 0xEF, 0xE8, 0x03, 0x00, 0x00])
        let event = PacketParser.parse(data)

        guard case .messageSent(let info) = event else {
            Issue.record("Expected .messageSent event, got \(event)")
            return
        }
        #expect(info.type == 0)
        #expect(info.expectedAck == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(info.suggestedTimeoutMs == 1000)
    }

    @Test("Parse acknowledgement")
    func parseAck() {
        let data = Data([0x82, 0xDE, 0xAD, 0xBE, 0xEF])
        let event = PacketParser.parse(data)

        guard case .acknowledgement(let code) = event else {
            Issue.record("Expected .acknowledgement event, got \(event)")
            return
        }
        #expect(code == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("Parse no more messages")
    func parseNoMoreMessages() {
        let data = Data([0x0A])
        let event = PacketParser.parse(data)

        guard case .noMoreMessages = event else {
            Issue.record("Expected .noMoreMessages event, got \(event)")
            return
        }
    }

    @Test("Parse messages waiting")
    func parseMessagesWaiting() {
        let data = Data([0x83])
        let event = PacketParser.parse(data)

        guard case .messagesWaiting = event else {
            Issue.record("Expected .messagesWaiting event, got \(event)")
            return
        }
    }

    @Test("Parse battery response basic")
    func parseBatteryBasic() {
        var data = Data([0x0C]) // Battery response code
        data.append(TestFixtures.batteryBasicPayload)
        let event = PacketParser.parse(data)

        guard case .battery(let info) = event else {
            Issue.record("Expected .battery event, got \(event)")
            return
        }
        #expect(info.level == 4200)
        #expect(info.usedStorageKB == nil)
        #expect(info.totalStorageKB == nil)
    }

    @Test("Parse battery response extended")
    func parseBatteryExtended() {
        var data = Data([0x0C]) // Battery response code
        data.append(TestFixtures.batteryExtendedPayload)
        let event = PacketParser.parse(data)

        guard case .battery(let info) = event else {
            Issue.record("Expected .battery event, got \(event)")
            return
        }
        #expect(info.level == 4200)
        #expect(info.usedStorageKB == 1024)
        #expect(info.totalStorageKB == 4096)
    }

    @Test("Parse current time")
    func parseCurrentTime() {
        var data = Data([0x09]) // CurrentTime response code
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })
        let event = PacketParser.parse(data)

        guard case .currentTime(let date) = event else {
            Issue.record("Expected .currentTime event, got \(event)")
            return
        }
        #expect(date.timeIntervalSince1970 == 1700000000)
    }

    @Test("Parse contacts start")
    func parseContactsStart() {
        var data = Data([0x02])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(10).littleEndian) { Array($0) })
        let event = PacketParser.parse(data)

        guard case .contactsStart(let count) = event else {
            Issue.record("Expected .contactsStart event, got \(event)")
            return
        }
        #expect(count == 10)
    }

    @Test("Parse contacts end with timestamp")
    func parseContactsEnd() {
        var data = Data([0x04]) // ContactEnd response code
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1700000000).littleEndian) { Array($0) })
        let event = PacketParser.parse(data)

        guard case .contactsEnd(let lastMod) = event else {
            Issue.record("Expected .contactsEnd event, got \(event)")
            return
        }
        #expect(lastMod.timeIntervalSince1970 == 1700000000)
    }

    @Test("Unknown response code returns parseFailure")
    func unknownResponseCode() {
        let data = Data([0xFF, 0x01, 0x02])
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected .parseFailure event, got \(event)")
            return
        }
        #expect(reason.contains("Unknown response code"))
    }

    @Test("Empty packet returns parseFailure")
    func emptyPacket() {
        let data = Data()
        let event = PacketParser.parse(data)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected .parseFailure event, got \(event)")
            return
        }
        #expect(reason.contains("Empty"))
    }
}

// MARK: - Direct Parser Tests (via Parsers namespace)
// These test complex parsers in isolation without going through full routing

@Suite("Parsers.Contact Tests")
struct ContactParserTests {

    @Test("Contact parser rejects short data")
    func contactParserMinimumSize() {
        let shortData = Data(repeating: 0x00, count: 100)
        let event = Parsers.Contact.parse(shortData)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure for short data, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
        #expect(reason.contains("100 < 147"))
    }

    @Test("Contact parser extracts valid contact")
    func contactParserValidData() {
        let event = Parsers.Contact.parse(TestFixtures.validContactPayload)

        guard case .contact(let contact) = event else {
            Issue.record("Expected contact event, got: \(event)")
            return
        }
        #expect(contact.publicKey.count == 32)
        #expect(contact.advertisedName == "TestNode")
        #expect(abs(contact.latitude - 37.7749) < 0.0001)
        #expect(abs(contact.longitude - (-122.4194)) < 0.0001)
        #expect(contact.type == 0x01)
        #expect(contact.flags == 0x00)
        #expect(contact.outPathLength == 2)
        #expect(contact.outPath == Data([0x11, 0x22]))
    }

    @Test("Contact parser handles flood path length")
    func contactParserFloodPath() {
        var data = TestFixtures.validContactPayload
        // Set path_len to -1 (0xFF) for flood
        data[34] = 0xFF
        let event = Parsers.Contact.parse(data)

        guard case .contact(let contact) = event else {
            Issue.record("Expected contact event, got \(event)")
            return
        }
        #expect(contact.outPathLength == -1)
        #expect(contact.outPath.isEmpty)
        #expect(contact.isFloodPath == true)
    }
}

@Suite("Parsers.DeviceInfo Tests")
struct DeviceInfoParserTests {

    @Test("DeviceInfo parser handles v2 format")
    func deviceInfoV2() {
        let data = Data([0x02])  // Firmware version 2, minimal data
        let event = Parsers.DeviceInfo.parse(data)

        guard case .deviceInfo(let info) = event else {
            Issue.record("Expected deviceInfo event, got \(event)")
            return
        }
        #expect(info.firmwareVersion == 2)
        #expect(info.maxContacts == 0)  // Not available in v2
    }

    @Test("DeviceInfo parser handles v3 format with multiplier")
    func deviceInfoV3() {
        let event = Parsers.DeviceInfo.parse(TestFixtures.deviceInfoV3Payload)

        guard case .deviceInfo(let info) = event else {
            Issue.record("Expected deviceInfo event, got \(event)")
            return
        }
        #expect(info.firmwareVersion == 3)
        #expect(info.maxContacts == 100)  // raw 50 * 2
        #expect(info.maxChannels == 8)
        #expect(info.model.contains("T-Echo"))
        #expect(info.firmwareBuild.contains("1.2.3"))
        #expect(info.version.contains("2.0.0"))
    }

    @Test("DeviceInfo parser rejects empty data")
    func deviceInfoEmpty() {
        let event = Parsers.DeviceInfo.parse(Data())

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure, got \(event)")
            return
        }
        #expect(reason.contains("empty"))
    }
}

@Suite("Parsers.ContactMessage Tests")
struct ContactMessageParserTests {

    @Test("ContactMessage v1 parsing")
    func contactMessageV1() {
        let event = Parsers.ContactMessage.parse(TestFixtures.contactMessageV1Payload, version: .v1)

        guard case .contactMessageReceived(let msg) = event else {
            Issue.record("Expected contactMessageReceived event, got \(event)")
            return
        }
        #expect(msg.senderPublicKeyPrefix.count == 6)
        #expect(msg.snr == nil)  // v1 has no SNR
        #expect(msg.text == "Hello")
        #expect(msg.pathLength == 1)
        #expect(msg.textType == 0)
    }

    @Test("ContactMessage v3 parsing includes SNR")
    func contactMessageV3() {
        let event = Parsers.ContactMessage.parse(TestFixtures.contactMessageV3Payload, version: .v3)

        guard case .contactMessageReceived(let msg) = event else {
            Issue.record("Expected contactMessageReceived event, got \(event)")
            return
        }
        #expect(msg.snr != nil)
        #expect(msg.snr! > -32.0 && msg.snr! < 32.0)  // Valid SNR range
        #expect(msg.text == "Hello from mesh!")
        #expect(msg.pathLength == 2)
    }

    @Test("ContactMessage v1 rejects short data")
    func contactMessageV1Short() {
        let shortData = Data(repeating: 0x00, count: 8)
        let event = Parsers.ContactMessage.parse(shortData, version: .v1)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }

    @Test("ContactMessage handles invalid UTF-8 with lossy conversion")
    func contactMessageInvalidUTF8() {
        let event = Parsers.ContactMessage.parse(TestFixtures.contactMessageWithInvalidUTF8, version: .v1)

        guard case .contactMessageReceived(let msg) = event else {
            Issue.record("Expected contactMessageReceived event even with invalid UTF-8, got \(event)")
            return
        }
        // Should contain "Hello" and replacement characters for invalid bytes
        #expect(msg.text.contains("Hello"))
        #expect(msg.text.contains("\u{FFFD}"))  // Unicode replacement character
    }
}

@Suite("Parsers.ChannelMessage Tests")
struct ChannelMessageParserTests {

    @Test("ChannelMessage v1 parsing")
    func channelMessageV1() {
        let event = Parsers.ChannelMessage.parse(TestFixtures.channelMessageV1Payload, version: .v1)

        guard case .channelMessageReceived(let msg) = event else {
            Issue.record("Expected channelMessageReceived event, got \(event)")
            return
        }
        #expect(msg.channelIndex == 1)
        #expect(msg.snr == nil)
        #expect(msg.text == "Channel message")
        #expect(msg.pathLength == 1)
    }

    @Test("ChannelMessage v3 parsing includes SNR")
    func channelMessageV3() {
        let event = Parsers.ChannelMessage.parse(TestFixtures.channelMessageV3Payload, version: .v3)

        guard case .channelMessageReceived(let msg) = event else {
            Issue.record("Expected channelMessageReceived event, got \(event)")
            return
        }
        #expect(msg.snr != nil)
        #expect(msg.channelIndex == 2)
        #expect(msg.pathLength == 3)
        #expect(msg.text == "V3 channel message")
    }
}

@Suite("Parsers.SelfInfo Tests")
struct SelfInfoParserTests {

    @Test("SelfInfo parser extracts all fields")
    func selfInfoValidData() {
        let event = Parsers.SelfInfo.parse(TestFixtures.selfInfoPayload)

        guard case .selfInfo(let info) = event else {
            Issue.record("Expected selfInfo event, got \(event)")
            return
        }
        #expect(info.publicKey.count == 32)
        #expect(info.radioFrequency > 0)
        #expect(info.radioBandwidth > 0)
        #expect(info.name.contains("MyNode"))
        #expect(info.txPower == 20)
        #expect(info.maxTxPower == 30)
    }

    @Test("SelfInfo parser rejects short data")
    func selfInfoShort() {
        let shortData = Data(repeating: 0x00, count: 30)
        let event = Parsers.SelfInfo.parse(shortData)

        guard case .parseFailure(_, let reason) = event else {
            Issue.record("Expected parseFailure, got \(event)")
            return
        }
        #expect(reason.contains("too short"))
    }
}

@Suite("Parsers.Stats Tests")
struct StatsParserTests {

    @Test("CoreStats parsing")
    func coreStatsParsing() {
        let event = Parsers.CoreStats.parse(TestFixtures.coreStatsPayload)

        guard case .statsCore(let stats) = event else {
            Issue.record("Expected statsCore event, got \(event)")
            return
        }
        #expect(stats.batteryMV == 4200)
        #expect(stats.uptimeSeconds == 3600)
        #expect(stats.errors == 5)
        #expect(stats.queueLength == 3)
    }

    @Test("RadioStats parsing")
    func radioStatsParsing() {
        let event = Parsers.RadioStats.parse(TestFixtures.radioStatsPayload)

        guard case .statsRadio(let stats) = event else {
            Issue.record("Expected statsRadio event, got \(event)")
            return
        }
        #expect(stats.noiseFloor == -110)
        #expect(stats.lastRSSI == -70)
        #expect(abs(stats.lastSNR - 6.5) < 0.01)  // 26 / 4.0 = 6.5
        #expect(stats.txAirtimeSeconds == 1000)
        #expect(stats.rxAirtimeSeconds == 5000)
    }

    @Test("PacketStats parsing")
    func packetStatsParsing() {
        let event = Parsers.PacketStats.parse(TestFixtures.packetStatsPayload)

        guard case .statsPackets(let stats) = event else {
            Issue.record("Expected statsPackets event, got \(event)")
            return
        }
        #expect(stats.received == 100)
        #expect(stats.sent == 50)
        #expect(stats.floodTx == 20)
        #expect(stats.directTx == 30)
        #expect(stats.floodRx == 60)
        #expect(stats.directRx == 40)
    }
}

// MARK: - Category Routing Tests

@Suite("ResponseCode Category Tests")
struct ResponseCodeCategoryTests {

    @Test("Simple responses route to simple category")
    func simpleCategoryRouting() {
        #expect(ResponseCode.ok.category == .simple)
        #expect(ResponseCode.error.category == .simple)
    }

    @Test("Device responses route to device category")
    func deviceCategoryRouting() {
        #expect(ResponseCode.selfInfo.category == .device)
        #expect(ResponseCode.deviceInfo.category == .device)
        #expect(ResponseCode.battery.category == .device)
        #expect(ResponseCode.currentTime.category == .device)
        #expect(ResponseCode.privateKey.category == .device)
        #expect(ResponseCode.disabled.category == .device)
    }

    @Test("Contact responses route to contact category")
    func contactCategoryRouting() {
        #expect(ResponseCode.contactStart.category == .contact)
        #expect(ResponseCode.contact.category == .contact)
        #expect(ResponseCode.contactEnd.category == .contact)
        #expect(ResponseCode.contactURI.category == .contact)
    }

    @Test("Message responses route to message category")
    func messageCategoryRouting() {
        #expect(ResponseCode.messageSent.category == .message)
        #expect(ResponseCode.contactMessageReceived.category == .message)
        #expect(ResponseCode.contactMessageReceivedV3.category == .message)
        #expect(ResponseCode.channelMessageReceived.category == .message)
        #expect(ResponseCode.channelMessageReceivedV3.category == .message)
        #expect(ResponseCode.noMoreMessages.category == .message)
    }

    @Test("Push notifications route to push category")
    func pushCategoryRouting() {
        #expect(ResponseCode.advertisement.category == .push)
        #expect(ResponseCode.pathUpdate.category == .push)
        #expect(ResponseCode.ack.category == .push)
        #expect(ResponseCode.messagesWaiting.category == .push)
        #expect(ResponseCode.statusResponse.category == .push)
        #expect(ResponseCode.telemetryResponse.category == .push)
        #expect(ResponseCode.binaryResponse.category == .push)
        #expect(ResponseCode.pathDiscoveryResponse.category == .push)
        #expect(ResponseCode.controlData.category == .push)
        #expect(ResponseCode.newAdvertisement.category == .push)
    }

    @Test("Login responses route to login category")
    func loginCategoryRouting() {
        #expect(ResponseCode.loginSuccess.category == .login)
        #expect(ResponseCode.loginFailed.category == .login)
    }

    @Test("Signing responses route to signing category")
    func signingCategoryRouting() {
        #expect(ResponseCode.signStart.category == .signing)
        #expect(ResponseCode.signature.category == .signing)
    }

    @Test("Misc responses route to misc category")
    func miscCategoryRouting() {
        #expect(ResponseCode.stats.category == .misc)
        #expect(ResponseCode.customVars.category == .misc)
        #expect(ResponseCode.channelInfo.category == .misc)
        #expect(ResponseCode.rawData.category == .misc)
        #expect(ResponseCode.logData.category == .misc)
        #expect(ResponseCode.traceData.category == .misc)
    }
}

// MARK: - Data Extension Tests

@Suite("Data Extension Tests")
struct DataExtensionTests {

    @Test("hexString produces correct output")
    func hexStringConversion() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(data.hexString == "deadbeef")
    }

    @Test("Data init from hex string")
    func dataFromHexString() {
        let data = Data(hexString: "deadbeef")
        #expect(data == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("readUInt32LE reads correctly")
    func readUInt32LE() {
        let data = Data([0x2A, 0x00, 0x00, 0x00])  // 42 in little-endian
        #expect(data.readUInt32LE(at: 0) == 42)
    }

    @Test("readInt32LE reads negative correctly")
    func readInt32LE() {
        // -1 in little-endian is 0xFF 0xFF 0xFF 0xFF
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        #expect(data.readInt32LE(at: 0) == -1)
    }

    @Test("readUInt16LE reads correctly")
    func readUInt16LE() {
        let data = Data([0x68, 0x10])  // 4200 in little-endian
        #expect(data.readUInt16LE(at: 0) == 4200)
    }

    @Test("SNR value conversion")
    func snrConversion() {
        #expect(UInt8(bitPattern: Int8(-21)).snrValue == -5.25)
        #expect(UInt8(26).snrValue == 6.5)
        #expect(Int8(-21).snrValue == -5.25)
    }
}

// MARK: - NewAdvertisement Fallback Tests

@Suite("NewAdvertisement Fallback Tests")
struct NewAdvertisementFallbackTests {

    @Test("NewAdvertisement with 147+ bytes parses as Contact")
    func newAdvertisementParsesAsContact() {
        // 147-byte payload should parse as full Contact
        // PacketParser.parse() expects response code as first byte (public entry point)
        let contactPayload = TestFixtures.validContactPayload
        let packet = Data([ResponseCode.newAdvertisement.rawValue]) + contactPayload

        let event = PacketParser.parse(packet)

        if case .contact(let contact) = event {
            #expect(contact.publicKey.count == 32)
            #expect(!contact.advertisedName.isEmpty)
        } else {
            Issue.record("Expected .contact, got \(event)")
        }
    }

    @Test("NewAdvertisement with 32-146 bytes falls back to advertisement")
    func newAdvertisementFallbackToAdvertisement() {
        // 32-byte payload (just public key) should parse as advertisement
        let publicKey = Data(repeating: 0xAB, count: 32)
        let packet = Data([ResponseCode.newAdvertisement.rawValue]) + publicKey

        let event = PacketParser.parse(packet)

        if case .advertisement(let advert) = event {
            #expect(advert == publicKey)
        } else {
            Issue.record("Expected .advertisement, got \(event)")
        }
    }

    @Test("NewAdvertisement with less than 32 bytes returns parseFailure")
    func newAdvertisementTooShort() {
        let shortPayload = Data(repeating: 0xAB, count: 20)
        let packet = Data([ResponseCode.newAdvertisement.rawValue]) + shortPayload

        let event = PacketParser.parse(packet)

        if case .parseFailure = event {
            // Expected
        } else {
            Issue.record("Expected .parseFailure for short payload, got \(event)")
        }
    }
}

// MARK: - ControlData Payload Type Tests

@Suite("ControlData Payload Type Tests")
struct ControlDataPayloadTypeTests {

    @Test("ControlData with nodeDiscoverResponse payload type")
    func controlDataNodeDiscoverResponse() {
        // ControlData format: snr(1) + rssi(1) + pathLength(1) + payloadType(1) + payload
        var packet = Data([ResponseCode.controlData.rawValue])
        packet.append(20)  // snr = 20 (5.0 dB after /4)
        packet.append(UInt8(bitPattern: Int8(-80))) // rssi = -80
        packet.append(3)   // pathLength
        packet.append(0x90) // payloadType = nodeDiscoverResponse

        // Payload: node info for discover response
        let nodePublicKey = Data(repeating: 0xDE, count: 32)
        let nodeName = "TestNode".data(using: .utf8)!.prefix(32)
        packet.append(contentsOf: nodePublicKey)
        packet.append(contentsOf: nodeName)
        packet.append(contentsOf: Data(repeating: 0x00, count: 32 - nodeName.count))

        let event = PacketParser.parse(packet)

        if case .controlData(let control) = event {
            #expect(control.snr == 5.0)
            #expect(control.rssi == -80)
            #expect(control.pathLength == 3)
            #expect(control.payloadType == 0x90)
        } else {
            Issue.record("Expected .controlData, got \(event)")
        }
    }
}
