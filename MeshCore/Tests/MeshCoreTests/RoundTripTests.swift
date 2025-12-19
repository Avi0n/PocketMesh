import Foundation
import Testing
@testable import MeshCore

// MARK: - Round-Trip Tests (Build → Parse → Verify)

@Suite("Round-Trip Tests")
struct RoundTripTests {

    // MARK: - Device Command Round-Trips

    @Test("setTime round-trip preserves timestamp")
    func setTimeRoundTrip() {
        let testDate = Date(timeIntervalSince1970: 1700000000)
        let packet = PacketBuilder.setTime(testDate)

        // Verify the timestamp in packet matches original
        let extractedTimestamp = packet.readUInt32LE(at: 1)
        #expect(extractedTimestamp == 1700000000)
    }

    @Test("setCoordinates round-trip preserves location")
    func setCoordinatesRoundTrip() {
        let lat = 37.7749
        let lon = -122.4194
        let packet = PacketBuilder.setCoordinates(latitude: lat, longitude: lon)

        // Extract and verify coordinates
        let extractedLat = Double(packet.readInt32LE(at: 1)) / 1_000_000.0
        let extractedLon = Double(packet.readInt32LE(at: 5)) / 1_000_000.0

        #expect(abs(extractedLat - lat) < 0.000001)
        #expect(abs(extractedLon - lon) < 0.000001)
    }

    @Test("setRadio round-trip preserves parameters")
    func setRadioRoundTrip() {
        let freq = 915.0
        let bw = 125.0
        let sf: UInt8 = 10
        let cr: UInt8 = 5

        let packet = PacketBuilder.setRadio(
            frequency: freq,
            bandwidth: bw,
            spreadingFactor: sf,
            codingRate: cr
        )

        let extractedFreq = Double(packet.readUInt32LE(at: 1)) / 1000.0
        let extractedBW = Double(packet.readUInt32LE(at: 5)) / 1000.0
        let extractedSF = packet[9]
        let extractedCR = packet[10]

        #expect(abs(extractedFreq - freq) < 0.001)
        #expect(abs(extractedBW - bw) < 0.001)
        #expect(extractedSF == sf)
        #expect(extractedCR == cr)
    }

    // MARK: - Message Command Round-Trips

    @Test("sendMessage round-trip preserves content")
    func sendMessageRoundTrip() {
        let destination = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let text = "Hello, Mesh!"
        let timestamp = Date(timeIntervalSince1970: 1700000000)

        let packet = PacketBuilder.sendMessage(
            to: destination,
            text: text,
            timestamp: timestamp,
            attempt: 2
        )

        // Verify structure
        #expect(packet[0] == CommandCode.sendMessage.rawValue)
        #expect(packet[1] == 0x00) // Plain text type
        #expect(packet[2] == 2)    // Attempt

        let extractedTimestamp = packet.readUInt32LE(at: 3)
        #expect(extractedTimestamp == 1700000000)

        let extractedDest = Data(packet[7..<13])
        #expect(extractedDest == destination)

        let extractedText = String(data: packet[13...], encoding: .utf8)
        #expect(extractedText == text)
    }

    @Test("sendChannelMessage round-trip preserves content")
    func sendChannelMessageRoundTrip() {
        let channel: UInt8 = 3
        let text = "Broadcast message"
        let timestamp = Date(timeIntervalSince1970: 1700000000)

        let packet = PacketBuilder.sendChannelMessage(
            channel: channel,
            text: text,
            timestamp: timestamp
        )

        #expect(packet[0] == CommandCode.sendChannelMessage.rawValue)
        #expect(packet[1] == 0x00) // Type
        #expect(packet[2] == channel)

        let extractedTimestamp = packet.readUInt32LE(at: 3)
        #expect(extractedTimestamp == 1700000000)

        let extractedText = String(data: packet[7...], encoding: .utf8)
        #expect(extractedText == text)
    }

    // MARK: - Contact Command Round-Trips

    @Test("getContacts round-trip with timestamp")
    func getContactsRoundTrip() {
        let since = Date(timeIntervalSince1970: 1699999000)
        let packet = PacketBuilder.getContacts(since: since)

        #expect(packet[0] == CommandCode.getContacts.rawValue)
        let extractedTimestamp = packet.readUInt32LE(at: 1)
        #expect(extractedTimestamp == 1699999000)
    }

    @Test("Public key is properly truncated to 32 bytes")
    func publicKeyTruncation() {
        let longKey = Data(repeating: 0xAA, count: 64)

        let resetPacket = PacketBuilder.resetPath(publicKey: longKey)
        let removePacket = PacketBuilder.removeContact(publicKey: longKey)
        let sharePacket = PacketBuilder.shareContact(publicKey: longKey)

        // All should truncate to 32 bytes
        #expect(resetPacket.count == 33)  // 1 cmd + 32 key
        #expect(removePacket.count == 33)
        #expect(sharePacket.count == 33)
    }

    // MARK: - Binary Request Round-Trips

    @Test("binaryRequest round-trip with all types")
    func binaryRequestRoundTrip() {
        let destination = Data(repeating: 0xBB, count: 32)

        let types: [BinaryRequestType] = [.status, .telemetry, .mma, .acl, .neighbours]

        for type in types {
            let packet = PacketBuilder.binaryRequest(to: destination, type: type)

            #expect(packet[0] == CommandCode.binaryRequest.rawValue)
            #expect(Data(packet[1..<33]) == destination)
            #expect(packet[33] == type.rawValue)
        }
    }

    // MARK: - Channel Command Round-Trips

    @Test("setChannel round-trip preserves all fields")
    func setChannelRoundTrip() {
        let index: UInt8 = 2
        let name = "Emergency"
        let secret = Data(repeating: 0xEE, count: 16)

        let packet = PacketBuilder.setChannel(index: index, name: name, secret: secret)

        #expect(packet[0] == CommandCode.setChannel.rawValue)
        #expect(packet[1] == index)

        // Name should be padded to 32 bytes
        let nameData = Data(packet[2..<34])
        let extractedName = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        #expect(extractedName == name)

        // Secret
        let extractedSecret = Data(packet[34..<50])
        #expect(extractedSecret == secret)
    }

    // MARK: - Edge Case Round-Trips

    @Test("Empty text message round-trip")
    func emptyTextRoundTrip() {
        let destination = Data(repeating: 0x00, count: 6)
        let timestamp = Date(timeIntervalSince1970: 0)

        let packet = PacketBuilder.sendMessage(to: destination, text: "", timestamp: timestamp)

        let extractedText = String(data: packet[13...], encoding: .utf8)
        #expect(extractedText == "")
    }

    @Test("Maximum coordinate values round-trip")
    func maxCoordinatesRoundTrip() {
        let maxLat = 90.0
        let maxLon = 180.0
        let minLat = -90.0
        let minLon = -180.0

        let packet1 = PacketBuilder.setCoordinates(latitude: maxLat, longitude: maxLon)
        let packet2 = PacketBuilder.setCoordinates(latitude: minLat, longitude: minLon)

        let extractedMaxLat = Double(packet1.readInt32LE(at: 1)) / 1_000_000.0
        let extractedMaxLon = Double(packet1.readInt32LE(at: 5)) / 1_000_000.0
        let extractedMinLat = Double(packet2.readInt32LE(at: 1)) / 1_000_000.0
        let extractedMinLon = Double(packet2.readInt32LE(at: 5)) / 1_000_000.0

        #expect(abs(extractedMaxLat - maxLat) < 0.000001)
        #expect(abs(extractedMaxLon - maxLon) < 0.000001)
        #expect(abs(extractedMinLat - minLat) < 0.000001)
        #expect(abs(extractedMinLon - minLon) < 0.000001)
    }

    @Test("Unicode text in messages round-trip")
    func unicodeTextRoundTrip() {
        let destination = Data(repeating: 0x00, count: 6)
        let timestamp = Date()
        let unicodeText = "Hello 🌍 世界 مرحبا"

        let packet = PacketBuilder.sendMessage(to: destination, text: unicodeText, timestamp: timestamp)

        let extractedText = String(data: packet[13...], encoding: .utf8)
        #expect(extractedText == unicodeText)
    }

    @Test("setOtherParams telemetry mode encoding round-trip")
    func telemetryModeEncodingRoundTrip() {
        let env: UInt8 = 1
        let loc: UInt8 = 2
        let base: UInt8 = 3

        let packet = PacketBuilder.setOtherParams(
            manualAddContacts: true,
            telemetryModeEnvironment: env,
            telemetryModeLocation: loc,
            telemetryModeBase: base,
            advertisementLocationPolicy: 1
        )

        // Decode the telemetry mode byte
        let telemetryByte = packet[2]
        let extractedEnv = (telemetryByte >> 4) & 0b11
        let extractedLoc = (telemetryByte >> 2) & 0b11
        let extractedBase = telemetryByte & 0b11

        #expect(extractedEnv == env)
        #expect(extractedLoc == loc)
        #expect(extractedBase == base)
    }
}

// MARK: - Parse → Re-encode Validation

@Suite("Parse Verification Tests")
struct ParseVerificationTests {

    @Test("Contact parse extracts correct coordinates")
    func contactCoordinateParsing() {
        let event = Parsers.Contact.parse(TestFixtures.validContactPayload)

        guard case .contact(let contact) = event else {
            Issue.record("Expected contact event")
            return
        }

        // San Francisco coordinates from fixture
        #expect(abs(contact.latitude - 37.7749) < 0.0001)
        #expect(abs(contact.longitude - (-122.4194)) < 0.0001)
    }

    @Test("SelfInfo parse extracts telemetry modes correctly")
    func selfInfoTelemetryModeParsing() {
        let event = Parsers.SelfInfo.parse(TestFixtures.selfInfoPayload)

        guard case .selfInfo(let info) = event else {
            Issue.record("Expected selfInfo event")
            return
        }

        // Fixture has telemetry mode 0x15: env=1, loc=1, base=1
        // (1 << 4) | (1 << 2) | 1 = 16 + 4 + 1 = 21 = 0x15
        #expect(info.telemetryModeEnvironment == 1)
        #expect(info.telemetryModeLocation == 1)
        #expect(info.telemetryModeBase == 1)
    }

    @Test("DeviceInfo v3 parse applies maxContacts multiplier")
    func deviceInfoMaxContactsMultiplier() {
        let event = Parsers.DeviceInfo.parse(TestFixtures.deviceInfoV3Payload)

        guard case .deviceInfo(let info) = event else {
            Issue.record("Expected deviceInfo event")
            return
        }

        // Fixture has raw value 50, should be multiplied by 2
        #expect(info.maxContacts == 100)
    }

    @Test("SNR parsing uses correct divisor")
    func snrParsingDivisor() {
        let rawSNR: UInt8 = 26  // Should be 6.5 dB
        #expect(abs(rawSNR.snrValue - 6.5) < 0.001)

        let negativeSNR: Int8 = -20  // Should be -5.0 dB
        #expect(abs(negativeSNR.snrValue - (-5.0)) < 0.001)
    }
}
