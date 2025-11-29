@testable import PocketMesh
@testable import PocketMeshKit
import SwiftData
import XCTest

@MainActor
open class BaseTestCase: XCTestCase {
    // MARK: - Properties

    var mockRadio: MockBLERadio!
    var bleManager: MockBLEManager!
    var meshProtocol: MeshCoreProtocol!
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    // Services (optional, override in subclasses)
    var messageService: MessageService?
    var advertisementService: AdvertisementService?
    var channelService: ChannelService?
    var pollingService: MessagePollingService?
    var telemetryService: TelemetryService?

    // MARK: - Setup/Teardown

    override open func setUp() async throws {
        try await super.setUp()

        // Create mock radio with configurable test scenarios
        let testConfig = configForTest()
        mockRadio = MockBLERadio(
            deviceName: "Test-Device-\(UUID().uuidString.prefix(8))",
            config: testConfig,
        )

        // Create mock BLE manager
        bleManager = MockBLEManager(radio: mockRadio)

        // Create mesh protocol
        meshProtocol = MeshCoreProtocol(bleManager: bleManager)

        // Create in-memory SwiftData container for testing
        let schema = Schema([Device.self, Contact.self, Message.self, Channel.self])
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = ModelContext(modelContainer)

        // Start mock radio
        await mockRadio.start()

        // Enable RX notifications (required for radio to send responses)
        let rxChar = await mockRadio.rxCharacteristic
        await rxChar.setNotifyValue(true)

        // Wait for radio to be ready (subscriptions established)
        await mockRadio.waitForReady()
    }

    override open func tearDown() async throws {
        // Stop mock radio
        await mockRadio.stop()

        // Clear all references
        messageService = nil
        advertisementService = nil
        channelService = nil
        pollingService = nil
        telemetryService = nil

        meshProtocol = nil
        bleManager = nil
        mockRadio = nil

        modelContext = nil
        modelContainer = nil

        try await super.tearDown()
    }

    // MARK: - Configuration Methods

    /// Override in subclasses to provide specific test configurations
    open func configForTest() -> MockRadioConfig {
        // Default configuration for basic protocol tests
        return .default
    }

    // MARK: - Helper Methods

    /// Create a test device and insert into context
    func createTestDevice(
        name: String = "Test Device",
        publicKey: Data = Data(repeating: 0x01, count: 32),
    ) -> Device {
        let device = Device(
            publicKey: publicKey,
            name: name,
            firmwareVersion: "v1.10.0",
            frequency: 915_000_000,
            bandwidth: 125_000,
            spreadingFactor: 7,
            codingRate: 5,
            txPower: 20,
        )
        modelContext.insert(device)
        try? modelContext.save()
        return device
    }

    /// Create a test contact for a device
    func createTestContact(
        device: Device,
        name: String = "Test Contact",
        publicKey: Data = Data(repeating: 0x02, count: 32),
        isPending: Bool = false,
    ) -> Contact {
        let contact = Contact(
            publicKey: publicKey,
            name: name,
            device: device,
            isPending: isPending,
        )
        modelContext.insert(contact)
        try? modelContext.save()
        return contact
    }

    /// Create a test channel for a device
    func createTestChannel(
        device: Device,
        name: String = "Test Channel",
        slotIndex: UInt8 = 1,
    ) -> Channel {
        let channel = Channel(
            slotIndex: slotIndex,
            name: name,
            device: device,
        )
        modelContext.insert(channel)
        try? modelContext.save()
        return channel
    }
}

// MARK: - Test Configuration Extensions

extension BaseTestCase {

    /// Configuration for contact-heavy tests
    func configWithTestContacts() -> MockRadioConfig {
        return MockRadioConfig(
            packetLossRate: 0.0,
            verboseLogging: true
        )
    }

    /// Configuration for high-volume message tests
    func configForHighVolumeTests() -> MockRadioConfig {
        return MockRadioConfig(
            packetLossRate: 0.0,
            verboseLogging: false // Reduce log noise in high-volume tests
        )
    }

    /// Configuration for timeout/error testing
    func configForTimeoutTests() -> MockRadioConfig {
        return MockRadioConfig(
            packetLossRate: 1.0, // 100% packet loss for timeout testing
            verboseLogging: true
        )
    }
}