import Foundation

/// Events emitted by a MeshCore device during communication.
///
/// `MeshEvent` represents all possible events that can be received from a MeshCore
/// mesh networking device. Events are delivered through the ``MeshCoreSession/events()``
/// async stream.
///
/// ## Event Categories
///
/// Events fall into several categories:
///
/// - **Connection**: Session lifecycle and connection state changes
/// - **Command Responses**: Success/error responses to commands
/// - **Contacts**: Contact list updates and discovery
/// - **Messages**: Incoming messages and send confirmations
/// - **Network**: Advertisements, path updates, and routing events
/// - **Telemetry**: Sensor data and device statistics
///
/// ## Usage
///
/// ```swift
/// for await event in await session.events() {
///     switch event {
///     case .contactMessageReceived(let message):
///         handleMessage(message)
///     case .advertisement(let publicKey):
///         print("Saw node: \(publicKey.hexString)")
///     case .connectionStateChanged(let state):
///         updateUI(for: state)
///     default:
///         break
///     }
/// }
/// ```
public enum MeshEvent: Sendable {
    // MARK: - Connection Lifecycle

    /// Connection state changed.
    ///
    /// Emitted when the transport connection state changes (connecting, connected, disconnected, etc.).
    /// Subscribe to ``MeshCoreSession/connectionState`` for a dedicated state stream.
    case connectionStateChanged(ConnectionState)

    // MARK: - Command Responses

    /// Command completed successfully.
    ///
    /// Emitted when a command sent to the device completes successfully.
    /// - Parameter value: Optional success value returned by the command.
    case ok(value: UInt32?)

    /// Command failed with error.
    ///
    /// Emitted when a command sent to the device fails.
    /// - Parameter code: Device-specific error code, if available.
    case error(code: UInt8?)

    // MARK: - Device Information

    /// Device self-information received.
    ///
    /// Emitted after ``MeshCoreSession/start()`` with the device's identity and configuration.
    case selfInfo(SelfInfo)

    /// Device capabilities received.
    ///
    /// Emitted in response to ``MeshCoreSession/queryDevice()`` with hardware capabilities.
    case deviceInfo(DeviceCapabilities)

    /// Battery status received.
    ///
    /// Emitted in response to ``MeshCoreSession/getBattery()``.
    case battery(BatteryInfo)

    /// Current device time received.
    ///
    /// Emitted in response to ``MeshCoreSession/getTime()``.
    case currentTime(Date)

    /// Custom variables received.
    ///
    /// Emitted in response to ``MeshCoreSession/getCustomVars()``.
    case customVars([String: String])

    /// Channel configuration received.
    ///
    /// Emitted in response to ``MeshCoreSession/getChannel(index:)``.
    case channelInfo(ChannelInfo)

    /// Core statistics received.
    ///
    /// Emitted in response to ``MeshCoreSession/getStatsCore()``.
    case statsCore(CoreStats)

    /// Radio statistics received.
    ///
    /// Emitted in response to ``MeshCoreSession/getStatsRadio()``.
    case statsRadio(RadioStats)

    /// Packet statistics received.
    ///
    /// Emitted in response to ``MeshCoreSession/getStatsPackets()``.
    case statsPackets(PacketStats)

    // MARK: - Contact Management

    /// Contact list transfer started.
    ///
    /// Emitted at the start of a contact list transfer, indicating the total count.
    /// - Parameter count: Total number of contacts to be received.
    case contactsStart(count: Int)

    /// Contact received.
    ///
    /// Emitted for each contact during a contact list transfer.
    case contact(MeshContact)

    /// Contact list transfer completed.
    ///
    /// Emitted at the end of a contact list transfer.
    /// - Parameter lastModified: Timestamp of the most recently modified contact.
    case contactsEnd(lastModified: Date)

    /// New contact discovered.
    ///
    /// Emitted when a new contact is added to the device's contact list.
    case newContact(MeshContact)

    /// Contact URI received.
    ///
    /// Emitted in response to ``MeshCoreSession/exportContact(publicKey:)`` with a shareable contact URI.
    case contactURI(String)

    // MARK: - Messaging

    /// Message queued for sending.
    ///
    /// Emitted when a message is successfully queued for transmission.
    /// Wait for an ``acknowledgement(code:)`` event to confirm delivery.
    case messageSent(MessageSentInfo)

    /// Direct message received from a contact.
    ///
    /// Emitted when a private message is received from another node.
    case contactMessageReceived(ContactMessage)

    /// Channel broadcast message received.
    ///
    /// Emitted when a message is received on a subscribed channel.
    case channelMessageReceived(ChannelMessage)

    /// No more messages waiting.
    ///
    /// Emitted by ``MeshCoreSession/getMessage()`` when the message queue is empty.
    case noMoreMessages

    /// Messages are waiting to be fetched.
    ///
    /// Emitted when the device has pending messages in its queue.
    /// Use ``MeshCoreSession/getMessage()`` to fetch them, or enable
    /// ``MeshCoreSession/startAutoMessageFetching()`` for automatic handling.
    case messagesWaiting

    // MARK: - Network Events

    /// Advertisement received from a node.
    ///
    /// Emitted when the device receives an advertisement broadcast from another mesh node.
    /// - Parameter publicKey: Public key of the advertising node.
    case advertisement(publicKey: Data)

    /// Routing path updated.
    ///
    /// Emitted when the device learns a new or updated routing path to a node.
    /// - Parameter publicKey: Public key of the destination node.
    case pathUpdate(publicKey: Data)

    /// Message delivery acknowledgement.
    ///
    /// Emitted when the device receives confirmation that a sent message was delivered.
    /// Match against ``MessageSentInfo/expectedAck`` to correlate with sent messages.
    /// - Parameter code: Acknowledgement code to match against expected value.
    case acknowledgement(code: Data)

    /// Trace route data received.
    ///
    /// Emitted in response to ``MeshCoreSession/sendTrace(tag:authCode:flags:path:)``
    /// with path information.
    case traceData(TraceInfo)

    /// Path discovery response.
    ///
    /// Emitted in response to ``MeshCoreSession/sendPathDiscovery(to:)`` with routing paths.
    case pathResponse(PathInfo)

    // MARK: - Authentication

    /// Login succeeded.
    ///
    /// Emitted when authentication to a remote node succeeds.
    case loginSuccess(LoginInfo)

    /// Login failed.
    ///
    /// Emitted when authentication to a remote node fails.
    /// - Parameter publicKeyPrefix: Public key prefix of the target node, if available.
    case loginFailed(publicKeyPrefix: Data?)

    // MARK: - Binary Protocol Responses

    /// Status response from a remote node.
    ///
    /// Emitted in response to ``MeshCoreSession/requestStatus(from:)``.
    case statusResponse(StatusResponse)

    /// Telemetry response from a remote node.
    ///
    /// Emitted in response to ``MeshCoreSession/requestTelemetry(from:)`` or
    /// ``MeshCoreSession/getSelfTelemetry()``.
    case telemetryResponse(TelemetryResponse)

    /// Generic binary protocol response.
    ///
    /// Emitted for binary protocol responses that don't have specific event types.
    /// - Parameter tag: Request correlation tag.
    /// - Parameter data: Response payload.
    case binaryResponse(tag: Data, data: Data)

    /// Min/Max/Average telemetry response.
    ///
    /// Emitted in response to ``MeshCoreSession/requestMMA(from:start:end:)``.
    case mmaResponse(MMAResponse)

    /// Access control list response.
    ///
    /// Emitted in response to ``MeshCoreSession/requestACL(from:)``.
    case aclResponse(ACLResponse)

    /// Neighbours list response.
    ///
    /// Emitted in response to ``MeshCoreSession/requestNeighbours(from:count:offset:orderBy:pubkeyPrefixLength:)``.
    case neighboursResponse(NeighboursResponse)

    // MARK: - Cryptographic Signing

    /// Signing session started.
    ///
    /// Emitted in response to ``MeshCoreSession/signStart()`` with maximum data size.
    /// - Parameter maxLength: Maximum number of bytes that can be signed.
    case signStart(maxLength: Int)

    /// Cryptographic signature generated.
    ///
    /// Emitted in response to ``MeshCoreSession/signFinish(timeout:)`` with the signature.
    case signature(Data)

    /// Feature disabled.
    ///
    /// Emitted when a requested feature is disabled on the device.
    /// - Parameter reason: Human-readable reason for the disabled feature.
    case disabled(reason: String)

    // MARK: - Raw Data and Logging

    /// Raw radio data received.
    ///
    /// Emitted when the device forwards raw radio packets.
    case rawData(RawDataInfo)

    /// Log data from device.
    ///
    /// Emitted when the device sends diagnostic log data.
    case logData(LogDataInfo)

    /// Raw RF log data.
    ///
    /// Emitted when the device sends low-level radio log data.
    case rxLogData(LogDataInfo)

    /// Control protocol data received.
    ///
    /// Emitted when control protocol messages are received.
    case controlData(ControlDataInfo)

    /// Node discovery response.
    ///
    /// Emitted in response to ``MeshCoreSession/sendNodeDiscoverRequest(filter:prefixOnly:tag:since:)``.
    case discoverResponse(DiscoverResponse)

    // MARK: - Key Management

    /// Private key exported.
    ///
    /// Emitted in response to ``MeshCoreSession/exportPrivateKey()`` with the device's private key.
    case privateKey(Data)

    // MARK: - Debug and Diagnostics

    /// Packet parsing failed.
    ///
    /// Emitted when the session receives data it cannot parse.
    /// This is a diagnostic event for debugging protocol issues.
    /// - Parameter data: The raw data that failed to parse.
    /// - Parameter reason: Human-readable reason for the parse failure.
    case parseFailure(data: Data, reason: String)
}

// MARK: - Supporting Types for MeshEvent Associated Values

/// Information returned when a message is successfully queued for sending.
///
/// This struct is returned by message-sending methods and contains information
/// needed to wait for delivery acknowledgement.
public struct MessageSentInfo: Sendable, Equatable {
    public let type: UInt8
    public let expectedAck: Data
    public let suggestedTimeoutMs: UInt32

    public init(type: UInt8, expectedAck: Data, suggestedTimeoutMs: UInt32) {
        self.type = type
        self.expectedAck = expectedAck
        self.suggestedTimeoutMs = suggestedTimeoutMs
    }
}

/// A message received from a mesh contact.
///
/// Contact messages are private messages sent directly to your device from
/// another node in the mesh network.
public struct ContactMessage: Sendable, Equatable {
    public let senderPublicKeyPrefix: Data
    public let pathLength: UInt8
    public let textType: UInt8
    public let senderTimestamp: Date
    public let signature: Data?
    public let text: String
    public let snr: Double?

    public init(
        senderPublicKeyPrefix: Data,
        pathLength: UInt8,
        textType: UInt8,
        senderTimestamp: Date,
        signature: Data?,
        text: String,
        snr: Double?
    ) {
        self.senderPublicKeyPrefix = senderPublicKeyPrefix
        self.pathLength = pathLength
        self.textType = textType
        self.senderTimestamp = senderTimestamp
        self.signature = signature
        self.text = text
        self.snr = snr
    }
}

/// A message received on a broadcast channel.
///
/// Channel messages are broadcast messages visible to all nodes subscribed
/// to the same channel.
public struct ChannelMessage: Sendable, Equatable {
    public let channelIndex: UInt8
    public let pathLength: UInt8
    public let textType: UInt8
    public let senderTimestamp: Date
    public let text: String
    public let snr: Double?

    public init(
        channelIndex: UInt8,
        pathLength: UInt8,
        textType: UInt8,
        senderTimestamp: Date,
        text: String,
        snr: Double?
    ) {
        self.channelIndex = channelIndex
        self.pathLength = pathLength
        self.textType = textType
        self.senderTimestamp = senderTimestamp
        self.text = text
        self.snr = snr
    }
}

/// Configuration information for a broadcast channel.
///
/// Channels allow broadcast messaging to all nodes sharing the same channel
/// name and secret key.
public struct ChannelInfo: Sendable, Equatable {
    public let index: UInt8
    public let name: String
    public let secret: Data

    public init(index: UInt8, name: String, secret: Data) {
        self.index = index
        self.name = name
        self.secret = secret
    }
}

/// Status response from a remote node
/// Note on offset logic (per Python parsing.py):
/// - Binary request responses: offset=0, fields start immediately after response code
/// - Push notification responses: offset=8, pubkey_prefix at bytes 2-8, fields follow
/// The parser must handle both cases based on whether this is a solicited vs unsolicited response
public struct StatusResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let battery: Int
    public let txQueueLength: Int
    public let noiseFloor: Int
    public let lastRSSI: Int
    public let packetsReceived: UInt32
    public let packetsSent: UInt32
    public let airtime: UInt32
    public let uptime: UInt32
    public let sentFlood: UInt32
    public let sentDirect: UInt32
    public let receivedFlood: UInt32
    public let receivedDirect: UInt32
    public let fullEvents: Int
    public let lastSNR: Double
    public let directDuplicates: Int
    public let floodDuplicates: Int
    public let rxAirtime: UInt32

    public init(
        publicKeyPrefix: Data,
        battery: Int,
        txQueueLength: Int,
        noiseFloor: Int,
        lastRSSI: Int,
        packetsReceived: UInt32,
        packetsSent: UInt32,
        airtime: UInt32,
        uptime: UInt32,
        sentFlood: UInt32,
        sentDirect: UInt32,
        receivedFlood: UInt32,
        receivedDirect: UInt32,
        fullEvents: Int,
        lastSNR: Double,
        directDuplicates: Int,
        floodDuplicates: Int,
        rxAirtime: UInt32
    ) {
        self.publicKeyPrefix = publicKeyPrefix
        self.battery = battery
        self.txQueueLength = txQueueLength
        self.noiseFloor = noiseFloor
        self.lastRSSI = lastRSSI
        self.packetsReceived = packetsReceived
        self.packetsSent = packetsSent
        self.airtime = airtime
        self.uptime = uptime
        self.sentFlood = sentFlood
        self.sentDirect = sentDirect
        self.receivedFlood = receivedFlood
        self.receivedDirect = receivedDirect
        self.fullEvents = fullEvents
        self.lastSNR = lastSNR
        self.directDuplicates = directDuplicates
        self.floodDuplicates = floodDuplicates
        self.rxAirtime = rxAirtime
    }
}

/// Core stats (9 bytes payload, little-endian per Python reader.py):
/// - Bytes 0-1: UInt16 - battery_mv
/// - Bytes 2-5: UInt32 - uptime_secs
/// - Bytes 6-7: UInt16 - errors
/// - Byte 8: UInt8 - queue_len
public struct CoreStats: Sendable, Equatable {
    public let batteryMV: UInt16
    public let uptimeSeconds: UInt32
    public let errors: UInt16
    public let queueLength: UInt8

    public init(batteryMV: UInt16, uptimeSeconds: UInt32, errors: UInt16, queueLength: UInt8) {
        self.batteryMV = batteryMV
        self.uptimeSeconds = uptimeSeconds
        self.errors = errors
        self.queueLength = queueLength
    }
}

/// Radio stats (12 bytes payload, little-endian per Python reader.py):
/// - Bytes 0-1: Int16 - noise_floor (dBm)
/// - Byte 2: Int8 - last_rssi (dBm)
/// - Byte 3: Int8 - last_snr (raw, divide by 4.0 for dB)
/// - Bytes 4-7: UInt32 - tx_air_secs
/// - Bytes 8-11: UInt32 - rx_air_secs
public struct RadioStats: Sendable, Equatable {
    public let noiseFloor: Int16
    public let lastRSSI: Int8
    public let lastSNR: Double
    public let txAirtimeSeconds: UInt32
    public let rxAirtimeSeconds: UInt32

    public init(
        noiseFloor: Int16,
        lastRSSI: Int8,
        lastSNR: Double,
        txAirtimeSeconds: UInt32,
        rxAirtimeSeconds: UInt32
    ) {
        self.noiseFloor = noiseFloor
        self.lastRSSI = lastRSSI
        self.lastSNR = lastSNR
        self.txAirtimeSeconds = txAirtimeSeconds
        self.rxAirtimeSeconds = rxAirtimeSeconds
    }
}

/// Packet stats (24 bytes payload, little-endian per Python reader.py):
/// - Bytes 0-3: UInt32 - recv
/// - Bytes 4-7: UInt32 - sent
/// - Bytes 8-11: UInt32 - flood_tx
/// - Bytes 12-15: UInt32 - direct_tx
/// - Bytes 16-19: UInt32 - flood_rx
/// - Bytes 20-23: UInt32 - direct_rx
public struct PacketStats: Sendable, Equatable {
    public let received: UInt32
    public let sent: UInt32
    public let floodTx: UInt32
    public let directTx: UInt32
    public let floodRx: UInt32
    public let directRx: UInt32

    public init(
        received: UInt32,
        sent: UInt32,
        floodTx: UInt32,
        directTx: UInt32,
        floodRx: UInt32,
        directRx: UInt32
    ) {
        self.received = received
        self.sent = sent
        self.floodTx = floodTx
        self.directTx = directTx
        self.floodRx = floodRx
        self.directRx = directRx
    }
}

/// Trace route information
public struct TraceInfo: Sendable, Equatable {
    public let tag: UInt32
    public let authCode: UInt32
    public let flags: UInt8
    public let pathLength: UInt8
    public let path: [TraceNode]

    public init(tag: UInt32, authCode: UInt32, flags: UInt8, pathLength: UInt8, path: [TraceNode]) {
        self.tag = tag
        self.authCode = authCode
        self.flags = flags
        self.pathLength = pathLength
        self.path = path
    }
}

/// A node in a trace path
public struct TraceNode: Sendable, Equatable {
    public let hash: UInt8?
    public let snr: Double

    public init(hash: UInt8?, snr: Double) {
        self.hash = hash
        self.snr = snr
    }
}

/// Path discovery information
public struct PathInfo: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let outPath: Data
    public let inPath: Data

    public init(publicKeyPrefix: Data, outPath: Data, inPath: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.outPath = outPath
        self.inPath = inPath
    }
}

/// Login success information
public struct LoginInfo: Sendable, Equatable {
    public let permissions: UInt8
    public let isAdmin: Bool
    public let publicKeyPrefix: Data

    public init(permissions: UInt8, isAdmin: Bool, publicKeyPrefix: Data) {
        self.permissions = permissions
        self.isAdmin = isAdmin
        self.publicKeyPrefix = publicKeyPrefix
    }
}

/// Telemetry response from a remote node
public struct TelemetryResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let tag: Data?
    public let rawData: Data

    /// Parsed LPP data points from the raw telemetry data
    public var dataPoints: [LPPDataPoint] {
        LPPDecoder.decode(rawData)
    }

    public init(publicKeyPrefix: Data, tag: Data?, rawData: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.tag = tag
        self.rawData = rawData
    }
}

/// MMA (Min/Max/Average) response
public struct MMAResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let tag: Data
    public let data: [MMAEntry]

    public init(publicKeyPrefix: Data, tag: Data, data: [MMAEntry]) {
        self.publicKeyPrefix = publicKeyPrefix
        self.tag = tag
        self.data = data
    }
}

/// An entry in MMA response data
public struct MMAEntry: Sendable, Equatable {
    public let channel: UInt8
    public let type: String
    public let min: Double
    public let max: Double
    public let avg: Double

    public init(channel: UInt8, type: String, min: Double, max: Double, avg: Double) {
        self.channel = channel
        self.type = type
        self.min = min
        self.max = max
        self.avg = avg
    }
}

/// ACL (Access Control List) response
public struct ACLResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let tag: Data
    public let entries: [ACLEntry]

    public init(publicKeyPrefix: Data, tag: Data, entries: [ACLEntry]) {
        self.publicKeyPrefix = publicKeyPrefix
        self.tag = tag
        self.entries = entries
    }
}

/// An entry in ACL response data
public struct ACLEntry: Sendable, Equatable {
    public let keyPrefix: Data
    public let permissions: UInt8

    public init(keyPrefix: Data, permissions: UInt8) {
        self.keyPrefix = keyPrefix
        self.permissions = permissions
    }
}

/// Neighbours response from a remote node
/// Note: Parser context must include `pubkey_prefix_length` for proper neighbour parsing
/// (typically 6 bytes, but configurable in some firmware versions)
public struct NeighboursResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let tag: Data
    public let totalCount: Int
    public let neighbours: [Neighbour]

    public init(publicKeyPrefix: Data, tag: Data, totalCount: Int, neighbours: [Neighbour]) {
        self.publicKeyPrefix = publicKeyPrefix
        self.tag = tag
        self.totalCount = totalCount
        self.neighbours = neighbours
    }
}

/// A neighbour node
public struct Neighbour: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let secondsAgo: Int
    public let snr: Double

    public init(publicKeyPrefix: Data, secondsAgo: Int, snr: Double) {
        self.publicKeyPrefix = publicKeyPrefix
        self.secondsAgo = secondsAgo
        self.snr = snr
    }
}

/// Raw data received from device
public struct RawDataInfo: Sendable, Equatable {
    public let snr: Double
    public let rssi: Int
    public let payload: Data

    public init(snr: Double, rssi: Int, payload: Data) {
        self.snr = snr
        self.rssi = rssi
        self.payload = payload
    }
}

/// Log data from device
public struct LogDataInfo: Sendable, Equatable {
    public let snr: Double?
    public let rssi: Int?
    public let payload: Data

    public init(snr: Double?, rssi: Int?, payload: Data) {
        self.snr = snr
        self.rssi = rssi
        self.payload = payload
    }
}

/// Control data from device
public struct ControlDataInfo: Sendable, Equatable {
    public let snr: Double
    public let rssi: Int
    public let pathLength: UInt8
    public let payloadType: UInt8
    public let payload: Data

    public init(snr: Double, rssi: Int, pathLength: UInt8, payloadType: UInt8, payload: Data) {
        self.snr = snr
        self.rssi = rssi
        self.pathLength = pathLength
        self.payloadType = payloadType
        self.payload = payload
    }
}

/// Node discovery response
public struct DiscoverResponse: Sendable, Equatable {
    public let nodeType: UInt8
    public let snrIn: Double
    public let snr: Double
    public let rssi: Int
    public let pathLength: UInt8
    public let tag: Data
    public let publicKey: Data

    public init(
        nodeType: UInt8,
        snrIn: Double,
        snr: Double,
        rssi: Int,
        pathLength: UInt8,
        tag: Data,
        publicKey: Data
    ) {
        self.nodeType = nodeType
        self.snrIn = snrIn
        self.snr = snr
        self.rssi = rssi
        self.pathLength = pathLength
        self.tag = tag
        self.publicKey = publicKey
    }
}

// MARK: - Connection State

/// The current connection state of a MeshCore session.
///
/// Use this enum to update your UI based on connection status. Subscribe to
/// state changes via ``MeshCoreSession/connectionState``.
///
/// ## Example
///
/// ```swift
/// for await state in session.connectionState {
///     switch state {
///     case .connected:
///         showConnectedUI()
///     case .connecting:
///         showLoadingIndicator()
///     case .reconnecting(let attempt):
///         showReconnecting(attempt: attempt)
///     case .failed(let error):
///         showError(error)
///     case .disconnected:
///         showDisconnectedUI()
///     }
/// }
/// ```
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(MeshTransportError)
}

/// Errors that can occur at the transport layer.
///
/// These errors indicate problems with the underlying transport connection
/// (e.g., Bluetooth LE), rather than protocol-level errors.
public enum MeshTransportError: Error, Sendable, Equatable {
    case notConnected
    case connectionFailed(String)
    case sendFailed(String)
    case deviceNotFound
    case serviceNotFound
    case characteristicNotFound
}

// MARK: - Event Attributes for Filtering

extension MeshEvent {
    /// Attributes for event filtering.
    ///
    /// Returns a dictionary of key-value pairs that can be used to filter events.
    /// This enables type-safe filtering via ``EventFilter`` without runtime type checking.
    ///
    /// - Note: Not all events have attributes. Events without filterable properties
    ///   return an empty dictionary.
    public var attributes: [String: AnyHashable] {
        switch self {
        case .contactMessageReceived(let msg):
            return [
                "publicKeyPrefix": msg.senderPublicKeyPrefix,
                "textType": msg.textType
            ]
        case .channelMessageReceived(let msg):
            return [
                "channelIndex": msg.channelIndex,
                "textType": msg.textType
            ]
        case .acknowledgement(let code):
            return ["code": code]
        case .messageSent(let info):
            return [
                "type": info.type,
                "expectedAck": info.expectedAck
            ]
        case .statusResponse(let resp):
            return ["publicKeyPrefix": resp.publicKeyPrefix]
        case .telemetryResponse(let resp):
            return ["publicKeyPrefix": resp.publicKeyPrefix]
        case .advertisement(let pubKey):
            return ["publicKeyPrefix": pubKey.prefix(6)]
        case .pathUpdate(let pubKey):
            return ["publicKeyPrefix": pubKey.prefix(6)]
        case .newContact(let contact):
            return ["publicKey": contact.publicKey]
        case .contact(let contact):
            return ["publicKey": contact.publicKey]
        case .error(let code):
            return ["code": code as AnyHashable]
        case .ok(let value):
            return ["value": value as AnyHashable]
        default:
            return [:]
        }
    }
}
