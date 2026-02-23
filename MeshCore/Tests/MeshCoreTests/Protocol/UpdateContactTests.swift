import Foundation
import Testing
@testable import MeshCore

@Suite("UpdateContact")
struct UpdateContactTests {

    @Test("updateContact produces 147 bytes")
    func updateContactProduces147Bytes() {
        let contact = MeshContact(
            id: "test",
            publicKey: Data(repeating: 0xAA, count: 32),
            type: .chat,
            flags: ContactFlags(rawValue: 0x02),
            outPathLength: 3,
            outPath: Data([0x11, 0x22, 0x33]),
            advertisedName: "TestNode",
            lastAdvertisement: Date(timeIntervalSince1970: 1704067200),  // 2024-01-01
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: Date()
        )

        let packet = PacketBuilder.updateContact(contact)

        #expect(packet.count == 147, "Full contact update should be 147 bytes")
    }

    @Test("updateContact correct layout")
    func updateContactCorrectLayout() {
        let pubkey = Data(repeating: 0xAA, count: 32)
        let outPath = Data([0x11, 0x22, 0x33])
        let contact = MeshContact(
            id: "test",
            publicKey: pubkey,
            type: .room,
            flags: ContactFlags(rawValue: 0x03),
            outPathLength: 3,
            outPath: outPath,
            advertisedName: "Node",
            lastAdvertisement: Date(timeIntervalSince1970: 1000),
            latitude: 10.0,
            longitude: -20.0,
            lastModified: Date()
        )

        let packet = PacketBuilder.updateContact(contact)

        // Verify layout
        #expect(packet[0] == 0x09, "Byte 0: command code")
        #expect(Data(packet[1..<33]) == pubkey, "Bytes 1-32: public key")
        #expect(packet[33] == ContactType.room.rawValue, "Byte 33: type")
        #expect(packet[34] == 0x03, "Byte 34: flags")
        #expect(packet[35] == 0x03, "Byte 35: outPathLength")

        // Bytes 36-99: outPath (64 bytes, padded)
        #expect(Data(packet[36..<39]) == outPath, "Bytes 36-38: outPath data")
        #expect(packet[39] == 0x00, "Byte 39: padding")

        // Bytes 100-131: name (32 bytes, padded)
        let nameBytes = Data(packet[100..<132])
        let name = String(data: nameBytes.prefix(4), encoding: .utf8)
        #expect(name == "Node", "Bytes 100-103: name")
        #expect(packet[104] == 0x00, "Byte 104: name padding")

        // Bytes 132-135: lastAdvertTimestamp (UInt32 LE)
        let timestamp = packet.readUInt32LE(at: 132)
        #expect(timestamp == 1000, "Bytes 132-135: timestamp")

        // Bytes 136-139: latitude (Int32 LE, scaled by 1M)
        let lat = packet.readInt32LE(at: 136)
        #expect(lat == 10_000_000, "Bytes 136-139: latitude")

        // Bytes 140-143: longitude (Int32 LE, scaled by 1M)
        let lon = packet.readInt32LE(at: 140)
        #expect(lon == -20_000_000, "Bytes 140-143: longitude")
    }

    @Test("updateContact signed path length")
    func updateContactSignedPathLength() {
        let contact = MeshContact(
            id: "test",
            publicKey: Data(repeating: 0x00, count: 32),
            type: .chat,
            flags: [],
            outPathLength: -1,  // Flood path
            outPath: Data(),
            advertisedName: "",
            lastAdvertisement: Date(timeIntervalSince1970: 0),
            latitude: 0,
            longitude: 0,
            lastModified: Date()
        )

        let packet = PacketBuilder.updateContact(contact)

        // -1 as UInt8 bit pattern = 0xFF
        #expect(packet[35] == 0xFF, "outPathLength -1 should be 0xFF")
    }
}
