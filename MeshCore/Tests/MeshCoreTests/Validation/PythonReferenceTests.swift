import XCTest
@testable import MeshCore

/// Tests that verify Swift PacketBuilder produces identical bytes to Python meshcore_py.
///
/// These tests compare Swift-generated packets against reference bytes extracted from
/// the Python meshcore_py library, ensuring byte-level protocol compatibility.
final class PythonReferenceTests: XCTestCase {

    // MARK: - Device Commands

    func test_appStart_matchesPython() {
        // Python: b"\x01\x03" + 6 spaces + "MCore" (per firmware, name at byte 8)
        let packet = PacketBuilder.appStart(clientId: "MCore")
        XCTAssertEqual(packet, PythonReferenceBytes.appStart,
            "appStart mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.appStart.hexString)")
    }

    func test_deviceQuery_matchesPython() {
        // Python: b"\x16\x03"
        let packet = PacketBuilder.deviceQuery()
        XCTAssertEqual(packet, PythonReferenceBytes.deviceQuery)
    }

    func test_getBattery_matchesPython() {
        // Python: b"\x14"
        let packet = PacketBuilder.getBattery()
        XCTAssertEqual(packet, PythonReferenceBytes.getBattery)
    }

    func test_getTime_matchesPython() {
        // Python: b"\x05"
        let packet = PacketBuilder.getTime()
        XCTAssertEqual(packet, PythonReferenceBytes.getTime)
    }

    func test_setTime_matchesPython() {
        // Python: b"\x06" + timestamp.to_bytes(4, "little")
        let date = Date(timeIntervalSince1970: 1704067200)
        let packet = PacketBuilder.setTime(date)
        XCTAssertEqual(packet, PythonReferenceBytes.setTime_1704067200,
            "setTime mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.setTime_1704067200.hexString)")
    }

    func test_setName_matchesPython() {
        // Python: b"\x08" + name.encode("utf-8")
        let packet = PacketBuilder.setName("TestNode")
        XCTAssertEqual(packet, PythonReferenceBytes.setName_TestNode)
    }

    func test_setCoordinates_matchesPython() {
        // Python: lat/lon * 1e6 as signed little-endian int32
        let packet = PacketBuilder.setCoordinates(latitude: 37.7749, longitude: -122.4194)
        XCTAssertEqual(packet, PythonReferenceBytes.setCoords_SF,
            "setCoords mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.setCoords_SF.hexString)")
    }

    func test_setTxPower_matchesPython() {
        // Python: b"\x0c" + power.to_bytes(4, "little")
        let packet = PacketBuilder.setTxPower(20)
        XCTAssertEqual(packet, PythonReferenceBytes.setTxPower_20)
    }

    func test_setRadio_matchesPython() {
        // Python: freq/bw * 1000 as uint32 LE, sf/cr as uint8
        let packet = PacketBuilder.setRadio(
            frequency: 906.875,
            bandwidth: 250.0,
            spreadingFactor: 11,
            codingRate: 8
        )
        XCTAssertEqual(packet, PythonReferenceBytes.setRadio_default,
            "setRadio mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.setRadio_default.hexString)")
    }

    func test_sendAdvertisement_matchesPython() {
        // Python: b"\x07" or b"\x07\x01" for flood
        XCTAssertEqual(PacketBuilder.sendAdvertisement(flood: false),
                       PythonReferenceBytes.sendAdvertisement)
        XCTAssertEqual(PacketBuilder.sendAdvertisement(flood: true),
                       PythonReferenceBytes.sendAdvertisement_flood)
    }

    func test_reboot_matchesPython() {
        // Python: b"\x13reboot"
        let packet = PacketBuilder.reboot()
        XCTAssertEqual(packet, PythonReferenceBytes.reboot)
    }

    // MARK: - Contact Commands

    func test_getContacts_matchesPython() {
        let packet = PacketBuilder.getContacts()
        XCTAssertEqual(packet, PythonReferenceBytes.getContacts)
    }

    // MARK: - Messaging Commands

    func test_getMessage_matchesPython() {
        let packet = PacketBuilder.getMessage()
        XCTAssertEqual(packet, PythonReferenceBytes.getMessage)
    }

    func test_sendMessage_matchesPython() {
        // Python: b"\x02\x00" + attempt + timestamp(4LE) + dst(6) + msg
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
        let timestamp = Date(timeIntervalSince1970: 1704067200)
        let packet = PacketBuilder.sendMessage(
            to: dst,
            text: "Hello",
            timestamp: timestamp,
            attempt: 0
        )
        XCTAssertEqual(packet, PythonReferenceBytes.sendMessage_Hello,
            "sendMessage mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendMessage_Hello.hexString)")
    }

    func test_sendCommand_matchesPython() {
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
        let timestamp = Date(timeIntervalSince1970: 1704067200)
        let packet = PacketBuilder.sendCommand(
            to: dst,
            command: "status",
            timestamp: timestamp
        )
        XCTAssertEqual(packet, PythonReferenceBytes.sendCommand_status,
            "sendCommand mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendCommand_status.hexString)")
    }

    func test_sendChannelMessage_matchesPython() {
        let timestamp = Date(timeIntervalSince1970: 1704067200)
        let packet = PacketBuilder.sendChannelMessage(
            channel: 0,
            text: "Hi",
            timestamp: timestamp
        )
        XCTAssertEqual(packet, PythonReferenceBytes.sendChannelMessage_0_Hi,
            "sendChannelMessage mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendChannelMessage_0_Hi.hexString)")
    }

    func test_sendLogin_matchesPython() {
        // Python: b"\x1A" + dst(32) + password
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]) + Data(repeating: 0, count: 26)
        let packet = PacketBuilder.sendLogin(to: dst, password: "secret")
        XCTAssertEqual(packet, PythonReferenceBytes.sendLogin,
            "sendLogin mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendLogin.hexString)")
    }

    func test_sendLogout_matchesPython() {
        // Python: b"\x1D" + dst(32)
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]) + Data(repeating: 0, count: 26)
        let packet = PacketBuilder.sendLogout(to: dst)
        XCTAssertEqual(packet, PythonReferenceBytes.sendLogout,
            "sendLogout mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendLogout.hexString)")
    }

    func test_sendStatusRequest_matchesPython() {
        // Python: b"\x1B" + dst(32)
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]) + Data(repeating: 0, count: 26)
        let packet = PacketBuilder.sendStatusRequest(to: dst)
        XCTAssertEqual(packet, PythonReferenceBytes.sendStatusRequest,
            "sendStatusRequest mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendStatusRequest.hexString)")
    }

    // MARK: - Channel Commands

    func test_getChannel_matchesPython() {
        let packet = PacketBuilder.getChannel(index: 0)
        XCTAssertEqual(packet, PythonReferenceBytes.getChannel_0)
    }

    func test_setChannel_matchesPython() {
        let secret = Data(0..<16)
        let packet = PacketBuilder.setChannel(index: 0, name: "General", secret: secret)
        XCTAssertEqual(packet, PythonReferenceBytes.setChannel_0_General,
            "setChannel mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.setChannel_0_General.hexString)")
    }

    // MARK: - Stats Commands

    func test_getStats_matchesPython() {
        XCTAssertEqual(PacketBuilder.getStatsCore(), PythonReferenceBytes.getStatsCore)
        XCTAssertEqual(PacketBuilder.getStatsRadio(), PythonReferenceBytes.getStatsRadio)
        XCTAssertEqual(PacketBuilder.getStatsPackets(), PythonReferenceBytes.getStatsPackets)
    }

    func test_getSelfTelemetry_matchesPython() {
        let packet = PacketBuilder.getSelfTelemetry()
        XCTAssertEqual(packet, PythonReferenceBytes.getSelfTelemetry,
            "getSelfTelemetry mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.getSelfTelemetry.hexString)")
    }

    // MARK: - Security Commands

    func test_exportPrivateKey_matchesPython() {
        let packet = PacketBuilder.exportPrivateKey()
        XCTAssertEqual(packet, PythonReferenceBytes.exportPrivateKey)
    }

    func test_signStart_matchesPython() {
        let packet = PacketBuilder.signStart()
        XCTAssertEqual(packet, PythonReferenceBytes.signStart)
    }

    func test_signFinish_matchesPython() {
        let packet = PacketBuilder.signFinish()
        XCTAssertEqual(packet, PythonReferenceBytes.signFinish)
    }

    // MARK: - Path Discovery Commands

    func test_pathDiscovery_matchesPython() {
        let dst = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]) + Data(repeating: 0, count: 26)
        let packet = PacketBuilder.sendPathDiscovery(to: dst)
        XCTAssertEqual(packet, PythonReferenceBytes.pathDiscovery,
            "pathDiscovery mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.pathDiscovery.hexString)")
    }

    func test_sendTrace_matchesPython() {
        let packet = PacketBuilder.sendTrace(
            tag: 12345,
            authCode: 67890,
            flags: 0
        )
        XCTAssertEqual(packet, PythonReferenceBytes.sendTrace,
            "sendTrace mismatch - Swift: \(packet.hexString), Python: \(PythonReferenceBytes.sendTrace.hexString)")
    }
}
