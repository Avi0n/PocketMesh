import Foundation
import Testing
@testable import MeshCore

@Suite("V112 Protocol")
struct V112ProtocolTests {

    // MARK: - ResponseCode Tests

    @Test("contactDeleted response code exists")
    func contactDeletedResponseCodeExists() {
        let code = ResponseCode(rawValue: 0x8F)
        #expect(code != nil)
        #expect(code == .contactDeleted)
    }

    @Test("contactsFull response code exists")
    func contactsFullResponseCodeExists() {
        let code = ResponseCode(rawValue: 0x90)
        #expect(code != nil)
        #expect(code == .contactsFull)
    }

    @Test("contactDeleted category is push")
    func contactDeletedCategoryIsPush() {
        #expect(ResponseCode.contactDeleted.category == .push)
    }

    @Test("contactsFull category is push")
    func contactsFullCategoryIsPush() {
        #expect(ResponseCode.contactsFull.category == .push)
    }

    // MARK: - ContactDeleted Parser Tests

    @Test("contactDeleted parses valid payload")
    func contactDeletedParsesValidPayload() {
        let publicKey = Data(repeating: 0xAB, count: 32)

        let event = Parsers.ContactDeleted.parse(publicKey)

        if case .contactDeleted(let parsedKey) = event {
            #expect(parsedKey == publicKey)
        } else {
            Issue.record("Expected .contactDeleted event, got \(event)")
        }
    }

    @Test("contactDeleted parse failure for short payload")
    func contactDeletedParseFailureForShortPayload() {
        let shortData = Data(repeating: 0xAB, count: 31)

        let event = Parsers.ContactDeleted.parse(shortData)

        if case .parseFailure(_, let reason) = event {
            #expect(reason.contains("ContactDeleted too short"))
        } else {
            Issue.record("Expected .parseFailure event, got \(event)")
        }
    }

    @Test("contactDeleted ignores extra bytes")
    func contactDeletedIgnoresExtraBytes() {
        var data = Data(repeating: 0xCD, count: 32)
        data.append(contentsOf: [0xFF, 0xFF, 0xFF])

        let event = Parsers.ContactDeleted.parse(data)

        if case .contactDeleted(let parsedKey) = event {
            #expect(parsedKey.count == 32)
            #expect(parsedKey == Data(repeating: 0xCD, count: 32))
        } else {
            Issue.record("Expected .contactDeleted event, got \(event)")
        }
    }

    // MARK: - ContactsFull Parser Tests

    @Test("contactsFull parses empty payload")
    func contactsFullParsesEmptyPayload() {
        let event = Parsers.ContactsFull.parse(Data())

        if case .contactsFull = event {
            // Success
        } else {
            Issue.record("Expected .contactsFull event, got \(event)")
        }
    }

    @Test("contactsFull parses any payload")
    func contactsFullParsesAnyPayload() {
        let data = Data([0x01, 0x02, 0x03])

        let event = Parsers.ContactsFull.parse(data)

        if case .contactsFull = event {
            // Success - payload is ignored
        } else {
            Issue.record("Expected .contactsFull event, got \(event)")
        }
    }

    // MARK: - PacketParser Integration Tests

    @Test("packetParser routes contactDeleted")
    func packetParserRoutesContactDeleted() {
        var packet = Data([0x8F])
        packet.append(Data(repeating: 0xEF, count: 32))

        let event = PacketParser.parse(packet)

        if case .contactDeleted(let publicKey) = event {
            #expect(publicKey == Data(repeating: 0xEF, count: 32))
        } else {
            Issue.record("Expected .contactDeleted event, got \(event)")
        }
    }

    @Test("packetParser routes contactsFull")
    func packetParserRoutesContactsFull() {
        let packet = Data([0x90])

        let event = PacketParser.parse(packet)

        if case .contactsFull = event {
            // Success
        } else {
            Issue.record("Expected .contactsFull event, got \(event)")
        }
    }

    @Test("packetParser contactDeleted parse failure for short payload")
    func packetParserContactDeletedParseFailureShortPayload() {
        var packet = Data([0x8F])
        packet.append(Data(repeating: 0xAB, count: 20))

        let event = PacketParser.parse(packet)

        if case .parseFailure(_, let reason) = event {
            #expect(reason.contains("ContactDeleted too short"))
        } else {
            Issue.record("Expected .parseFailure event, got \(event)")
        }
    }

    // MARK: - ContactManager Tests

    @Test("contactManager tracks contactDeleted")
    func contactManagerTracksContactDeleted() {
        var manager = ContactManager()
        let publicKey = Data(repeating: 0x11, count: 32)
        let contactId = publicKey.hexString

        let contact = MeshContact(
            id: contactId,
            publicKey: publicKey,
            type: .chat,
            flags: [],
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Test",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        manager.store(contact)

        #expect(manager.getByPublicKey(publicKey) != nil)

        manager.trackChanges(from: .contactDeleted(publicKey: publicKey))

        #expect(manager.getByPublicKey(publicKey) == nil)
        #expect(manager.needsRefresh)
    }

    @Test("contactManager tracks contactsFull")
    func contactManagerTracksContactsFull() {
        var manager = ContactManager()

        manager.trackChanges(from: .contactsFull)

        #expect(manager.needsRefresh)
    }

    // MARK: - Auto-Add Config PacketBuilder Tests

    @Test("getAutoAddConfig packet builder")
    func getAutoAddConfigPacketBuilder() {
        let packet = PacketBuilder.getAutoAddConfig()

        #expect(packet == Data([0x3B]))
    }

    @Test("setAutoAddConfig packet builder")
    func setAutoAddConfigPacketBuilder() {
        let packet = PacketBuilder.setAutoAddConfig(0x0F)

        #expect(packet == Data([0x3A, 0x0F]))
    }

    @Test("setAutoAddConfig all bits set")
    func setAutoAddConfigAllBitsSet() {
        let packet = PacketBuilder.setAutoAddConfig(0xFF)

        #expect(packet == Data([0x3A, 0xFF]))
    }

    @Test("setAutoAddConfig zero bits")
    func setAutoAddConfigZeroBits() {
        let packet = PacketBuilder.setAutoAddConfig(0x00)

        #expect(packet == Data([0x3A, 0x00]))
    }

    // MARK: - Auto-Add Config Response Parser Tests

    @Test("autoAddConfig response code exists")
    func autoAddConfigResponseCodeExists() {
        let code = ResponseCode(rawValue: 0x19)
        #expect(code != nil)
        #expect(code == .autoAddConfig)
    }

    @Test("autoAddConfig category is device")
    func autoAddConfigCategoryIsDevice() {
        #expect(ResponseCode.autoAddConfig.category == .device)
    }

    @Test("autoAddConfig parses valid payload")
    func autoAddConfigParsesValidPayload() {
        let packet = Data([0x19, 0x0F])

        let event = PacketParser.parse(packet)

        if case .autoAddConfig(let config) = event {
            #expect(config == 0x0F)
        } else {
            Issue.record("Expected .autoAddConfig event, got \(event)")
        }
    }

    @Test("autoAddConfig parse failure for empty payload")
    func autoAddConfigParseFailureForEmptyPayload() {
        let packet = Data([0x19])

        let event = PacketParser.parse(packet)

        if case .parseFailure(_, let reason) = event {
            #expect(reason.contains("AutoAddConfig response too short"))
        } else {
            Issue.record("Expected .parseFailure event, got \(event)")
        }
    }

    @Test("autoAddConfig ignores extra bytes")
    func autoAddConfigIgnoresExtraBytes() {
        let packet = Data([0x19, 0x0E, 0xFF, 0xFF])

        let event = PacketParser.parse(packet)

        if case .autoAddConfig(let config) = event {
            #expect(config == 0x0E)
        } else {
            Issue.record("Expected .autoAddConfig event, got \(event)")
        }
    }
}
