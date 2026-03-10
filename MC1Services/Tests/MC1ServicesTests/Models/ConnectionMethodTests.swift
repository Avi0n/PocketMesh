import Testing
import Foundation
@testable import PocketMeshServices

@Suite("ConnectionMethod Tests")
struct ConnectionMethodTests {

    @Test("Bluetooth method has correct identifier")
    func bluetoothIdentifier() {
        let uuid = UUID()
        let method = ConnectionMethod.bluetooth(peripheralUUID: uuid, displayName: "My Device")

        #expect(method.id == "ble:\(uuid.uuidString)")
    }

    @Test("WiFi method has correct identifier")
    func wifiIdentifier() {
        let method = ConnectionMethod.wifi(host: "192.168.1.50", port: 5000, displayName: "Home")

        #expect(method.id == "wifi:192.168.1.50:5000")
    }

    @Test("Codable round-trip for Bluetooth")
    func bluetoothCodable() throws {
        let uuid = UUID()
        let original = ConnectionMethod.bluetooth(peripheralUUID: uuid, displayName: "Test")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionMethod.self, from: encoded)

        #expect(decoded.id == original.id)
    }

    @Test("Codable round-trip for WiFi")
    func wifiCodable() throws {
        let original = ConnectionMethod.wifi(host: "10.0.0.1", port: 8080, displayName: nil)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionMethod.self, from: encoded)

        #expect(decoded.id == original.id)
    }

    @Test("Display name returns custom name when set")
    func displayNameCustom() {
        let method = ConnectionMethod.wifi(host: "192.168.1.1", port: 5000, displayName: "Office Router")
        #expect(method.displayName == "Office Router")
    }

    @Test("Display name returns nil when not set")
    func displayNameNil() {
        let method = ConnectionMethod.wifi(host: "192.168.1.1", port: 5000, displayName: nil)
        #expect(method.displayName == nil)
    }
}
