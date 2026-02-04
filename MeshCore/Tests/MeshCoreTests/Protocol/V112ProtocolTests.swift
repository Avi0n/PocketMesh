import XCTest
@testable import MeshCore

final class V112ProtocolTests: XCTestCase {

    // MARK: - ResponseCode Tests

    func test_contactDeleted_responseCode_exists() {
        let code = ResponseCode(rawValue: 0x8F)
        XCTAssertNotNil(code)
        XCTAssertEqual(code, .contactDeleted)
    }

    func test_contactsFull_responseCode_exists() {
        let code = ResponseCode(rawValue: 0x90)
        XCTAssertNotNil(code)
        XCTAssertEqual(code, .contactsFull)
    }

    func test_contactDeleted_category_isPush() {
        XCTAssertEqual(ResponseCode.contactDeleted.category, .push)
    }

    func test_contactsFull_category_isPush() {
        XCTAssertEqual(ResponseCode.contactsFull.category, .push)
    }

    // MARK: - ContactDeleted Parser Tests

    func test_contactDeleted_parsesValidPayload() {
        let publicKey = Data(repeating: 0xAB, count: 32)

        let event = Parsers.ContactDeleted.parse(publicKey)

        if case .contactDeleted(let parsedKey) = event {
            XCTAssertEqual(parsedKey, publicKey)
        } else {
            XCTFail("Expected .contactDeleted event, got \(event)")
        }
    }

    func test_contactDeleted_parseFailure_forShortPayload() {
        let shortData = Data(repeating: 0xAB, count: 31)

        let event = Parsers.ContactDeleted.parse(shortData)

        if case .parseFailure(_, let reason) = event {
            XCTAssertTrue(reason.contains("ContactDeleted too short"))
        } else {
            XCTFail("Expected .parseFailure event, got \(event)")
        }
    }

    func test_contactDeleted_ignoresExtraBytes() {
        var data = Data(repeating: 0xCD, count: 32)
        data.append(contentsOf: [0xFF, 0xFF, 0xFF])

        let event = Parsers.ContactDeleted.parse(data)

        if case .contactDeleted(let parsedKey) = event {
            XCTAssertEqual(parsedKey.count, 32)
            XCTAssertEqual(parsedKey, Data(repeating: 0xCD, count: 32))
        } else {
            XCTFail("Expected .contactDeleted event, got \(event)")
        }
    }

    // MARK: - ContactsFull Parser Tests

    func test_contactsFull_parsesEmptyPayload() {
        let event = Parsers.ContactsFull.parse(Data())

        if case .contactsFull = event {
            // Success
        } else {
            XCTFail("Expected .contactsFull event, got \(event)")
        }
    }

    func test_contactsFull_parsesAnyPayload() {
        let data = Data([0x01, 0x02, 0x03])

        let event = Parsers.ContactsFull.parse(data)

        if case .contactsFull = event {
            // Success - payload is ignored
        } else {
            XCTFail("Expected .contactsFull event, got \(event)")
        }
    }

    // MARK: - PacketParser Integration Tests

    func test_packetParser_routesContactDeleted() {
        var packet = Data([0x8F])
        packet.append(Data(repeating: 0xEF, count: 32))

        let event = PacketParser.parse(packet)

        if case .contactDeleted(let publicKey) = event {
            XCTAssertEqual(publicKey, Data(repeating: 0xEF, count: 32))
        } else {
            XCTFail("Expected .contactDeleted event, got \(event)")
        }
    }

    func test_packetParser_routesContactsFull() {
        let packet = Data([0x90])

        let event = PacketParser.parse(packet)

        if case .contactsFull = event {
            // Success
        } else {
            XCTFail("Expected .contactsFull event, got \(event)")
        }
    }

    func test_packetParser_contactDeleted_parseFailure_shortPayload() {
        var packet = Data([0x8F])
        packet.append(Data(repeating: 0xAB, count: 20))

        let event = PacketParser.parse(packet)

        if case .parseFailure(_, let reason) = event {
            XCTAssertTrue(reason.contains("ContactDeleted too short"))
        } else {
            XCTFail("Expected .parseFailure event, got \(event)")
        }
    }

    // MARK: - ContactManager Tests

    func test_contactManager_tracksContactDeleted() {
        var manager = ContactManager()
        let publicKey = Data(repeating: 0x11, count: 32)
        let contactId = publicKey.hexString

        let contact = MeshContact(
            id: contactId,
            publicKey: publicKey,
            type: 0,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            advertisedName: "Test",
            lastAdvertisement: Date(),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )
        manager.store(contact)

        XCTAssertNotNil(manager.getByPublicKey(publicKey))

        manager.trackChanges(from: .contactDeleted(publicKey: publicKey))

        XCTAssertNil(manager.getByPublicKey(publicKey))
        XCTAssertTrue(manager.needsRefresh)
    }

    func test_contactManager_tracksContactsFull() {
        var manager = ContactManager()

        manager.trackChanges(from: .contactsFull)

        XCTAssertTrue(manager.needsRefresh)
    }

    // MARK: - Auto-Add Config PacketBuilder Tests

    func test_getAutoAddConfig_packetBuilder() {
        let packet = PacketBuilder.getAutoAddConfig()

        XCTAssertEqual(packet, Data([0x3B]))
    }

    func test_setAutoAddConfig_packetBuilder() {
        let packet = PacketBuilder.setAutoAddConfig(0x0F)

        XCTAssertEqual(packet, Data([0x3A, 0x0F]))
    }

    func test_setAutoAddConfig_packetBuilder_allBitsSet() {
        let packet = PacketBuilder.setAutoAddConfig(0xFF)

        XCTAssertEqual(packet, Data([0x3A, 0xFF]))
    }

    func test_setAutoAddConfig_packetBuilder_zeroBits() {
        let packet = PacketBuilder.setAutoAddConfig(0x00)

        XCTAssertEqual(packet, Data([0x3A, 0x00]))
    }

    // MARK: - Auto-Add Config Response Parser Tests

    func test_autoAddConfig_responseCode_exists() {
        let code = ResponseCode(rawValue: 0x19)
        XCTAssertNotNil(code)
        XCTAssertEqual(code, .autoAddConfig)
    }

    func test_autoAddConfig_category_isDevice() {
        XCTAssertEqual(ResponseCode.autoAddConfig.category, .device)
    }

    func test_autoAddConfig_parsesValidPayload() {
        let packet = Data([0x19, 0x0F])

        let event = PacketParser.parse(packet)

        if case .autoAddConfig(let config) = event {
            XCTAssertEqual(config, 0x0F)
        } else {
            XCTFail("Expected .autoAddConfig event, got \(event)")
        }
    }

    func test_autoAddConfig_parseFailure_forEmptyPayload() {
        let packet = Data([0x19])

        let event = PacketParser.parse(packet)

        if case .parseFailure(_, let reason) = event {
            XCTAssertTrue(reason.contains("AutoAddConfig response too short"))
        } else {
            XCTFail("Expected .parseFailure event, got \(event)")
        }
    }

    func test_autoAddConfig_ignoresExtraBytes() {
        let packet = Data([0x19, 0x0E, 0xFF, 0xFF])

        let event = PacketParser.parse(packet)

        if case .autoAddConfig(let config) = event {
            XCTAssertEqual(config, 0x0E)
        } else {
            XCTFail("Expected .autoAddConfig event, got \(event)")
        }
    }
}
