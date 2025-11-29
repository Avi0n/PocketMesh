@preconcurrency import Combine
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
public actor MockBLERadio {
    // MARK: - Public Properties

    public let peripheral: MockBLEPeripheral
    public nonisolated var rxNotifications: AsyncStream<Data> {
        radioService.rxCharacteristic.notificationStream
    }

    // Keep for backward compatibility during transition
    public nonisolated(unsafe) let rxNotificationsPublisher: AnyPublisher<Data, Never>

    // MARK: - Private Properties

    private let radioService: RadioService
    private let radioState: BLERadioState
    private let config: MockRadioConfig
    private var cancellables = Set<AnyCancellable>()

    private var isReadyContinuation: CheckedContinuation<Void, Never>?
    public nonisolated(unsafe) var isReady: Bool = false

    // MARK: - Initialization

    public init(
        deviceName: String = "MockMeshCore",
        config: MockRadioConfig = .default,
    ) {
        self.config = config

        // Initialize device info and self info from config or defaults
        let deviceInfo = config.deviceInfo ?? .default
        let selfInfo = config.selfInfo ?? .default

        // Create state actor
        self.radioState = BLERadioState(deviceInfo: deviceInfo, selfInfo: selfInfo)

        // Create radio service with command handler
        let serviceUUID = UUID(uuidString: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!
        let txUUID = UUID(uuidString: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")!
        let rxUUID = UUID(uuidString: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")!

        // Create RX characteristic first (needed for closure)
        let rxChar = RXCharacteristic(uuid: rxUUID)

        self.radioService = RadioService(
            uuid: serviceUUID,
            txUUID: txUUID,
            rxCharacteristic: rxChar,
            onTXWrite: { [weak radioState] data in
                guard let radioState else { return }
                await Self.handleIncomingFrame(data, radioState: radioState, rxChar: rxChar)
            },
        )

        // Create peripheral
        self.peripheral = MockBLEPeripheral(
            name: deviceName,
            radioService: radioService,
            config: config,
        )

        // Store Combine publisher for backward compatibility
        self.rxNotificationsPublisher = radioService.rxCharacteristic.notificationPublisher

        logger.info("MockBLERadio initialized: \(deviceName)")
    }

    // MARK: - Lifecycle

    public func start() async {
        await radioState.setConnectionState(.advertising)
        await peripheral.connect()
        logger.info("Mock radio started")

        // Signal readiness
        isReady = true
        if let continuation = isReadyContinuation {
            continuation.resume()
            isReadyContinuation = nil
        }
    }

    /// Wait for radio to be ready (subscriptions established)
    public func waitForReady() async {
        if isReady {
            return
        }

        await withCheckedContinuation { continuation in
            isReadyContinuation = continuation
        }
    }

    public func stop() async {
        await peripheral.disconnect()
        await radioState.setConnectionState(.disconnected)
        logger.info("Mock radio stopped")
    }

    // MARK: - Public Accessors

    /// Access to TX characteristic for MockBLEManager integration
    public nonisolated var txCharacteristic: TXCharacteristic {
        radioService.txCharacteristic
    }

    /// Access to RX characteristic for test notification setup
    public nonisolated var rxCharacteristic: RXCharacteristic {
        radioService.rxCharacteristic
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
        // Match command codes from MyMesh.cpp
        // NOTE: Only implementing CORE commands for initial testing
        switch frame.code {
        case 1: // CMD_APP_START
            return try await handleAppStart(radioState: radioState)
        case 22: // CMD_DEVICE_QUERY (note: typo in firmware: CMD_DEVICE_QEURY)
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
        default:
            logger.warning("Unsupported command: \(frame.code)")
            return RadioFrame(code: 1, payload: Data([1])) // RESP_CODE_ERR, ERR_CODE_UNSUPPORTED_CMD
        }
    }

    // MARK: - Command Handlers

    /// Handle CMD_DEVICE_QUERY (22)
    /// Response format matches MyMesh.cpp:815-828
    private static func handleDeviceQuery(radioState: BLERadioState) async throws -> RadioFrame {
        let deviceInfo = await radioState.deviceInfo

        var payload = Data()

        // Match firmware byte-for-byte (MyMesh.cpp:815-828)
        payload.append(deviceInfo.firmwareVersionCode) // 1 byte
        payload.append(deviceInfo.maxContacts) // 1 byte (MAX_CONTACTS/2)
        payload.append(deviceInfo.maxGroupChannels) // 1 byte
        payload.appendUInt32LE(deviceInfo.blePin) // 4 bytes

        // Build date (12 bytes) - firmware uses memset then strcpy
        var buildDateBytes = Data(repeating: 0, count: 12)
        if let buildData = deviceInfo.buildDate.data(using: .utf8) {
            let copyLen = min(buildData.count, 12)
            buildDateBytes.replaceSubrange(0 ..< copyLen, with: buildData.prefix(copyLen))
        }
        payload.append(buildDateBytes)

        // Manufacturer (40 bytes)
        var manufacturerBytes = Data(repeating: 0, count: 40)
        if let mfgData = deviceInfo.manufacturer.data(using: .utf8) {
            let copyLen = min(mfgData.count, 40)
            manufacturerBytes.replaceSubrange(0 ..< copyLen, with: mfgData.prefix(copyLen))
        }
        payload.append(manufacturerBytes)

        // Firmware version (20 bytes)
        var firmwareBytes = Data(repeating: 0, count: 20)
        if let fwData = deviceInfo.firmwareVersion.data(using: .utf8) {
            let copyLen = min(fwData.count, 20)
            firmwareBytes.replaceSubrange(0 ..< copyLen, with: fwData.prefix(copyLen))
        }
        payload.append(firmwareBytes)

        return RadioFrame(code: 13, payload: payload) // RESP_CODE_DEVICE_INFO
    }

    /// Handle CMD_APP_START (1)
    /// Response format matches MyMesh.cpp:838-870
    private static func handleAppStart(radioState: BLERadioState) async throws -> RadioFrame {
        let selfInfo = await radioState.selfInfo

        var payload = Data()

        // Match firmware byte-for-byte (MyMesh.cpp:838-870)
        payload.append(selfInfo.advertisementType) // 1 byte: adv_type
        payload.append(UInt8(bitPattern: selfInfo.txPower)) // 1 byte: tx_power (signed)
        payload.append(UInt8(bitPattern: selfInfo.maxTxPower)) // 1 byte: max_tx_power
        payload.append(selfInfo.publicKey) // 32 bytes: pub_key
        payload.appendInt32LE(selfInfo.latitude) // 4 bytes: lat (already scaled by 1E6)
        payload.appendInt32LE(selfInfo.longitude) // 4 bytes: lon (already scaled by 1E6)
        payload.append(selfInfo.multiAcks) // 1 byte: multi_acks (v7+)
        payload.append(selfInfo.advertLocationPolicy) // 1 byte: advert_loc_policy
        payload.append(selfInfo.telemetryModes) // 1 byte: telemetry_modes (v5+)
        payload.append(selfInfo.manualAddContacts) // 1 byte: manual_add_contacts
        payload.appendUInt32LE(selfInfo.frequency) // 4 bytes: freq (Hz)
        payload.appendUInt32LE(selfInfo.bandwidth) // 4 bytes: bw (Hz)
        payload.append(selfInfo.spreadingFactor) // 1 byte: sf
        payload.append(selfInfo.codingRate) // 1 byte: cr

        // Node name (variable length, null-terminated in firmware)
        if let nameData = selfInfo.nodeName.data(using: .utf8) {
            payload.append(nameData)
        }

        return RadioFrame(code: 5, payload: payload) // RESP_CODE_SELF_INFO
    }

    private static func handleGetContacts(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        logger.info("Handling CMD_GET_CONTACTS")

        // Parse optional 'since' parameter (4-byte Unix timestamp)
        var since: Date = .distantPast
        if frame.payload.count >= 4 {
            let timestamp = frame.payload.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            since = Date(timeIntervalSince1970: TimeInterval(timestamp))
            logger.debug("Contact sync since: \(since)")
        }

        // Get TOTAL count (unfiltered) - CRITICAL: Firmware sends total count, not filtered count
        let totalCount = await radioState.getContactCount()

        // Start filtered iterator for actual delivery
        let iteratorState = await radioState.startContactIterator(since: since)
        let filteredCount = iteratorState.contacts.count

        // Send CONTACTS_START frame (matches firmware MyMesh.cpp:946-950)
        // NOTE: Firmware sends TOTAL count, not filtered count (MyMesh.cpp:948 comment: "total, NOT filtered count")
        var startPayload = Data()
        startPayload.appendUInt32LE(UInt32(totalCount))

        // Queue remaining contacts in offline queue for multi-frame delivery
        if filteredCount > 0 {
            // Queue each contact as a separate frame in offline queue
            while let contact = await radioState.getNextContact() {
                let contactPayload = encodeContactForResponse(contact)
                let contactFrame = RadioFrame(code: ResponseCode.contact.rawValue, payload: contactPayload)
                try await radioState.enqueueOfflineFrame(contactFrame)
            }

            // Queue END_OF_CONTACTS frame
            let mostRecentLastMod = await radioState.endContactIterator()
            var endPayload = Data()
            endPayload.appendUInt32LE(UInt32(mostRecentLastMod.timeIntervalSince1970))
            let endFrame = RadioFrame(code: ResponseCode.endOfContacts.rawValue, payload: endPayload)
            try await radioState.enqueueOfflineFrame(endFrame)

            logger.info("Queued \(filteredCount) contact frames for multi-frame delivery (of \(totalCount) total contacts)")
        } else {
            // No contacts, send END_OF_CONTACTS immediately
            let endPayload = Data(repeating: 0, count: 4) // timestamp = 0
            let endFrame = RadioFrame(code: ResponseCode.endOfContacts.rawValue, payload: endPayload)
            try await radioState.enqueueOfflineFrame(endFrame)
        }

        return RadioFrame(code: ResponseCode.contactsStart.rawValue, payload: startPayload)
    }

    /// Helper to encode MockContact to firmware payload format
    private static func encodeContactForResponse(_ contact: MockContact) -> Data {
        var payload = Data()

        // Public key (32 bytes)
        payload.append(contact.publicKey)

        // Type (1 byte)
        payload.append(contact.type)

        // Flags (1 byte)
        payload.append(contact.flags)

        // Out path length (1 byte)
        payload.append(contact.outPathLength)

        // Out path (64 bytes, padded with zeros)
        var pathData = Data(count: 64)
        if let outPath = contact.outPath {
            let copyLength = min(outPath.count, 64)
            pathData.replaceSubrange(0 ..< copyLength, with: outPath.prefix(copyLength))
        }
        payload.append(pathData)

        // Name (32 bytes, null-terminated)
        var nameData = Data(count: 32)
        if let nameBytes = contact.name.data(using: .utf8) {
            let copyLength = min(nameBytes.count, 31) // Leave room for null terminator
            nameData.replaceSubrange(0 ..< copyLength, with: nameBytes.prefix(copyLength))
            // Null terminator already present from initialization
        }
        payload.append(nameData)

        // Last advertisement timestamp (4 bytes, little-endian)
        let lastAdvert = UInt32(contact.lastAdvertisement.timeIntervalSince1970)
        payload.appendUInt32LE(lastAdvert)

        // Latitude (4 bytes, little-endian, scaled by 1E6)
        let latInt = Int32((contact.latitude ?? 0) * 1_000_000)
        payload.appendInt32LE(latInt)

        // Longitude (4 bytes, little-endian, scaled by 1E6)
        let lonInt = Int32((contact.longitude ?? 0) * 1_000_000)
        payload.appendInt32LE(lonInt)

        // Last modified timestamp (4 bytes, little-endian)
        let lastMod = UInt32(contact.lastModified.timeIntervalSince1970)
        payload.appendUInt32LE(lastMod)

        return payload
    }

    private static func handleSyncNextMessage(radioState: BLERadioState) async throws -> RadioFrame {
        // Check offline queue
        if let queuedFrame = await radioState.dequeueOfflineFrame() {
            return queuedFrame
        }

        // No messages
        return RadioFrame(code: 10, payload: Data()) // RESP_CODE_NO_MORE_MESSAGES
    }

    /// Handle CMD_SEND_TXT_MSG (2)
    /// FIRMWARE: Payload is txt_type(1)+attempt(1)+timestamp(4)+key_prefix(6)+text(var) (MyMesh.cpp:872+)
    /// Response: RESP_CODE_SENT (6) with flag(1)+ack[4]+est_timeout[4] (MyMesh.cpp:905+)
    private static func handleSendTextMessage(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Parse payload: txt_type(1) + attempt(1) + timestamp(4) + key_prefix(6) + text(var)
        guard frame.payload.count >= 12 else { // Minimum: 1+1+4+6 = 12 bytes
            throw RadioError.invalidFrame
        }

        // Extract 6-byte public key prefix (offset 6, after txt_type + attempt + timestamp)
        let contactKey = frame.payload.subdata(in: 6 ..< 12)

        // Generate random ACK code (firmware generates this in sendMessage, not sent by client)
        let ackCode = UInt32.random(in: 0 ... UInt32.max)
        await radioState.addExpectedAck(ackCode, contactPublicKey: contactKey)

        // Build RESP_CODE_SENT response: flag(1) + ack[4] + est_timeout[4]
        var payload = Data()
        payload.append(0) // flag (stub: 0 for now)
        payload.appendUInt32LE(ackCode) // Generated ACK code
        payload.appendUInt32LE(5000) // Estimated timeout in ms (stub: 5000ms)

        return RadioFrame(code: 6, payload: payload) // RESP_CODE_SENT
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
    /// FIRMWARE: Sends full 32-byte pubkey (MyMesh.cpp:262-265: memcpy(..., PUB_KEY_SIZE))
    public func simulateIncomingAdvertisement(publicKey: Data, name: String) async {
        var payload = Data()
        payload.append(publicKey) // Full 32-byte public key (matches firmware)

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
        await peripheral.simulateDisconnectWithError()
        await radioState.setConnectionState(.disconnected)
        logger.warning("Simulated disconnect with error")
    }

    // MARK: - Contact Test APIs

    /// Add a contact for testing
    /// Useful for pre-populating contacts before running sync tests
    public func addTestContact(
        publicKey: Data,
        name: String,
        type: ContactType = .chat,
        flags: UInt8 = 0x01,
        outPath: Data? = nil,
        lastAdvertisement: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        lastModified: Date = Date(),
    ) async {
        let typeValue: UInt8 = switch type {
        case .none: 0
        case .chat: 1
        case .repeater: 2
        case .room: 3
        }

        let contact = MockContact(
            publicKey: publicKey,
            name: name,
            type: typeValue,
            flags: flags,
            outPathLength: UInt8(outPath?.count ?? 0),
            outPath: outPath,
            lastAdvertisement: lastAdvertisement,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified,
        )

        await radioState.addContact(contact)
        logger.info("Added test contact: \(name)")
    }

    /// Remove a contact by public key
    public func removeTestContact(publicKey: Data) async -> Bool {
        await radioState.removeContact(publicKey: publicKey)
    }

    /// Get current contact count
    public func getContactCount() async -> Int {
        await radioState.getContactCount()
    }

    /// Pre-populate with sample test contacts
    /// Useful for quick test setup
    public func populateSampleContacts() async {
        await radioState.populateTestContacts()
        logger.info("Populated sample test contacts")
    }

    /// Clear all contacts
    /// Useful for test isolation
    public func clearAllContacts() async {
        await radioState.resetContacts()
        logger.info("Cleared all contacts")
    }

    /// Simulate contact discovery from advertisement
    /// Creates a contact from advertisement data
    public func simulateContactDiscovery(
        publicKey: Data,
        name: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
    ) async {
        let contact = MockContact(
            publicKey: publicKey,
            name: name,
            type: 1, // chat
            flags: 0x01,
            outPathLength: 0,
            outPath: nil,
            lastAdvertisement: Date(),
            latitude: latitude,
            longitude: longitude,
            lastModified: Date(),
        )

        await radioState.addContact(contact)
        logger.info("Simulated contact discovery: \(name)")
    }
}
