import Foundation
import Testing
@testable import MeshCore

@Suite("PacketBuilder Tests")
struct PacketBuilderTests {

    // MARK: - Device Commands

    @Test("appStart generates correct packet")
    func testAppStart() {
        let packet = PacketBuilder.appStart(clientId: "TestClient")

        #expect(packet[0] == CommandCode.appStart.rawValue)
        #expect(packet[1] == 0x03)
        // Client ID should be padded to 12 bytes
        #expect(packet.count == 14) // 1 cmd + 1 version + 12 client id
        let clientId = String(data: packet[2...], encoding: .utf8)?.trimmingCharacters(in: .whitespaces)
        #expect(clientId == "TestClient")
    }

    @Test("appStart pads short client IDs")
    func testAppStartPadding() {
        let packet = PacketBuilder.appStart(clientId: "Hi")

        #expect(packet.count == 14)
        let clientId = String(data: packet[2...], encoding: .utf8)
        #expect(clientId?.count == 12)
    }

    @Test("deviceQuery generates correct packet")
    func testDeviceQuery() {
        let packet = PacketBuilder.deviceQuery()

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.deviceQuery.rawValue)
        #expect(packet[1] == 0x03)
    }

    @Test("getBattery generates correct packet")
    func testGetBattery() {
        let packet = PacketBuilder.getBattery()

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.getBattery.rawValue)
    }

    @Test("getTime generates correct packet")
    func testGetTime() {
        let packet = PacketBuilder.getTime()

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.getTime.rawValue)
    }

    @Test("setTime generates correct packet with timestamp")
    func testSetTime() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.setTime(date)

        #expect(packet.count == 5) // 1 cmd + 4 timestamp
        #expect(packet[0] == CommandCode.setTime.rawValue)

        // Verify timestamp is little-endian using safe read method
        let timestamp = packet.readUInt32LE(at: 1)
        #expect(timestamp == 1700000000)
    }

    @Test("setName generates correct packet")
    func testSetName() {
        let packet = PacketBuilder.setName("MyNode")

        #expect(packet[0] == CommandCode.setName.rawValue)
        let name = String(data: packet[1...], encoding: .utf8)
        #expect(name == "MyNode")
    }

    @Test("setCoordinates generates correct packet with microdegrees")
    func testSetCoordinates() {
        let packet = PacketBuilder.setCoordinates(latitude: 37.7749, longitude: -122.4194)

        #expect(packet.count == 13) // 1 cmd + 4 lat + 4 lon + 4 alt
        #expect(packet[0] == CommandCode.setCoordinates.rawValue)

        // Verify latitude (37.7749 * 1_000_000 = 37774900) using safe read method
        let lat = packet.readInt32LE(at: 1)
        #expect(lat == 37_774_900)

        // Verify longitude (-122.4194 * 1_000_000 = -122419400)
        let lon = packet.readInt32LE(at: 5)
        #expect(lon == -122_419_400)
    }

    @Test("setTxPower generates correct packet")
    func testSetTxPower() {
        let packet = PacketBuilder.setTxPower(20)

        #expect(packet.count == 5) // 1 cmd + 4 power
        #expect(packet[0] == CommandCode.setTxPower.rawValue)

        let power = packet.readUInt32LE(at: 1)
        #expect(power == 20)
    }

    @Test("setRadio generates correct packet")
    func testSetRadio() {
        let packet = PacketBuilder.setRadio(
            frequency: 915.0,
            bandwidth: 125.0,
            spreadingFactor: 10,
            codingRate: 5
        )

        #expect(packet.count == 11) // 1 cmd + 4 freq + 4 bw + 1 sf + 1 cr
        #expect(packet[0] == CommandCode.setRadio.rawValue)

        // Frequency: 915.0 * 1000 = 915000
        let freq = packet.readUInt32LE(at: 1)
        #expect(freq == 915_000)

        // Bandwidth: 125.0 * 1000 = 125000
        let bw = packet.readUInt32LE(at: 5)
        #expect(bw == 125_000)

        #expect(packet[9] == 10) // spreadingFactor
        #expect(packet[10] == 5) // codingRate
    }

    @Test("sendAdvertisement generates correct packet without flood")
    func testSendAdvertisement() {
        let packet = PacketBuilder.sendAdvertisement(flood: false)

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.sendAdvertisement.rawValue)
    }

    @Test("sendAdvertisement generates correct packet with flood")
    func testSendAdvertisementFlood() {
        let packet = PacketBuilder.sendAdvertisement(flood: true)

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.sendAdvertisement.rawValue)
        #expect(packet[1] == 0x01)
    }

    @Test("reboot generates correct packet")
    func testReboot() {
        let packet = PacketBuilder.reboot()

        #expect(packet[0] == CommandCode.reboot.rawValue)
        let text = String(data: packet[1...], encoding: .utf8)
        #expect(text == "reboot")
    }

    // MARK: - Contact Commands

    @Test("getContacts without timestamp generates correct packet")
    func testGetContacts() {
        let packet = PacketBuilder.getContacts()

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.getContacts.rawValue)
    }

    @Test("getContacts with timestamp generates correct packet")
    func testGetContactsWithTimestamp() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.getContacts(since: date)

        #expect(packet.count == 5) // 1 cmd + 4 timestamp
        #expect(packet[0] == CommandCode.getContacts.rawValue)

        let timestamp = packet.readUInt32LE(at: 1)
        #expect(timestamp == 1700000000)
    }

    @Test("resetPath generates correct packet")
    func testResetPath() {
        let publicKey = Data(repeating: 0xAB, count: 32)
        let packet = PacketBuilder.resetPath(publicKey: publicKey)

        #expect(packet.count == 33) // 1 cmd + 32 key
        #expect(packet[0] == CommandCode.resetPath.rawValue)
        #expect(Data(packet[1...32]) == publicKey)
    }

    @Test("removeContact generates correct packet")
    func testRemoveContact() {
        let publicKey = Data(repeating: 0xCD, count: 32)
        let packet = PacketBuilder.removeContact(publicKey: publicKey)

        #expect(packet.count == 33) // 1 cmd + 32 key
        #expect(packet[0] == CommandCode.removeContact.rawValue)
        #expect(Data(packet[1...32]) == publicKey)
    }

    @Test("shareContact generates correct packet")
    func testShareContact() {
        let publicKey = Data(repeating: 0xEF, count: 32)
        let packet = PacketBuilder.shareContact(publicKey: publicKey)

        #expect(packet.count == 33)
        #expect(packet[0] == CommandCode.shareContact.rawValue)
    }

    @Test("exportContact without key generates correct packet")
    func testExportContactNoKey() {
        let packet = PacketBuilder.exportContact()

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.exportContact.rawValue)
    }

    @Test("exportContact with key generates correct packet")
    func testExportContactWithKey() {
        let publicKey = Data(repeating: 0x12, count: 32)
        let packet = PacketBuilder.exportContact(publicKey: publicKey)

        #expect(packet.count == 33)
        #expect(packet[0] == CommandCode.exportContact.rawValue)
    }

    // MARK: - Messaging Commands

    @Test("getMessage generates correct packet")
    func testGetMessage() {
        let packet = PacketBuilder.getMessage()

        #expect(packet.count == 1)
        #expect(packet[0] == CommandCode.getMessage.rawValue)
    }

    @Test("sendMessage generates correct packet")
    func testSendMessage() {
        let destination = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.sendMessage(
            to: destination,
            text: "Hello",
            timestamp: timestamp,
            attempt: 1
        )

        #expect(packet[0] == CommandCode.sendMessage.rawValue)
        #expect(packet[1] == 0x00) // Plain text type
        #expect(packet[2] == 1)    // attempt

        let ts = packet.readUInt32LE(at: 3)
        #expect(ts == 1700000000)

        #expect(Data(packet[7...12]) == destination)

        let text = String(data: packet[13...], encoding: .utf8)
        #expect(text == "Hello")
    }

    @Test("sendCommand generates correct packet")
    func testSendCommand() {
        let destination = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.sendCommand(
            to: destination,
            command: "status",
            timestamp: timestamp
        )

        #expect(packet[0] == CommandCode.sendMessage.rawValue)
        #expect(packet[1] == 0x01) // Binary/command type
        #expect(packet[2] == 0x00) // attempt = 0

        let text = String(data: packet[13...], encoding: .utf8)
        #expect(text == "status")
    }

    @Test("sendChannelMessage generates correct packet")
    func testSendChannelMessage() {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.sendChannelMessage(
            channel: 2,
            text: "Broadcast",
            timestamp: timestamp
        )

        #expect(packet[0] == CommandCode.sendChannelMessage.rawValue)
        #expect(packet[1] == 0x00) // type
        #expect(packet[2] == 2)    // channel

        let ts = packet.readUInt32LE(at: 3)
        #expect(ts == 1700000000)

        let text = String(data: packet[7...], encoding: .utf8)
        #expect(text == "Broadcast")
    }

    @Test("sendLogin generates correct packet")
    func testSendLogin() {
        let destination = Data(repeating: 0xAA, count: 32)
        let packet = PacketBuilder.sendLogin(to: destination, password: "secret123")

        #expect(packet[0] == CommandCode.sendLogin.rawValue)
        #expect(Data(packet[1...32]) == destination)
        let password = String(data: packet[33...], encoding: .utf8)
        #expect(password == "secret123")
    }

    @Test("sendLogout generates correct packet")
    func testSendLogout() {
        let destination = Data(repeating: 0xBB, count: 32)
        let packet = PacketBuilder.sendLogout(to: destination)

        #expect(packet.count == 33)
        #expect(packet[0] == CommandCode.sendLogout.rawValue)
        #expect(Data(packet[1...32]) == destination)
    }

    @Test("sendStatusRequest generates correct packet")
    func testSendStatusRequest() {
        let destination = Data(repeating: 0xCC, count: 32)
        let packet = PacketBuilder.sendStatusRequest(to: destination)

        #expect(packet.count == 33)
        #expect(packet[0] == CommandCode.sendStatusRequest.rawValue)
    }

    // MARK: - Binary Protocol Commands

    @Test("binaryRequest generates correct packet")
    func testBinaryRequest() {
        let destination = Data(repeating: 0xDD, count: 32)
        let packet = PacketBuilder.binaryRequest(to: destination, type: .status)

        #expect(packet.count == 34) // 1 cmd + 32 dest + 1 type
        #expect(packet[0] == CommandCode.binaryRequest.rawValue)
        #expect(Data(packet[1...32]) == destination)
        #expect(packet[33] == BinaryRequestType.status.rawValue)
    }

    @Test("binaryRequest with payload generates correct packet")
    func testBinaryRequestWithPayload() {
        let destination = Data(repeating: 0xDD, count: 32)
        let payload = Data([0x01, 0x02, 0x03])
        let packet = PacketBuilder.binaryRequest(to: destination, type: .telemetry, payload: payload)

        #expect(packet.count == 37) // 1 cmd + 32 dest + 1 type + 3 payload
        #expect(packet[33] == BinaryRequestType.telemetry.rawValue)
        #expect(Data(packet[34...36]) == payload)
    }

    // MARK: - Channel Commands

    @Test("getChannel generates correct packet")
    func testGetChannel() {
        let packet = PacketBuilder.getChannel(index: 3)

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.getChannel.rawValue)
        #expect(packet[1] == 3)
    }

    @Test("setChannel generates correct packet")
    func testSetChannel() {
        let secret = Data(repeating: 0xFF, count: 16)
        let packet = PacketBuilder.setChannel(index: 1, name: "General", secret: secret)

        #expect(packet.count == 50) // 1 cmd + 1 index + 32 name + 16 secret
        #expect(packet[0] == CommandCode.setChannel.rawValue)
        #expect(packet[1] == 1)

        // Name should be padded to 32 bytes
        let nameData = Data(packet[2..<34])
        #expect(nameData.count == 32)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        #expect(name == "General")

        // Secret should be 16 bytes
        #expect(Data(packet[34..<50]) == secret)
    }

    // MARK: - Stats Commands

    @Test("getStatsCore generates correct packet")
    func testGetStatsCore() {
        let packet = PacketBuilder.getStatsCore()

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.getStats.rawValue)
        #expect(packet[1] == StatsType.core.rawValue)
    }

    @Test("getStatsRadio generates correct packet")
    func testGetStatsRadio() {
        let packet = PacketBuilder.getStatsRadio()

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.getStats.rawValue)
        #expect(packet[1] == StatsType.radio.rawValue)
    }

    @Test("getStatsPackets generates correct packet")
    func testGetStatsPackets() {
        let packet = PacketBuilder.getStatsPackets()

        #expect(packet.count == 2)
        #expect(packet[0] == CommandCode.getStats.rawValue)
        #expect(packet[1] == StatsType.packets.rawValue)
    }

    // MARK: - Additional Commands

    @Test("updateContact generates correct packet")
    func testUpdateContact() {
        let publicKey = Data(repeating: 0xEE, count: 32)
        let packet = PacketBuilder.updateContact(publicKey: publicKey, flags: 0x01)

        #expect(packet[0] == CommandCode.updateContact.rawValue)
        #expect(Data(packet[1...32]) == publicKey)
        #expect(packet[33] == 0x01)
    }

    @Test("updateContact with path generates correct packet")
    func testUpdateContactWithPath() {
        let publicKey = Data(repeating: 0xEE, count: 32)
        let path = Data([0x01, 0x02, 0x03])
        let packet = PacketBuilder.updateContact(publicKey: publicKey, flags: 0x01, pathLen: 3, path: path)

        #expect(packet[0] == CommandCode.updateContact.rawValue)
        #expect(packet[33] == 0x01) // flags
        #expect(packet[34] == 3)    // pathLen
    }

    @Test("setTuning generates correct packet")
    func testSetTuning() {
        let packet = PacketBuilder.setTuning(rxDelay: 1000, af: 500)

        #expect(packet.count == 11) // 1 cmd + 4 rxDelay + 4 af + 2 reserved
        #expect(packet[0] == CommandCode.setTuning.rawValue)

        let rxDelay = packet.readUInt32LE(at: 1)
        #expect(rxDelay == 1000)

        let af = packet.readUInt32LE(at: 5)
        #expect(af == 500)

        // Reserved bytes
        #expect(packet[9] == 0)
        #expect(packet[10] == 0)
    }

    @Test("setOtherParams generates correct packet")
    func testSetOtherParams() {
        let packet = PacketBuilder.setOtherParams(
            manualAddContacts: true,
            telemetryModeEnvironment: 1,
            telemetryModeLocation: 2,
            telemetryModeBase: 3,
            advertisementLocationPolicy: 1
        )

        #expect(packet.count == 4) // 1 cmd + 1 manual + 1 telemetry + 1 policy
        #expect(packet[0] == CommandCode.setOtherParams.rawValue)
        #expect(packet[1] == 1) // manualAddContacts = true

        // Telemetry mode: env=1(01), loc=2(10), base=3(11)
        // env << 4 | loc << 2 | base = (1 << 4) | (2 << 2) | 3 = 16 | 8 | 3 = 27
        let expectedTelemetry: UInt8 = ((1 & 0b11) << 4) | ((2 & 0b11) << 2) | (3 & 0b11)
        #expect(packet[2] == expectedTelemetry)
        #expect(packet[3] == 1) // advertisementLocationPolicy
    }

    @Test("setOtherParams with multiAcks generates correct packet")
    func testSetOtherParamsWithMultiAcks() {
        let packet = PacketBuilder.setOtherParams(
            manualAddContacts: false,
            telemetryModeEnvironment: 0,
            telemetryModeLocation: 0,
            telemetryModeBase: 0,
            advertisementLocationPolicy: 0,
            multiAcks: 3
        )

        #expect(packet.count == 5) // 1 cmd + 1 manual + 1 telemetry + 1 policy + 1 multiAcks
        #expect(packet[4] == 3) // multiAcks
    }

    @Test("getSelfTelemetry without destination generates correct packet")
    func testGetSelfTelemetry() {
        let packet = PacketBuilder.getSelfTelemetry()

        #expect(packet.count == 4) // 1 cmd + 3 zeros
        #expect(packet[0] == CommandCode.getSelfTelemetry.rawValue)
    }

    @Test("getSelfTelemetry with destination generates correct packet")
    func testGetSelfTelemetryWithDestination() {
        let destination = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let packet = PacketBuilder.getSelfTelemetry(destination: destination)

        #expect(packet.count == 10) // 1 cmd + 3 zeros + 6 dest
        #expect(Data(packet[4...9]) == destination)
    }

    // MARK: - Edge Cases

    @Test("public key truncation to 32 bytes")
    func testPublicKeyTruncation() {
        let longKey = Data(repeating: 0xAA, count: 64)
        let packet = PacketBuilder.resetPath(publicKey: longKey)

        // Should only contain 32 bytes of the key
        #expect(packet.count == 33)
    }

    @Test("destination truncation to 6 bytes for messages")
    func testDestinationTruncation() {
        let longDest = Data(repeating: 0xBB, count: 32)
        let timestamp = Date(timeIntervalSince1970: 0)
        let packet = PacketBuilder.sendMessage(to: longDest, text: "", timestamp: timestamp)

        // Destination prefix should be 6 bytes
        #expect(Data(packet[7...12]) == Data(repeating: 0xBB, count: 6))
    }
}
