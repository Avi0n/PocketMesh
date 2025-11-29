@testable import PocketMesh
@testable import PocketMeshKit
import SwiftData
import XCTest

/// Basic tests to verify test infrastructure is working correctly
@MainActor
final class InfrastructureTests: BaseTestCase {
    func testBaseTestCaseSetup() async throws {
        // Verify all test infrastructure components are initialized
        XCTAssertNotNil(mockRadio, "Mock radio should be initialized")
        XCTAssertNotNil(bleManager, "BLE manager should be initialized")
        XCTAssertNotNil(meshProtocol, "Mesh protocol should be initialized")
        XCTAssertNotNil(modelContainer, "Model container should be initialized")
        XCTAssertNotNil(modelContext, "Model context should be initialized")
    }

    func testInMemorySwiftDataContainer() throws {
        // Verify in-memory SwiftData container works
        let device = createTestDevice(name: "Test Device")
        XCTAssertEqual(device.name, "Test Device")
        XCTAssertEqual(device.publicKey.count, 32)

        // Verify device was saved
        let fetchDescriptor = FetchDescriptor<Device>()
        let devices = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.name, "Test Device")
    }

    func testMockRadioInitialization() async throws {
        // Verify mock radio is accessible through BLE manager
        let radio = await bleManager.getRadio()
        XCTAssertNotNil(radio, "Mock radio should be accessible")

        // Verify peripheral is available
        let peripheral = await radio.peripheral
        XCTAssertNotNil(peripheral, "Peripheral should be available")
    }

    func testTestDataFactories() {
        // Verify test data factories produce valid data
        let deviceInfo = TestDataFactory.deviceInfo()
        XCTAssertEqual(deviceInfo.manufacturer, "MockRadio")
        XCTAssertEqual(deviceInfo.firmwareVersion, "v1.10.0")
        XCTAssertEqual(deviceInfo.maxGroupChannels, 8)

        let selfInfo = TestDataFactory.selfInfo()
        XCTAssertEqual(selfInfo.publicKey.count, 32)
        XCTAssertEqual(selfInfo.frequency, 915_000_000)

        let contactData = TestDataFactory.contactData()
        XCTAssertEqual(contactData.publicKey.count, 32)
        XCTAssertEqual(contactData.name, "Test Contact")

        let messageText = TestDataFactory.messageText(length: 50)
        XCTAssertEqual(messageText.count, 50)

        // Verify predefined public keys
        XCTAssertEqual(TestDataFactory.alicePublicKey.count, 32)
        XCTAssertEqual(TestDataFactory.bobPublicKey.count, 32)
        XCTAssertEqual(TestDataFactory.charliePublicKey.count, 32)
    }

    func testCreateTestContact() throws {
        let device = createTestDevice()
        let contact = createTestContact(device: device, name: "Alice", isPending: true)

        XCTAssertEqual(contact.name, "Alice")
        XCTAssertEqual(contact.isPending, true)
        XCTAssertEqual(contact.device?.id, device.id)

        // Verify contact was saved
        let fetchDescriptor = FetchDescriptor<Contact>()
        let contacts = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(contacts.count, 1)
    }

    func testCreateTestChannel() throws {
        let device = createTestDevice()
        let channel = createTestChannel(device: device, name: "General", slotIndex: 1)

        XCTAssertEqual(channel.name, "General")
        XCTAssertEqual(channel.slotIndex, 1)
        XCTAssertEqual(channel.device?.id, device.id)

        // Verify channel was saved
        let fetchDescriptor = FetchDescriptor<Channel>()
        let channels = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(channels.count, 1)
    }

    func testProtocolTestHelpers() {
        // Test decoding helpers
        var data = Data([0x12, 0x34, 0x56, 0x78])
        let uint32 = ProtocolTestHelpers.decodeUInt32LE(from: data, at: 0)
        XCTAssertEqual(uint32, 0x7856_3412) // Little-endian

        data = Data([0x12, 0x34])
        let uint16 = ProtocolTestHelpers.decodeUInt16LE(from: data, at: 0)
        XCTAssertEqual(uint16, 0x3412) // Little-endian

        data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let int32 = ProtocolTestHelpers.decodeInt32LE(from: data, at: 0)
        XCTAssertEqual(int32, -1)

        // Test null-terminated string extraction
        data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x57, 0x6F, 0x72, 0x6C, 0x64]) // "Hello\0World"
        let string = ProtocolTestHelpers.extractNullTerminatedString(from: data, at: 0, maxLength: 20)
        XCTAssertEqual(string, "Hello")
    }

    func testAsyncTestHelpers() async throws {
        // Test waitForCondition with immediate success
        try await AsyncTestHelpers.waitForCondition(timeout: 2.0, pollingInterval: 0.1) {
            true // Immediate success
        }

        // Test waitForCondition with timeout
        do {
            try await AsyncTestHelpers.waitForCondition(timeout: 0.5, pollingInterval: 0.1) {
                false // Never succeeds
            }
            XCTFail("Expected timeout error")
        } catch {
            // Expected timeout
        }
    }
}
