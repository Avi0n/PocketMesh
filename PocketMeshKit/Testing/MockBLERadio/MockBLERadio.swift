import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "MockRadio")

/// Mock BLE Radio - main entrypoint for testing MeshCore protocol
///
/// Usage Example:
/// ```swift
/// let radio = MockBLERadio(
///     deviceName: "MeshCore-TEST",
///     config: .default
/// )
/// await radio.start()
///
/// // Subscribe to outgoing frames (radio → app)
/// for await frame in radio.rxNotifications.values {
///     print("Received frame: \(frame.hexString)")
/// }
///
/// // Simulate incoming advertisement
/// await radio.simulateIncomingAdvertisement(
///     publicKey: Data(repeating: 0xAB, count: 32),
///     name: "Remote-Device"
/// )
/// ```
/// Handler wrapper for mutable async closures
private final class TXWriteHandler: @unchecked Sendable {
    var handler: (@Sendable (Data) async -> Void)?

    func call(_ data: Data) async {
        await handler?(data)
    }
}

public final class MockBLERadio: @unchecked Sendable {
    // MARK: - Public Properties

    public let peripheral: MockBLEPeripheral
    public let rxNotifications: AnyPublisher<Data, Never>

    // MARK: - Internal Properties

    let radioService: RadioService

    // MARK: - Private Properties

    private let radioState: BLERadioState
    private let config: MockRadioConfig
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        deviceName: String = "MockMeshCore",
        config: MockRadioConfig = .default,
    ) {
        self.config = config

        // Initialize device info and self info
        let deviceInfo = config.deviceInfo ?? .default
        let selfInfo = config.selfInfo ?? .default

        // Create state actor
        radioState = BLERadioState(deviceInfo: deviceInfo, selfInfo: selfInfo)

        // Create radio service with command handler
        let serviceUUID = UUID(uuidString: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!
        let txUUID = UUID(uuidString: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")!
        let rxUUID = UUID(uuidString: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")!

        // Create mutable handler wrapper
        let txHandler = TXWriteHandler()

        radioService = RadioService(
            uuid: serviceUUID,
            txUUID: txUUID,
            rxUUID: rxUUID,
            onTXWrite: { data in
                await txHandler.call(data)
            },
        )

        // Set up actual handler now that radioService is initialized
        txHandler.handler = { [weak radioState, radioService] data in
            guard let radioState else { return }
            await Self.handleIncomingFrame(data, radioState: radioState, rxChar: radioService.rxCharacteristic)
        }

        // Create peripheral
        peripheral = MockBLEPeripheral(
            name: deviceName,
            radioService: radioService,
            config: config,
        )

        // Expose RX notifications publisher
        rxNotifications = radioService.rxCharacteristic.notificationPublisher

        logger.info("MockBLERadio initialized: \(deviceName)")
    }

    // MARK: - Lifecycle

    public func start() async {
        await radioState.setConnectionState(.advertising)
        peripheral.connect()
        logger.info("Mock radio started")
    }

    public func stop() async {
        peripheral.disconnect()
        await radioState.setConnectionState(.disconnected)
        logger.info("Mock radio stopped")
    }

    // MARK: - Command Handling (matches firmware MyMesh.cpp)

    private static func handleIncomingFrame(
        _ data: Data,
        radioState: BLERadioState,
        rxChar: RXCharacteristic,
    ) async {
        do {
            let frame = try RadioFrame.decode(data)
            logger.debug("Handling command: \(frame.code)")

            let response = try await processCommand(frame, radioState: radioState)
            await rxChar.sendNotification(response.encode())

        } catch {
            logger.error("Error handling frame: \(error)")
            await sendErrorResponse(error, rxChar: rxChar)
        }
    }

    private static func processCommand(
        _ frame: RadioFrame,
        radioState: BLERadioState,
    ) async throws -> RadioFrame {
        // Match command codes from MyMesh.cpp (lines 6-55)
        switch frame.code {
        case 1: // CMD_APP_START
            return try await handleAppStart(radioState: radioState)
        case 22: // CMD_DEVICE_QUERY
            return try await handleDeviceQuery(radioState: radioState)
        case 4: // CMD_GET_CONTACTS
            return try await handleGetContacts(frame: frame, radioState: radioState)
        case 10: // CMD_SYNC_NEXT_MESSAGE
            return try await handleSyncNextMessage(radioState: radioState)
        case 2: // CMD_SEND_TXT_MSG
            return try await handleSendTextMessage(frame: frame, radioState: radioState)
        case 3: // CMD_SEND_CHANNEL_TXT_MSG
            return try await handleSendChannelMessage(frame: frame, radioState: radioState)
        case 7: // CMD_SEND_SELF_ADVERT
            return try await handleSendSelfAdvert(frame: frame, radioState: radioState)
        // ... Add all 56+ command handlers as needed
        default:
            logger.warning("Unsupported command: \(frame.code)")
            return RadioFrame(code: 1, payload: Data([1])) // RESP_CODE_ERR, ERR_CODE_UNSUPPORTED_CMD
        }
    }

    // MARK: - Command Handlers

    private static func handleDeviceQuery(radioState: BLERadioState) async throws -> RadioFrame {
        // RESP_CODE_DEVICE_INFO (13) - matches MyMesh.cpp device query response
        var payload = Data()

        let deviceInfo = await radioState.deviceInfo

        // Firmware version (4 bytes: major.minor.patch.build)
        payload.append(contentsOf: [7, 0, 0, 0])

        // Max contacts (uint16 LE)
        payload.appendUInt16LE(deviceInfo.maxContacts)

        // Max channels (uint8)
        payload.append(deviceInfo.maxChannels)

        // BLE PIN (uint32 LE)
        payload.appendUInt32LE(deviceInfo.blePin)

        // Build date (12 bytes, null-padded)
        let buildDate = deviceInfo.buildDate.padding(toLength: 12, withPad: "\0", startingAt: 0)
        payload.append(buildDate.data(using: .utf8)!)

        // Manufacturer (40 bytes, null-padded)
        let manufacturer = deviceInfo.manufacturer.padding(toLength: 40, withPad: "\0", startingAt: 0)
        payload.append(manufacturer.data(using: .utf8)!)

        // Model (20 bytes, null-padded)
        let model = deviceInfo.model.padding(toLength: 20, withPad: "\0", startingAt: 0)
        payload.append(model.data(using: .utf8)!)

        // Firmware version code (4 bytes LE)
        payload.appendUInt32LE(UInt32(RadioConstants.firmwareVersionCode))

        return RadioFrame(code: 13, payload: payload) // RESP_CODE_DEVICE_INFO
    }

    private static func handleAppStart(radioState: BLERadioState) async throws -> RadioFrame {
        // RESP_CODE_SELF_INFO (5) - matches MyMesh.cpp app start response
        var payload = Data()

        let selfInfo = await radioState.selfInfo

        // Advert type (1 byte)
        payload.append(0)

        // TX power (int8)
        payload.append(UInt8(bitPattern: selfInfo.txPower))

        // Max TX power (1 byte)
        payload.append(20)

        // Public key (32 bytes)
        payload.append(selfInfo.publicKey)

        // Latitude (int32 LE, * 1E6)
        let lat = Int32((selfInfo.latitude ?? 0) * 1_000_000)
        payload.appendInt32LE(lat)

        // Longitude (int32 LE, * 1E6)
        let lon = Int32((selfInfo.longitude ?? 0) * 1_000_000)
        payload.appendInt32LE(lon)

        // Feature flags (4 bytes)
        payload.append(contentsOf: [0, 0, 0, 0])

        // Radio params (all uint32 LE)
        payload.appendUInt32LE(selfInfo.radioFrequency)
        payload.appendUInt32LE(selfInfo.radioBandwidth)
        payload.append(selfInfo.radioSpreadingFactor)
        payload.append(selfInfo.radioCodingRate)

        return RadioFrame(code: 5, payload: payload) // RESP_CODE_SELF_INFO
    }

    private static func handleGetContacts(frame _: RadioFrame, radioState _: BLERadioState) async throws -> RadioFrame {
        // CMD_GET_CONTACTS - return empty contact list for now
        // TODO: Implement contact storage in Phase 5
        RadioFrame(code: 2, payload: Data()) // RESP_CODE_CONTACTS_START
    }

    private static func handleSyncNextMessage(radioState: BLERadioState) async throws -> RadioFrame {
        // Check offline queue
        if let queuedFrame = await radioState.dequeueOfflineFrame() {
            return queuedFrame
        }

        // No messages
        return RadioFrame(code: 10, payload: Data()) // RESP_CODE_NO_MORE_MESSAGES
    }

    private static func handleSendTextMessage(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Extract ACK code from payload and track it
        guard frame.payload.count >= 4 else {
            throw RadioError.invalidFrame
        }

        let ackCode = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let contactKey = frame.payload.subdata(in: 4 ..< 10) // 6-byte public key prefix

        await radioState.addExpectedAck(ackCode, contactPublicKey: contactKey)

        // Return RESP_CODE_SENT
        return RadioFrame(code: 6, payload: Data())
    }

    private static func handleSendChannelMessage(frame _: RadioFrame, radioState _: BLERadioState) async throws -> RadioFrame {
        // Channels don't have ACKs, just return OK
        RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    private static func handleSendSelfAdvert(frame _: RadioFrame, radioState _: BLERadioState) async throws -> RadioFrame {
        // Return OK - advertisement sent
        RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    private static func sendErrorResponse(_: Error, rxChar: RXCharacteristic) async {
        let errorCode: UInt8 = 6 // ERR_CODE_ILLEGAL_ARG (default)
        let response = RadioFrame(code: 1, payload: Data([errorCode])) // RESP_CODE_ERR
        await rxChar.sendNotification(response.encode())
    }

    // MARK: - Test Control APIs

    /// Simulate incoming advertisement push notification
    public func simulateIncomingAdvertisement(publicKey: Data, name: String) async {
        var payload = Data()
        payload.append(publicKey.prefix(6)) // 6-byte prefix for PUSH_CODE_ADVERT

        let push = RadioFrame(code: 0x80, payload: payload) // PUSH_CODE_ADVERT
        await radioService.rxCharacteristic.sendNotification(push.encode())

        logger.info("Simulated incoming advertisement: \(name)")
    }

    /// Simulate incoming message waiting notification
    public func simulateMessageWaiting() async {
        let push = RadioFrame(code: 0x83, payload: Data()) // PUSH_CODE_MSG_WAITING
        await radioService.rxCharacteristic.sendNotification(push.encode())

        logger.info("Simulated message waiting notification")
    }

    /// Simulate time advancement (for timeout testing)
    public func advanceTime(by seconds: TimeInterval) async {
        // Mock implementation - in real tests, would integrate with test clock
        logger.debug("Advanced time by \(seconds) seconds")
    }

    /// Simulate disconnect with error
    public func disconnectWithError() async {
        peripheral.simulateDisconnectWithError()
        await radioState.setConnectionState(.disconnected)
        logger.warning("Simulated disconnect with error")
    }
}
