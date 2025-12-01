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

        // Phase 1: Device Configuration Commands
        case 5: // CMD_GET_DEVICE_TIME
            return try await handleGetDeviceTime(radioState: radioState)
        case 6: // CMD_SET_DEVICE_TIME
            return try await handleSetDeviceTime(frame: frame, radioState: radioState)
        case 8: // CMD_SET_ADVERT_NAME
            return try await handleSetAdvertName(frame: frame, radioState: radioState)
        case 14: // CMD_SET_ADVERT_LATLON
            return try await handleSetAdvertLatLon(frame: frame, radioState: radioState)

        // Phase 1: Contact Management Commands
        case 9: // CMD_ADD_UPDATE_CONTACT
            return try await handleAddUpdateContact(frame: frame, radioState: radioState)
        case 15: // CMD_REMOVE_CONTACT
            return try await handleRemoveContact(frame: frame, radioState: radioState)
        case 30: // CMD_GET_CONTACT_BY_KEY
            return try await handleGetContactByKey(frame: frame, radioState: radioState)

        // Phase 1: Radio Configuration Commands
        case 11: // CMD_SET_RADIO_PARAMS
            return try await handleSetRadioParams(frame: frame, radioState: radioState)
        case 12: // CMD_SET_RADIO_TX_POWER
            return try await handleSetRadioTxPower(frame: frame, radioState: radioState)
        case 20: // CMD_GET_BATT_AND_STORAGE
            return try await handleGetBatteryAndStorage(radioState: radioState)
        case 21: // CMD_SET_TUNING_PARAMS
            return try await handleSetTuningParams(frame: frame, radioState: radioState)
        case 43: // CMD_GET_TUNING_PARAMS
            return try await handleGetTuningParams(radioState: radioState)

        // Phase 2 Missing: Channel Commands
        case 31: // CMD_GET_CHANNEL
            return try await handleGetChannel(radioState: radioState)
        case 32: // CMD_SET_CHANNEL
            return try await handleSetChannel(frame: frame, radioState: radioState)

        // Phase 2: Contact Management Extended Commands
        case 16: // CMD_SHARE_CONTACT
            return try await handleShareContact(frame: frame, radioState: radioState)
        case 17: // CMD_EXPORT_CONTACT
            return try await handleExportContact(frame: frame, radioState: radioState)
        case 18: // CMD_IMPORT_CONTACT
            return try await handleImportContact(frame: frame, radioState: radioState)

        // Phase 2: Advanced Messaging Commands
        case 25: // CMD_SEND_RAW_DATA
            return try await handleSendRawData(frame: frame, radioState: radioState)
        case 27: // CMD_SEND_STATUS_REQ
            return try await handleSendStatusReq(frame: frame, radioState: radioState)
        case 28: // CMD_HAS_CONNECTION
            return try await handleHasConnection(frame: frame, radioState: radioState)

        // Phase 2: Security Foundation Commands
        case 37: // CMD_SET_DEVICE_PIN
            return try await handleSetDevicePin(frame: frame, radioState: radioState)
        case 40: // CMD_GET_CUSTOM_VARS
            return try await handleGetCustomVars(radioState: radioState)
        case 41: // CMD_SET_CUSTOM_VAR
            return try await handleSetCustomVar(frame: frame, radioState: radioState)

        // Phase 3: Authentication Commands
        case 23: // CMD_EXPORT_PRIVATE_KEY
            return try await handleExportPrivateKey(radioState: radioState)
        case 24: // CMD_IMPORT_PRIVATE_KEY
            return try await handleImportPrivateKey(frame: frame, radioState: radioState)
        case 26: // CMD_SEND_LOGIN
            return try await handleSendLogin(frame: frame, radioState: radioState)
        case 29: // CMD_LOGOUT
            return try await handleLogout(frame: frame, radioState: radioState)

        // Phase 3: Path Discovery Basic
        case 13: // CMD_RESET_PATH
            return try await handleResetPath(frame: frame, radioState: radioState)
        case 42: // CMD_GET_ADVERT_PATH
            return try await handleGetAdvertPath(frame: frame, radioState: radioState)

        // Phase 3: Advanced Configuration (v8+ features)
        case 54: // CMD_SET_FLOOD_SCOPE
            return try await handleSetFloodScope(frame: frame, radioState: radioState)
        case 55: // CMD_SEND_CONTROL_DATA
            return try await handleSendControlData(frame: frame, radioState: radioState)

        // Phase 4: Advanced Path Discovery Commands
        case 52: // CMD_SEND_PATH_DISCOVERY_REQ
            return try await handlePathDiscoveryRequest(frame: frame, radioState: radioState)
        case 36: // CMD_SEND_TRACE_PATH
            return try await handleSendTracePath(frame: frame, radioState: radioState)

        // Phase 4: v8+ Features Commands
        case 50: // CMD_SEND_BINARY_REQ
            return try await handleSendBinaryReq(frame: frame, radioState: radioState)

        // Phase 4: Telemetry and Monitoring Commands
        case 39: // CMD_SEND_TELEMETRY_REQ
            return try await handleSendTelemetryReq(frame: frame, radioState: radioState)
        case 62: // CMD_REQUEST_STATUS
            return try await handleRequestStatus(frame: frame, radioState: radioState)
        case 63: // CMD_REQUEST_NEIGHBOURS
            return try await handleRequestNeighbours(frame: frame, radioState: radioState)

        // Phase 3 Missing: System Commands
        case 19: // CMD_REBOOT
            return try await handleReboot(radioState: radioState)
        case 33: // CMD_SIGN_START
            return try await handleSignStart(frame: frame, radioState: radioState)
        case 34: // CMD_SIGN_DATA
            return try await handleSignData(frame: frame, radioState: radioState)
        case 35: // CMD_SIGN_FINISH
            return try await handleSignFinish(frame: frame, radioState: radioState)
        case 38: // CMD_SET_OTHER_PARAMS
            return try await handleSetOtherParams(frame: frame, radioState: radioState)
        case 51: // CMD_FACTORY_RESET
            return try await handleFactoryReset(radioState: radioState)

        // Phase 4 Missing: v8+ Features
        case 57: // CMD_GET_FLOOD_SCOPE
            return try await handleGetFloodScope(radioState: radioState)

        // Remaining Commands for 100% Protocol Coverage
        case 56: // CMD_GET_MULTI_ACKS
            return try await handleGetMultiAcks(radioState: radioState)
        case 58: // CMD_SEND_PATH_DISCOVERY
            return try await handleSendPathDiscovery(frame: frame, radioState: radioState)
        case 59: // CMD_SEND_TRACE
            return try await handleSendTrace(frame: frame, radioState: radioState)
        case 60: // CMD_CHANGE_CONTACT_PATH
            return try await handleChangeContactPath(frame: frame, radioState: radioState)

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

    // MARK: - Phase 1: Device Configuration Command Handlers

    /// Handle CMD_GET_DEVICE_TIME (5)
    /// Firmware Reference: Device time query response
    private static func handleGetDeviceTime(radioState: BLERadioState) async throws -> RadioFrame {
        // Get current device time
        let currentTime = Date()
        let timestamp = UInt32(currentTime.timeIntervalSince1970)

        // Build response: timestamp(4) + timezone_offset(2) + daylight_savings(1) = 7 bytes
        var payload = Data()
        payload.appendUInt32LE(timestamp)
        payload.appendUInt16LE(300) // UTC-5 (in minutes, mock)
        payload.append(1) // DST active (mock)

        return RadioFrame(code: 16, payload: payload) // RESP_CODE_DEVICE_TIME
    }

    /// Handle CMD_SET_DEVICE_TIME (6)
    /// Firmware Reference: Device time synchronization
    private static func handleSetDeviceTime(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: timestamp(4) + timezone_offset(2) + daylight_savings(1) = 7 bytes
        guard frame.payload.count == 7 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let timestamp = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let timezoneOffset = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self) }
        let daylightSavings = frame.payload[6]

        // Validate timestamp (reasonable range: 2020-2050)
        let year2020 = UInt32(1577836800) // Jan 1, 2020 00:00:00 UTC
        let year2050 = UInt32(2524608000) // Jan 1, 2050 00:00:00 UTC
        guard timestamp >= year2020 && timestamp <= year2050 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate timezone offset (-12 to +14 hours in minutes)
        let minOffset = -12 * 60 // -720 minutes
        let maxOffset = 14 * 60  // 840 minutes
        guard timezoneOffset >= minOffset && timezoneOffset <= maxOffset else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate daylight savings (0 or 1)
        guard daylightSavings <= 1 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Update device time in radio state
        await radioState.setDeviceTime(timestamp: timestamp, timezoneOffset: timezoneOffset, daylightSavings: daylightSavings)

        logger.info("Device time updated: \(timestamp), timezone: \(timezoneOffset), DST: \(daylightSavings)")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SET_ADVERT_NAME (8)
    /// Firmware Reference: Set device advertisement name
    private static func handleSetAdvertName(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: name_length(1) + name(variable, max 32 chars)
        guard !frame.payload.isEmpty else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let nameLength = Int(frame.payload[0])
        guard frame.payload.count >= 1 + nameLength else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let nameData = frame.payload.subdata(in: 1..<(1 + nameLength))
        guard let name = String(data: nameData, encoding: .utf8) else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate name length (1-32 characters, non-empty)
        guard nameLength > 0 && nameLength <= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate name characters (printable ASCII only)
        for char in name.utf8 {
            guard char >= 32 && char <= 126 else {
                return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
            }
        }

        // Update advertisement name in radio state
        await radioState.setAdvertisementName(name)

        logger.info("Advertisement name updated: '\(name)'")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SET_ADVERT_LATLON (14)
    /// Firmware Reference: Set device advertisement location
    private static func handleSetAdvertLatLon(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: latitude(4) + longitude(4) = 8 bytes (scaled by 1E6)
        guard frame.payload.count == 8 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let latitude = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) }
        let longitude = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }

        // Validate latitude range (-90 to +90 degrees, scaled by 1E6)
        let minLat = Int32(-90 * 1_000_000)
        let maxLat = Int32(90 * 1_000_000)
        guard latitude >= minLat && latitude <= maxLat else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate longitude range (-180 to +180 degrees, scaled by 1E6)
        let minLon = Int32(-180 * 1_000_000)
        let maxLon = Int32(180 * 1_000_000)
        guard longitude >= minLon && longitude <= maxLon else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Update location in radio state
        await radioState.setDeviceLocation(latitude: Double(latitude) / 1_000_000.0,
                                        longitude: Double(longitude) / 1_000_000.0)

        let latDeg = Double(latitude) / 1_000_000.0
        let lonDeg = Double(longitude) / 1_000_000.0
        logger.info("Device location updated: \(latDeg), \(lonDeg)")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 1: Contact Management Command Handlers

    /// Handle CMD_ADD_UPDATE_CONTACT (9)
    /// Firmware Reference: MyMesh.cpp:1023-1043 (CMD_ADD_UPDATE_CONTACT handler)
    private static func handleAddUpdateContact(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Minimum payload: pub_key(32) + type(1) + flags(1) + path_len(1) + path(64) + name(32) = 131 bytes
        // Plus optional fields: last_advert(4) + lat(4) + lon(4) + last_mod(4) = 147 bytes max
        guard frame.payload.count >= 131 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let offset = 0

        // Parse public key (32 bytes)
        guard offset + 32 <= frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let publicKey = frame.payload.subdata(in: offset..<(offset + 32))

        // Parse type (1 byte)
        let typeOffset = offset + 32
        guard typeOffset < frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let type = frame.payload[typeOffset]

        // Parse flags (1 byte)
        let flagsOffset = typeOffset + 1
        guard flagsOffset < frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let flags = frame.payload[flagsOffset]

        // Parse path length (1 byte)
        let pathLengthOffset = flagsOffset + 1
        guard pathLengthOffset < frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let pathLength = frame.payload[pathLengthOffset]

        // Parse path (64 bytes, but only use pathLength bytes)
        let pathOffset = pathLengthOffset + 1
        guard pathOffset + 64 <= frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let pathData = frame.payload.subdata(in: pathOffset..<(pathOffset + 64))
        let outPath = pathLength > 0 ? Array(pathData.prefix(Int(pathLength))) : nil

        // Parse name (32 bytes, null-terminated)
        let nameOffset = pathOffset + 64
        guard nameOffset + 32 <= frame.payload.count else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
        let nameData = frame.payload.subdata(in: nameOffset..<(nameOffset + 32))
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

        // Parse optional fields if present
        var lastAdvertisement = Date()
        var latitude: Double?
        var longitude: Double?
        var lastModified = Date()

        let optionalOffset = nameOffset + 32
        if optionalOffset + 16 <= frame.payload.count {
            // last_advert(4) + lat(4) + lon(4) + last_mod(4) = 16 bytes
            lastAdvertisement = Date(timeIntervalSince1970: TimeInterval(frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: optionalOffset, as: UInt32.self) }))
            latitude = Double(frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: optionalOffset + 4, as: Int32.self) }) / 1_000_000.0
            longitude = Double(frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: optionalOffset + 8, as: Int32.self) }) / 1_000_000.0
            lastModified = Date(timeIntervalSince1970: TimeInterval(frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: optionalOffset + 12, as: UInt32.self) }))
        }

        // Create contact object
        let contact = MockContact(
            publicKey: publicKey,
            name: name,
            type: type,
            flags: flags,
            outPathLength: pathLength,
            outPath: outPath != nil ? Data(outPath!) : nil,
            lastAdvertisement: lastAdvertisement,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified
        )

        // Add or update contact in radio state
        do {
            try await radioState.addOrUpdateContact(contact)
            logger.info("Contact added/updated: '\(name)'")
            return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
        } catch RadioError.tableFull {
            return RadioFrame(code: 1, payload: Data([3])) // RESP_CODE_ERR, ERR_CODE_TABLE_FULL
        } catch RadioError.storageFull {
            return RadioFrame(code: 1, payload: Data([5])) // RESP_CODE_ERR, ERR_CODE_FILE_IO_ERROR
        } catch {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }
    }

    /// Handle CMD_REMOVE_CONTACT (15)
    /// Firmware Reference: Contact removal from storage
    private static func handleRemoveContact(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let publicKey = frame.payload.subdata(in: 0..<32)

        // Remove contact from radio state
        let removed = await radioState.removeContact(publicKey: publicKey)

        guard removed else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        logger.info("Contact removed: \(publicKey.hexString)")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_GET_CONTACT_BY_KEY (30)
    /// Firmware Reference: Contact lookup by public key
    private static func handleGetContactByKey(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let publicKey = frame.payload.subdata(in: 0..<32)

        // Get contact from radio state
        guard let contact = await radioState.getContactByPublicKey(publicKey) else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        // Encode contact response (same format as contact sync)
        let contactPayload = encodeContactForResponse(contact)

        logger.info("Contact retrieved: '\(contact.name)'")

        return RadioFrame(code: 2, payload: contactPayload) // RESP_CODE_CONTACT
    }

    // MARK: - Phase 1: Radio Configuration Command Handlers

    /// Firmware Reference: MyMesh.cpp:1120-1148 for CMD_SET_RADIO_PARAMS payload structure
    /// Error Handling: Returns ERR_CODE_ILLEGAL_ARG for invalid frequency/bw/sf/cr ranges
    /// Enhanced Validation: Exact firmware range validation with detailed error responses
    private static func handleSetRadioParams(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // frequency(4) + bandwidth(4) + sf(1) + cr(1) = 10 bytes total
        guard frame.payload.count == 10 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Parse payload matching firmware exactly (MyMesh.cpp:1120-1148)
        let frequency = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let bandwidth = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let spreadingFactor = frame.payload[8]
        let codingRate = frame.payload[9]

        // Enhanced validation matching firmware logic exactly
        // Frequency: 300kHz to 2.5MHz (firmware: freq >= 300000 && freq <= 2500000)
        guard frequency >= 300000 && frequency <= 2500000 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Bandwidth: 7kHz to 500kHz (firmware: bw >= 7000 && bw <= 500000)
        guard bandwidth >= 7000 && bandwidth <= 500000 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Spreading Factor: SF7 to SF12 (firmware: sf >= 7 && sf <= 12)
        guard spreadingFactor >= 7 && spreadingFactor <= 12 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Coding Rate: 4/5 to 8/8 (firmware: cr >= 5 && cr <= 8, where cr=5 means 4/5)
        guard codingRate >= 5 && codingRate <= 8 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Additional validation: Validate commonly used combinations
        let isValidCombination = validateRadioParameterCombination(
            frequency: frequency, bandwidth: bandwidth,
            spreadingFactor: spreadingFactor, codingRate: codingRate
        )
        guard isValidCombination else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Update radio state (matches firmware savePrefs() and radio_set_params())
        await radioState.setRadioParameters(
            frequency: frequency,           // Stored as kHz in firmware: freq / 1000.0
            bandwidth: bandwidth,           // Stored as kHz in firmware: bw / 1000.0
            spreadingFactor: spreadingFactor,
            codingRate: codingRate
        )

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Firmware Reference: MyMesh.cpp - validate radio parameter combinations
    /// Enhanced validation for realistic LoRa parameter combinations
    private static func validateRadioParameterCombination(
        frequency: UInt32, bandwidth: UInt32,
        spreadingFactor: UInt8, codingRate: UInt8
    ) -> Bool {
        // Common bandwidth values: 7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125, 250, 500 kHz
        let validBandwidths: [UInt32] = [7800, 10400, 15600, 20800, 31250, 41700, 62500, 125000, 250000, 500000]
        guard validBandwidths.contains(bandwidth) else { return false }

        // Common SF values and their typical bandwidth pairings
        switch spreadingFactor {
        case 7...9:  // High data rate
            return bandwidth >= 62500  // SF7-9 typically use 125kHz+
        case 10...12: // Long range
            return bandwidth <= 125000  // SF10-12 typically use 125kHz or less
        default:
            return false
        }
    }

    /// Handle CMD_SET_RADIO_TX_POWER (12)
    /// Firmware Reference: TX power constants in MyMesh.h
    private static func handleSetRadioTxPower(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // TX power: 1 byte payload
        guard frame.payload.count == 1 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let txPower = Int8(bitPattern: frame.payload[0])

        // Validate TX power range: -20 to +20 dBm (typical LoRa range)
        guard txPower >= -20 && txPower <= 20 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Update radio state
        await radioState.setRadioTxPower(txPower)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_GET_BATT_AND_STORAGE (20)
    /// Firmware Reference: Battery and storage information
    private static func handleGetBatteryAndStorage(radioState: BLERadioState) async throws -> RadioFrame {
        let (battery, used, total) = await radioState.getBatteryAndStorageInfo()

        // Build response: battery_mV(2) + storage_usedKB(4) + storage_totalKB(4) = 10 bytes
        var payload = Data()

        // Battery millivolts (simulate from percentage)
        let batteryMillivolts = UInt16(battery * 42) // Rough approximation: 0-100% -> 0-4200mV
        payload.appendUInt16LE(batteryMillivolts)

        // Storage usage in KB
        payload.appendUInt32LE(used / 1024)
        payload.appendUInt32LE(total / 1024)

        return RadioFrame(code: 12, payload: payload) // RESP_CODE_BATT_AND_STORAGE
    }

    /// Handle CMD_SET_TUNING_PARAMS (21)
    /// Firmware Reference: Network tuning parameters
    private static func handleSetTuningParams(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // rx_delay(2) + airtime_factor(2) = 4 bytes total
        guard frame.payload.count == 4 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let rxDelay = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        let airtimeFactor = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) }

        // Validate ranges
        guard rxDelay <= 10000 else { return RadioFrame(code: 1, payload: Data([6])) } // Max 10 seconds
        guard airtimeFactor <= 1000 else { return RadioFrame(code: 1, payload: Data([6])) } // Max 1000%

        // For now, just accept the parameters without storing (Phase 1 scope)
        logger.info("Set tuning params: rx_delay=\(rxDelay)ms, airtime_factor=\(airtimeFactor)%")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_GET_TUNING_PARAMS (43)
    /// Firmware Reference: Current tuning parameters
    private static func handleGetTuningParams(radioState: BLERadioState) async throws -> RadioFrame {
        // Return default tuning parameters for testing
        var payload = Data()
        payload.appendUInt16LE(100)    // rx_delay = 100ms
        payload.appendUInt16LE(50)     // airtime_factor = 50%

        return RadioFrame(code: 23, payload: payload) // RESP_CODE_TUNING_PARAMS
    }

    // MARK: - Phase 2: Channel Command Handlers

    /// Handle CMD_GET_CHANNEL (31)
    /// Firmware Reference: Get current channel information
    private static func handleGetChannel(radioState: BLERadioState) async throws -> RadioFrame {
        let channelInfo = await radioState.getChannelInfo()

        // Build response: channel_id(2) + name_length(1) + name(32, null-terminated) + member_count(2) + last_activity(4)
        var payload = Data()
        payload.appendUInt16LE(channelInfo.channelId)

        let nameData = channelInfo.name.data(using: .utf8) ?? Data()
        let nameLength = UInt8(min(nameData.count, 32))
        payload.append(nameLength)

        // Pad name to 32 bytes
        var paddedName = Data(count: 32)
        if !nameData.isEmpty {
            let copyLength = min(nameData.count, 32)
            paddedName.replaceSubrange(0..<copyLength, with: nameData.prefix(copyLength))
        }
        payload.append(paddedName)

        payload.appendUInt16LE(UInt16(channelInfo.memberCount))
        payload.appendUInt32LE(UInt32(channelInfo.lastActivity.timeIntervalSince1970))

        return RadioFrame(code: 24, payload: payload) // RESP_CODE_CHANNEL_INFO
    }

    /// Handle CMD_SET_CHANNEL (32)
    /// Firmware Reference: Set or join a channel
    private static func handleSetChannel(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: channel_id(2) + name_length(1) + name(variable, max 32)
        guard frame.payload.count >= 4 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let channelId = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        let nameLength = Int(frame.payload[2])
        guard frame.payload.count >= 3 + nameLength else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let nameData = frame.payload.subdata(in: 3..<(3 + nameLength))
        guard let name = String(data: nameData, encoding: .utf8) else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate channel ID (1-65535)
        guard channelId > 0 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate name length (1-32 characters, non-empty)
        guard nameLength > 0 && nameLength <= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Set channel in radio state
        await radioState.setChannel(channelId: channelId, name: name)

        logger.info("Channel set: \(channelId) '\(name)'")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 2: Contact Management Extended Command Handlers

    /// Handle CMD_SHARE_CONTACT (16)
    /// Firmware Reference: Contact sharing between devices
    private static func handleShareContact(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: public_key(32) + target_public_key(32) = 64 bytes
        guard frame.payload.count == 64 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)
        let targetPublicKey = frame.payload.subdata(in: 32..<64)

        // Check if contact exists
        guard let contact = await radioState.getContactByPublicKey(contactPublicKey) else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        // Simulate sharing contact by encoding it for transport
        let sharedContactData = try encodeContactForSharing(contact)

        // For testing purposes, return the encoded contact data
        var responsePayload = Data()
        responsePayload.append(targetPublicKey) // Echo back target key
        responsePayload.append(sharedContactData)

        return RadioFrame(code: 0, payload: responsePayload) // RESP_CODE_OK
    }

    /// Handle CMD_EXPORT_CONTACT (17)
    /// Firmware Reference: Contact export for backup/transfer
    private static func handleExportContact(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)

        // Find contact to export
        guard let contact = await radioState.getContactByPublicKey(contactPublicKey) else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        // Export contact in JSON format (simplified for testing)
        let exportedData = try encodeContactForSharing(contact)

        return RadioFrame(code: 11, payload: exportedData) // RESP_CODE_EXPORT_CONTACT
    }

    /// Handle CMD_IMPORT_CONTACT (18)
    /// Firmware Reference: Contact import from backup/transfer
    private static func handleImportContact(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: exported_contact_data (variable length)
        guard !frame.payload.isEmpty else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Decode imported contact
        let importedContact = try decodeContactFromSharingData(frame.payload)

        // Check contact limit
        let contactCount = await radioState.getContactCount()
        guard contactCount < 100 else { // MAX_CONTACTS from firmware
            return RadioFrame(code: 1, payload: Data([3])) // RESP_CODE_ERR, ERR_CODE_TABLE_FULL
        }

        // Add contact (replace existing if present)
        await radioState.addContact(importedContact)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 2: Advanced Messaging Command Handlers

    /// Handle CMD_SEND_RAW_DATA (25)
    /// Firmware Reference: Raw binary data transmission
    private static func handleSendRawData(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_key_prefix(6) + data_type(1) + raw_data(variable)
        guard frame.payload.count >= 7 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetKeyPrefix = frame.payload.subdata(in: 0..<6)
        let dataType = frame.payload[6]
        let rawData = frame.payload.subdata(in: 7..<frame.payload.count)

        // Simulate raw data transmission by queuing it
        await radioState.queueRawDataMessage(rawData, dataType: dataType, targetKey: targetKeyPrefix)

        // Generate ACK for raw data transmission
        let ackCode = UInt32.random(in: 0 ... UInt32.max)
        await radioState.addExpectedAck(ackCode, contactPublicKey: targetKeyPrefix)

        // Return ACK response
        var responsePayload = Data()
        responsePayload.append(0) // flag
        responsePayload.appendUInt32LE(ackCode) // ACK code
        responsePayload.appendUInt32LE(3000) // Estimated timeout

        return RadioFrame(code: 6, payload: responsePayload) // RESP_CODE_SENT
    }

    /// Handle CMD_SEND_STATUS_REQ (27)
    /// Firmware Reference: Status request/response messaging
    private static func handleSendStatusReq(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_key_prefix(6) + status_type(1) + request_data(variable)
        guard frame.payload.count >= 7 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetKeyPrefix = frame.payload.subdata(in: 0..<6)
        let statusType = frame.payload[6]
        let requestData = frame.payload.count > 7 ? frame.payload.subdata(in: 7..<frame.payload.count) : Data()

        // Generate mock status response based on type
        let statusResponse = generateStatusResponse(statusType: statusType, requestData: requestData)

        // Queue status response as a push notification
        await radioState.queueStatusResponse(statusResponse, targetKey: targetKeyPrefix)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_HAS_CONNECTION (28)
    /// Firmware Reference: Check connection status to target device
    private static func handleHasConnection(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_key_prefix(6) = 6 bytes
        guard frame.payload.count == 6 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetKeyPrefix = frame.payload.subdata(in: 0..<6)

        // Check connection status
        let hasConnection = await radioState.checkConnectionStatus(targetKeyPrefix)

        // Return response: 1 byte boolean (0=false, 1=true)
        let responsePayload = Data([hasConnection ? 1 : 0])

        return RadioFrame(code: 0, payload: responsePayload) // RESP_CODE_OK
    }

    // MARK: - Phase 2: Security Foundation Command Handlers

    /// Handle CMD_SET_DEVICE_PIN (37)
    /// Firmware Reference: Device PIN/security code management
    private static func handleSetDevicePin(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: old_pin(4) + new_pin(4) = 8 bytes
        guard frame.payload.count == 8 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let oldPin = frame.payload.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let newPin = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }

        // Verify old PIN (mock: always accept for testing)
        let currentPin = await radioState.getDevicePIN()
        guard oldPin == currentPin || currentPin == 0 else { // Allow if no PIN set
            return RadioFrame(code: 1, payload: Data([4])) // RESP_CODE_ERR, ERR_CODE_BAD_STATE
        }

        // Set new PIN
        await radioState.setDevicePIN(newPin)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_GET_CUSTOM_VARS (40)
    /// Firmware Reference: Get custom device variables/settings
    private static func handleGetCustomVars(radioState: BLERadioState) async throws -> RadioFrame {
        // Get all custom variables
        let customVars = await radioState.getCustomVariables()

        // Encode as key=value pairs, null-separated
        var payload = Data()
        for (key, value) in customVars {
            if let keyData = key.data(using: .utf8),
               let valueData = value.data(using: .utf8) {
                payload.append(keyData)
                payload.append(0x3D) // '='
                payload.append(valueData)
                payload.append(0x00) // null separator
            }
        }

        return RadioFrame(code: 21, payload: payload) // RESP_CODE_CUSTOM_VARS
    }

    /// Handle CMD_SET_CUSTOM_VAR (41)
    /// Firmware Reference: Set custom device variable/setting
    private static func handleSetCustomVar(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: key_length(1) + key(variable) + value_length(1) + value(variable)
        guard frame.payload.count >= 4 else { // Minimum: key_len(1) + key(1) + value_len(1) + value(1)
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let keyLength = Int(frame.payload[0])
        guard frame.payload.count >= 1 + keyLength + 1 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let keyData = frame.payload.subdata(in: 1..<(1 + keyLength))
        let valueLength = Int(frame.payload[1 + keyLength])
        guard frame.payload.count >= 1 + keyLength + 1 + valueLength else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let valueData = frame.payload.subdata(in: (1 + keyLength + 1)..<(1 + keyLength + 1 + valueLength))

        guard let key = String(data: keyData, encoding: .utf8),
              let value = String(data: valueData, encoding: .utf8) else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Validate key length (firmware typically limits to 32 chars)
        guard key.count <= 32 && value.count <= 128 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Set custom variable
        await radioState.setCustomVariable(key: key, value: value)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 3: Authentication Command Handlers

    /// Handle CMD_EXPORT_PRIVATE_KEY (23)
    /// Firmware Reference: Private key export for backup/transfer
    private static func handleExportPrivateKey(radioState: BLERadioState) async throws -> RadioFrame {
        // Get mock private key (for testing purposes)
        let privateKey = await radioState.exportPrivateKey()

        // Return private key in response
        return RadioFrame(code: 14, payload: privateKey) // RESP_CODE_PRIVATE_KEY
    }

    /// Handle CMD_IMPORT_PRIVATE_KEY (24)
    /// Firmware Reference: Private key import from backup/transfer
    private static func handleImportPrivateKey(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: private_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let privateKey = frame.payload

        // Import private key (mock implementation - just store it)
        await radioState.importPrivateKey(privateKey)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SEND_LOGIN (26)
    /// Firmware Reference: Contact authentication/login
    private static func handleSendLogin(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: contact_public_key(32) + credentials(variable)
        guard frame.payload.count >= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)
        let credentials = frame.payload.count > 32 ? frame.payload.subdata(in: 32..<frame.payload.count) : Data()

        // Authenticate contact (mock: always succeed for testing)
        let isAuthenticated = await radioState.authenticateContact(publicKey: contactPublicKey, credentials: credentials)

        if isAuthenticated {
            // Return success response
            return RadioFrame(code: 0, payload: Data([1])) // RESP_CODE_OK, success flag
        } else {
            // Return failure response
            return RadioFrame(code: 1, payload: Data([4])) // RESP_CODE_ERR, ERR_CODE_BAD_STATE
        }
    }

    /// Handle CMD_LOGOUT (29)
    /// Firmware Reference: Contact logout/session termination
    private static func handleLogout(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: contact_public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)

        // Logout contact (remove from authenticated sessions)
        await radioState.logoutContact(publicKey: contactPublicKey)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 3: Path Discovery Basic Command Handlers

    /// Handle CMD_RESET_PATH (13)
    /// Firmware Reference: Reset path for contact
    private static func handleResetPath(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: contact_public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)

        // Reset path for contact
        await radioState.resetPath(for: contactPublicKey)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_GET_ADVERT_PATH (42)
    /// Firmware Reference: Get advertisement path for contact
    private static func handleGetAdvertPath(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: contact_public_key(32) = 32 bytes
        guard frame.payload.count == 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)

        // Get path for contact
        let pathData = await radioState.getContactPath(for: contactPublicKey)

        // Build response: path_length(1) + path_data(64, padded)
        var responsePayload = Data()
        responsePayload.append(UInt8(pathData.count))

        // Pad path to 64 bytes (matches firmware behavior)
        var paddedPathData = Data(count: 64)
        if !pathData.isEmpty {
            let copyLength = min(pathData.count, 64)
            paddedPathData.replaceSubrange(0..<copyLength, with: Array(pathData.prefix(copyLength)))
        }
        responsePayload.append(paddedPathData)

        return RadioFrame(code: 22, payload: responsePayload) // RESP_CODE_ADVERT_PATH
    }

    // MARK: - Phase 3: Advanced Configuration Command Handlers (v8+ Features)

    /// Handle CMD_SET_FLOOD_SCOPE (54)
    /// Firmware Reference: v8+ flood scope configuration
    private static func handleSetFloodScope(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: flood_scope(1) + transport_key(32) = 33 bytes
        guard frame.payload.count == 33 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let floodScope = frame.payload[0]
        let transportKey = frame.payload.subdata(in: 1..<33)

        // Validate flood scope (0=global, 1=local, 2=direct)
        guard floodScope <= 2 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Set flood scope
        await radioState.setFloodScope(floodScope, transportKey: transportKey)

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SEND_CONTROL_DATA (55)
    /// Firmware Reference: v8+ control data message transmission
    private static func handleSendControlData(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: control_type(1) + target_key_prefix(6) + control_data(variable)
        guard frame.payload.count >= 7 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let controlType = frame.payload[0]
        let targetKeyPrefix = frame.payload.subdata(in: 1..<7)
        let controlData = frame.payload.count > 7 ? frame.payload.subdata(in: 7..<frame.payload.count) : Data()

        // Queue control data for transmission
        await radioState.queueControlData(controlType, targetKey: targetKeyPrefix, data: controlData)

        // Generate ACK for control data transmission
        let ackCode = UInt32.random(in: 0 ... UInt32.max)
        await radioState.addExpectedAck(ackCode, contactPublicKey: targetKeyPrefix)

        // Return ACK response
        var responsePayload = Data()
        responsePayload.append(0) // flag
        responsePayload.appendUInt32LE(ackCode) // ACK code
        responsePayload.appendUInt32LE(2000) // Estimated timeout (shorter for control data)

        return RadioFrame(code: 6, payload: responsePayload) // RESP_CODE_SENT
    }

    // MARK: - Phase 4: Advanced Path Discovery Command Handlers

    /// Handle CMD_SEND_PATH_DISCOVERY_REQ (52)
    /// Firmware Reference: Advanced path discovery for complex multi-hop routing
    private static func handlePathDiscoveryRequest(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_public_key(32) + discovery_options(1) = 33 bytes
        guard frame.payload.count >= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetPublicKey = frame.payload.subdata(in: 0..<32)
        _ = frame.payload.count > 32 ? frame.payload[32] : 0x00 // discoveryOptions not used

        // Perform path discovery using network topology
        let discoveredPath = await radioState.discoverPath(to: targetPublicKey)

        // Build response: path_length(1) + path_nodes(32*hop_count)
        var responsePayload = Data()
        responsePayload.append(UInt8(discoveredPath.count)) // Number of hops

        // Add each path node (32-byte public keys)
        for nodeKey in discoveredPath {
            responsePayload.append(nodeKey)
        }

        logger.info("Path discovery completed: \(discoveredPath.count) hops to destination")

        return RadioFrame(code: 26, payload: responsePayload) // RESP_CODE_PATH_DISCOVERY_RESPONSE
    }

    /// Handle CMD_SEND_TRACE_PATH (36)
    /// Firmware Reference: Trace network path for debugging and monitoring
    private static func handleSendTracePath(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_public_key(32) + trace_options(1) = 33 bytes
        guard frame.payload.count >= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetPublicKey = frame.payload.subdata(in: 0..<32)
        _ = frame.payload.count > 32 ? frame.payload[32] : 0x00 // traceOptions not used

        // Perform trace using network topology
        let tracedPath = await radioState.discoverPath(to: targetPublicKey)

        // Build trace response with detailed path information
        var responsePayload = Data()
        responsePayload.append(0x01) // Trace success flag
        responsePayload.append(UInt8(tracedPath.count)) // Number of hops

        // Add hop details: public_key(32) + rssi(1) + latency(2) for each hop
        for (index, nodeKey) in tracedPath.enumerated() {
            responsePayload.append(nodeKey)
            let rssi = Int8.random(in: -90 ..< -30) // Mock RSSI
            responsePayload.append(UInt8(bitPattern: rssi))
            responsePayload.appendUInt16LE(UInt16(index * 50 + 10)) // Mock latency (ms)
        }

        logger.info("Path trace completed: \(tracedPath.count) hops traced")

        return RadioFrame(code: 0x89, payload: responsePayload) // PUSH_CODE_TRACE_DATA
    }

    // MARK: - Phase 4: v8+ Features Command Handlers

    /// Handle CMD_SEND_BINARY_REQ (50)
    /// Firmware Reference: Large binary data transfer with chunking support
    private static func handleSendBinaryReq(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_key_prefix(6) + request_id(2) + chunk_index(2) + total_chunks(2) + data_size(2) + binary_data(variable)
        guard frame.payload.count >= 14 else { // Minimum: 6+2+2+2+2 = 14 bytes
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetKeyPrefix = frame.payload.subdata(in: 0..<6)
        let requestId = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: UInt16.self) }
        let chunkIndex = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt16.self) }
        let totalChunks = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 10, as: UInt16.self) }
        let dataSize = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt16.self) }

        let binaryData = frame.payload.count > 14 ? frame.payload.subdata(in: 14..<frame.payload.count) : Data()

        // Validate payload size matches declared size
        guard binaryData.count == dataSize else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Process binary request with chunking support
        let responseData = await radioState.processBinaryRequest(binaryData, targetKey: targetKeyPrefix)

        // Build binary response: request_id(2) + chunk_index(2) + success_flag(1) + response_data(variable)
        var responsePayload = Data()
        responsePayload.appendUInt16LE(requestId)
        responsePayload.appendUInt16LE(chunkIndex)
        responsePayload.append(0x01) // Success flag
        responsePayload.append(responseData)

        logger.info("Binary request processed: chunk \(chunkIndex + 1)/\(totalChunks), \(dataSize) bytes")

        return RadioFrame(code: 0x8C, payload: responsePayload) // PUSH_CODE_BINARY_RESPONSE
    }

    // MARK: - Phase 4: Telemetry and Monitoring Command Handlers

    /// Handle CMD_SEND_TELEMETRY_REQ (39)
    /// Firmware Reference: Sensor data and device telemetry request
    private static func handleSendTelemetryReq(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: telemetry_type(1) + options(1) = 2 bytes
        let telemetryType = frame.payload.count > 0 ? frame.payload[0] : 0x00
        _ = frame.payload.count > 1 ? frame.payload[1] : 0x00 // options not used

        // Get current telemetry data
        let telemetry = await radioState.getTelemetry()

        // Build telemetry response: type(1) + timestamp(4) + battery_voltage(4) + temperature(4) + humidity(4)
        var responsePayload = Data()
        responsePayload.append(telemetryType) // Echo request type
        responsePayload.appendUInt32LE(UInt32(telemetry.lastUpdate.timeIntervalSince1970)) // Unix timestamp

        // Convert float values to 32-bit little-endian format
        var batteryVoltage = telemetry.batteryVoltage
        responsePayload.append(Data(bytes: &batteryVoltage, count: 4))

        var temperature = telemetry.temperature
        responsePayload.append(Data(bytes: &temperature, count: 4))

        var humidity = telemetry.humidity
        responsePayload.append(Data(bytes: &humidity, count: 4))

        logger.info("Telemetry request processed: V=\(String(format: "%.2f", telemetry.batteryVoltage))V, T=\(String(format: "%.1f", telemetry.temperature))°C")

        return RadioFrame(code: 0x8B, payload: responsePayload) // PUSH_CODE_TELEMETRY_RESPONSE
    }

    /// Handle CMD_REQUEST_STATUS (62)
    /// Firmware Reference: Device status and health monitoring
    private static func handleRequestStatus(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: status_type(1) = 1 byte
        let statusType = frame.payload.count > 0 ? frame.payload[0] : 0x00

        var responsePayload = Data()
        responsePayload.append(statusType) // Echo request type

        switch statusType {
        case 1: // Basic status
            let (battery, used, total) = await radioState.getBatteryAndStorageInfo()
            responsePayload.append(battery)
            responsePayload.appendUInt32LE(used)
            responsePayload.appendUInt32LE(total)
            responsePayload.append(0x01) // Online status

        case 2: // Network status
            responsePayload.append(0x03) // Connected nodes count (mock)
            responsePayload.append(0x02) // Hop count to gateway
            responsePayload.appendUInt16LE(85) // Signal strength
            responsePayload.appendUInt32LE(12345) // Uptime in seconds

        case 3: // Advanced status with min/max/avg
            let mmaData = await radioState.getMinMaxAvgData()
            var tempMin = mmaData.min
            var tempMax = mmaData.max
            var tempAvg = mmaData.avg
            responsePayload.append(Data(bytes: &tempMin, count: 4))
            responsePayload.append(Data(bytes: &tempMax, count: 4))
            responsePayload.append(Data(bytes: &tempAvg, count: 4))

        default: // Generic status
            responsePayload.append(0x01) // Online
            responsePayload.append(0x00) // No errors
        }

        logger.info("Status request processed: type=\(statusType)")

        return RadioFrame(code: 0x87, payload: responsePayload) // PUSH_CODE_STATUS_RESPONSE
    }

    /// Handle CMD_REQUEST_NEIGHBOURS (63)
    /// Firmware Reference: Neighbor table and network topology information
    private static func handleRequestNeighbours(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: request_type(1) = 1 byte
        let requestType = frame.payload.count > 0 ? frame.payload[0] : 0x00

        let neighborTable = await radioState.getNeighborTable()

        var responsePayload = Data()
        responsePayload.append(requestType) // Echo request type
        responsePayload.append(UInt8(min(neighborTable.count, 255))) // Neighbor count (max 255)

        // Add neighbor information for each neighbor
        for neighbor in neighborTable.prefix(255) { // Limit to 255 neighbors
            responsePayload.append(neighbor.publicKey) // 32-byte public key
            responsePayload.append(UInt8(bitPattern: neighbor.signalStrength)) // RSSI (convert to uint8)
            responsePayload.append(neighbor.hopCount)

            // Last seen timestamp (4 bytes, little-endian)
            let timestamp = UInt32(neighbor.lastSeen.timeIntervalSince1970)
            responsePayload.appendUInt32LE(timestamp)
        }

        logger.info("Neighbour request processed: \(neighborTable.count) neighbors returned")

        return RadioFrame(code: 0x87, payload: responsePayload) // PUSH_CODE_STATUS_RESPONSE
    }

    private static func sendErrorResponse(_: Error, rxChar: RXCharacteristic) async {
        let errorCode: UInt8 = 6 // ERR_CODE_ILLEGAL_ARG (default)
        let response = RadioFrame(code: 1, payload: Data([errorCode])) // RESP_CODE_ERR
        await rxChar.sendNotification(response.encode())
    }

    // MARK: - Phase 2 Helper Methods

    /// Encode contact for sharing/import/export operations
    private static func encodeContactForSharing(_ contact: MockContact) throws -> Data {
        var data = Data()

        // Encode contact information in a simple format
        // Format: version(1) + pubkey(32) + name_len(1) + name + type(1) + flags(1)
        data.append(1) // Version

        // Public key (32 bytes)
        data.append(contact.publicKey)

        // Name (length-prefixed)
        guard let nameData = contact.name.data(using: .utf8) else {
            throw RadioError.invalidFrame
        }
        let nameLength = UInt8(min(nameData.count, 32))
        data.append(nameLength)
        data.append(nameData.prefix(Int(nameLength)))

        // Type and flags
        data.append(contact.type)
        data.append(contact.flags)

        // Location (optional)
        let hasLocation = contact.latitude != nil && contact.longitude != nil
        data.append(hasLocation ? 1 : 0)
        if hasLocation {
            let latInt = Int32((contact.latitude ?? 0) * 1_000_000)
            let lonInt = Int32((contact.longitude ?? 0) * 1_000_000)
            data.appendInt32LE(latInt)
            data.appendInt32LE(lonInt)
        }

        return data
    }

    /// Decode contact from sharing/import/export data
    private static func decodeContactFromSharingData(_ data: Data) throws -> MockContact {
        guard data.count >= 36 else { // version(1) + pubkey(32) + name_len(1) + at least name(1)
            throw RadioError.invalidFrame
        }

        let version = data[0]
        guard version == 1 else {
            throw RadioError.invalidFrame
        }

        let publicKey = data.subdata(in: 1..<33)
        let nameLength = Int(data[33])
        guard data.count >= 34 + nameLength else {
            throw RadioError.invalidFrame
        }

        let nameData = data.subdata(in: 34..<(34 + nameLength))
        guard let name = String(data: nameData, encoding: .utf8) else {
            throw RadioError.invalidFrame
        }

        let typeIndex = 34 + nameLength
        guard data.count > typeIndex else {
            throw RadioError.invalidFrame
        }

        let type = data[typeIndex]
        let flags = data[typeIndex + 1]

        var latitude: Double?
        var longitude: Double?

        let hasLocationIndex = typeIndex + 2
        if hasLocationIndex < data.count && data[hasLocationIndex] == 1 {
            let locationDataIndex = hasLocationIndex + 1
            guard data.count >= locationDataIndex + 8 else {
                throw RadioError.invalidFrame
            }

            let latInt = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: locationDataIndex, as: Int32.self) }
            let lonInt = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: locationDataIndex + 4, as: Int32.self) }

            latitude = Double(latInt) / 1_000_000.0
            longitude = Double(lonInt) / 1_000_000.0
        }

        return MockContact(
            publicKey: publicKey,
            name: name,
            type: type,
            flags: flags,
            outPathLength: 0,
            outPath: nil,
            lastAdvertisement: Date(),
            latitude: latitude,
            longitude: longitude,
            lastModified: Date()
        )
    }

    /// Generate mock status response based on type
    private static func generateStatusResponse(statusType: UInt8, requestData: Data) -> Data {
        var response = Data()
        response.append(statusType) // Echo status type

        switch statusType {
        case 1: // Basic status
            response.append(1) // Online status
            response.appendUInt32LE(100) // Battery percentage
            response.appendUInt32LE(5) // Signal strength

        case 2: // Detailed status
            response.append(1) // Online status
            response.appendUInt32LE(95) // Battery percentage
            response.appendUInt32LE(8) // Signal strength
            response.appendUInt32LE(12345) // Uptime in seconds
            response.append(42) // Temperature (mock)

        default: // Generic status
            response.append(1) // Online status
            response.appendUInt32LE(100) // Battery percentage
        }

        return response
    }

    // MARK: - Phase 3: System Command Handlers

    /// Handle CMD_REBOOT (19)
    /// Firmware Reference: Device reboot simulation
    private static func handleReboot(radioState: BLERadioState) async throws -> RadioFrame {
        // Simulate reboot by resetting volatile state
        await radioState.simulateReboot()

        logger.info("Device reboot simulated")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SIGN_START (33)
    /// Firmware Reference: Begin digital signing session
    private static func handleSignStart(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: data_length(4) + data_hash(32) = 36 bytes
        guard frame.payload.count >= 36 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let dataLength = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let dataHash = frame.payload.subdata(in: 4..<36)

        // Validate data length (reasonable range)
        guard dataLength <= 1000000 else { // Max 1MB for mock
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Start signing session
        let sessionId = await radioState.startSigningSession(dataLength: dataLength, dataHash: dataHash)

        // Build response: session_id(4)
        var payload = Data()
        payload.appendUInt32LE(sessionId)

        logger.info("Started signing session: \(sessionId)")

        return RadioFrame(code: 17, payload: payload) // RESP_CODE_SIGN_SESSION
    }

    /// Handle CMD_SIGN_DATA (34)
    /// Firmware Reference: Add data to signing session
    private static func handleSignData(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: session_id(4) + chunk_index(2) + data_chunk(variable)
        guard frame.payload.count >= 6 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let sessionId = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let chunkIndex = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self) }
        let dataChunk = frame.payload.count > 6 ? frame.payload.subdata(in: 6..<frame.payload.count) : Data()

        // Add data to signing session
        let success = await radioState.addDataToSigningSession(sessionId: sessionId, chunkIndex: chunkIndex, data: dataChunk)

        guard success else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        logger.info("Added data to signing session: \(sessionId), chunk \(chunkIndex)")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SIGN_FINISH (35)
    /// Firmware Reference: Complete digital signing and get signature
    private static func handleSignFinish(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: session_id(4) = 4 bytes
        guard frame.payload.count == 4 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let sessionId = frame.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }

        // Complete signing and get signature
        guard let signature = await radioState.finishSigningSession(sessionId: sessionId) else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        logger.info("Completed signing session: \(sessionId)")

        return RadioFrame(code: 18, payload: signature) // RESP_CODE_SIGNATURE
    }

    /// Handle CMD_SET_OTHER_PARAMS (38)
    /// Firmware Reference: Set other device parameters
    private static func handleSetOtherParams(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: param_count(1) + parameters(variable)
        guard !frame.payload.isEmpty else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let paramCount = frame.payload[0]
        guard paramCount > 0 && paramCount <= 10 else { // Max 10 parameters
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Parse and set parameters
        var offset = 1
        for _ in 0..<Int(paramCount) {
            guard offset + 2 <= frame.payload.count else {
                break
            }
            let paramType = frame.payload[offset]
            let paramLength = frame.payload[offset + 1]
            offset += 2

            guard offset + Int(paramLength) <= frame.payload.count else {
                break
            }

            let paramData = frame.payload.subdata(in: offset..<(offset + Int(paramLength)))
            await radioState.setOtherParameter(type: paramType, data: paramData)
            offset += Int(paramLength)
        }

        logger.info("Set \(paramCount) other parameters")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_FACTORY_RESET (51)
    /// Firmware Reference: Factory reset device to default state
    private static func handleFactoryReset(radioState: BLERadioState) async throws -> RadioFrame {
        // Perform factory reset
        await radioState.factoryReset()

        logger.info("Factory reset completed")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Phase 4: v8+ Features Command Handlers

    /// Handle CMD_GET_FLOOD_SCOPE (57)
    /// Firmware Reference: Get current flood scope configuration
    private static func handleGetFloodScope(radioState: BLERadioState) async throws -> RadioFrame {
        let floodScopeInfo = await radioState.getFloodScopeInfo()

        // Build response: flood_scope(1) + transport_key(32)
        var payload = Data()
        payload.append(floodScopeInfo.floodScope)
        payload.append(floodScopeInfo.transportKey)

        return RadioFrame(code: 25, payload: payload) // RESP_CODE_FLOOD_SCOPE
    }

    // MARK: - Remaining Command Handlers for 100% Protocol Coverage

    /// Handle CMD_GET_MULTI_ACKS (56)
    /// Firmware Reference: Multi-ACK status retrieval for v7+ enhanced acknowledgment
    private static func handleGetMultiAcks(radioState: BLERadioState) async throws -> RadioFrame {
        // Get current multi-ACK status from radio state
        let multiAckStatus = await radioState.getMultiAckStatus()

        // Build response: enabled_flag(1) + active_count(1) + ack_entries(8 * 12 bytes)
        var payload = Data()
        payload.append(multiAckStatus.enabled ? 1 : 0) // Multi-ACK enabled flag
        payload.append(UInt8(min(multiAckStatus.activeAcks.count, 8))) // Active ACK count (max 8)

        // Add ACK entries: ack_code(4) + contact_key_prefix(6) + timestamp(4) + timeout_ms(4) = 18 bytes each
        for ackEntry in multiAckStatus.activeAcks.prefix(8) {
            payload.appendUInt32LE(ackEntry.ackCode)
            payload.append(ackEntry.contactKeyPrefix)
            payload.appendUInt32LE(UInt32(ackEntry.timestamp.timeIntervalSince1970))
            payload.appendUInt32LE(ackEntry.timeoutMs)
        }

        logger.info("Multi-ACK status retrieved: \(multiAckStatus.activeAcks.count) active ACKs")

        return RadioFrame(code: 24, payload: payload) // RESP_CODE_MULTI_ACKS_STATUS
    }

    /// Handle CMD_SEND_PATH_DISCOVERY (58)
    /// Firmware Reference: Path discovery push notification for network topology updates
    private static func handleSendPathDiscovery(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: destination_public_key(32) + path_data(variable) = minimum 32 bytes
        guard frame.payload.count >= 32 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let destinationPublicKey = frame.payload.subdata(in: 0..<32)
        let pathData = frame.payload.count > 32 ? frame.payload.subdata(in: 32..<frame.payload.count) : Data()

        // Parse path data: hop_count(1) + hop_nodes(32 * hop_count)
        guard !pathData.isEmpty else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let hopCount = Int(pathData[0])
        let expectedDataSize = 1 + (hopCount * 32) // hop_count byte + hop nodes
        guard pathData.count >= expectedDataSize else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Extract hop nodes
        var hopNodes: [Data] = []
        for i in 0..<hopCount {
            let startIndex = 1 + (i * 32)
            let endIndex = startIndex + 32
            guard endIndex <= pathData.count else { break }
            let hopNode = pathData.subdata(in: startIndex..<endIndex)
            hopNodes.append(hopNode)
        }

        // Store discovered path in radio state
        await radioState.updateDiscoveredPath(to: destinationPublicKey, path: hopNodes)

        // Queue path discovery push notification
        var pushPayload = Data()
        pushPayload.append(destinationPublicKey)
        pushPayload.append(UInt8(hopCount))
        for hopNode in hopNodes {
            pushPayload.append(hopNode)
        }

        // Send as push notification (async)
        let pushFrame = RadioFrame(code: 0x8D, payload: pushPayload) // PUSH_CODE_PATH_DISCOVERY_RESPONSE
        try await radioState.enqueueOfflineFrame(pushFrame)

        logger.info("Path discovery processed: \(hopCount) hops to destination")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    /// Handle CMD_SEND_TRACE (59)
    /// Firmware Reference: Trace command for network diagnostics and debugging
    private static func handleSendTrace(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: target_public_key(32) + trace_type(1) + trace_options(1) = minimum 34 bytes
        guard frame.payload.count >= 34 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let targetPublicKey = frame.payload.subdata(in: 0..<32)
        let traceType = frame.payload[32]
        let traceOptions = frame.payload[33]

        // Generate trace data based on type
        let traceData = await generateTraceData(
            targetKey: targetPublicKey,
            traceType: traceType,
            options: traceOptions,
            radioState: radioState
        )

        // Build trace response: trace_type(1) + success_flag(1) + trace_data(variable)
        var responsePayload = Data()
        responsePayload.append(traceType)
        responsePayload.append(0x01) // Success flag

        // Add trace-specific data
        switch traceType {
        case 1: // Path trace
            responsePayload.append(UInt8(traceData.pathNodes.count))
            for node in traceData.pathNodes {
                responsePayload.append(node.publicKey)
                responsePayload.append(UInt8(bitPattern: node.rssi))
                responsePayload.appendUInt16LE(node.latencyMs)
            }

        case 2: // Signal trace
            responsePayload.appendUInt16LE(traceData.signalStrength)
            responsePayload.appendUInt16LE(traceData.noiseLevel)
            responsePayload.appendUInt32LE(traceData.packetLossRate)

        case 3: // Performance trace
            responsePayload.appendUInt32LE(traceData.roundTripTime)
            responsePayload.appendUInt16LE(traceData.throughput)
            responsePayload.appendUInt16LE(traceData.queueDepth)

        default: // Generic trace
            responsePayload.append(traceData.rawData)
        }

        logger.info("Trace completed: type=\(traceType), \(responsePayload.count) bytes")

        return RadioFrame(code: 0x89, payload: responsePayload) // PUSH_CODE_TRACE_DATA
    }

    /// Handle CMD_CHANGE_CONTACT_PATH (60)
    /// Firmware Reference: Modify contact's network path for routing optimization
    private static func handleChangeContactPath(frame: RadioFrame, radioState: BLERadioState) async throws -> RadioFrame {
        // Payload: contact_public_key(32) + new_path_length(1) + new_path(64 bytes) = 97 bytes
        guard frame.payload.count >= 97 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        let contactPublicKey = frame.payload.subdata(in: 0..<32)
        let newPathLength = Int(frame.payload[32])
        let newPathData = frame.payload.subdata(in: 33..<97)

        // Validate contact exists
        guard let contact = await radioState.getContactByPublicKey(contactPublicKey) else {
            return RadioFrame(code: 1, payload: Data([2])) // RESP_CODE_ERR, ERR_CODE_NOT_FOUND
        }

        // Validate path length
        guard newPathLength <= 64 else {
            return RadioFrame(code: 1, payload: Data([6])) // RESP_CODE_ERR, ERR_CODE_ILLEGAL_ARG
        }

        // Extract actual path nodes (32-byte public keys)
        let actualPathData = newPathData.prefix(newPathLength)
        var pathNodes: [Data] = []

        // Parse path nodes (assuming 32-byte keys, but could be variable based on implementation)
        let nodeSize = 32
        for i in stride(from: 0, to: actualPathData.count, by: nodeSize) {
            let endIndex = min(i + nodeSize, actualPathData.count)
            if endIndex - i >= 4 { // Minimum node identifier size
                pathNodes.append(Data(actualPathData[i..<endIndex]))
            }
        }

        // Update contact path in radio state
        await radioState.setContactPath(for: contactPublicKey, path: pathNodes)

        // Also update the contact's outPath if needed
        var updatedContact = contact
        updatedContact.outPathLength = UInt8(newPathLength)
        updatedContact.outPath = Data(actualPathData)
        updatedContact.lastModified = Date()

        // Update contact in storage
        try await radioState.addOrUpdateContact(updatedContact)

        logger.info("Contact path updated: '\(contact.name)', \(pathNodes.count) nodes")

        return RadioFrame(code: 0, payload: Data()) // RESP_CODE_OK
    }

    // MARK: - Helper Methods for New Commands

    /// Generate trace data based on trace type
    private static func generateTraceData(
        targetKey: Data,
        traceType: UInt8,
        options: UInt8,
        radioState: BLERadioState
    ) async -> TraceData {
        switch traceType {
        case 1: // Path trace
            let path = await radioState.discoverPath(to: targetKey)
            let pathNodes = path.enumerated().map { index, nodeKey in
                TracePathNode(
                    publicKey: nodeKey,
                    rssi: Int8.random(in: -90 ..< -30),
                    latencyMs: UInt16(index * 50 + 10)
                )
            }
            return TraceData(pathNodes: pathNodes)

        case 2: // Signal trace
            return TraceData(
                signalStrength: UInt16.random(in: 70...95),
                noiseLevel: UInt16.random(in: 85...95),
                packetLossRate: UInt32.random(in: 0...5)
            )

        case 3: // Performance trace
            return TraceData(
                roundTripTime: UInt32.random(in: 100...1000),
                throughput: UInt16.random(in: 10...100),
                queueDepth: UInt16.random(in: 0...10)
            )

        default: // Generic trace
            return TraceData(rawData: generateMockTraceData(options: options))
        }
    }

    /// Generate mock trace data based on options
    private static func generateMockTraceData(options: UInt8) -> Data {
        var data = Data()
        let dataSize = Int(options & 0x0F) + 1 // Use lower 4 bits for size

        for _ in 0..<dataSize {
            data.append(UInt8.random(in: 0x00...0xFF))
        }

        return data
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
