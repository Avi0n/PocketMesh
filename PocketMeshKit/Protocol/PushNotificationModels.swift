import Foundation

// MARK: - Push Notification Models

/// Advertisement push notification (PUSH_NEW_ADVERT = 0x8A)
public struct AdvertisementPush: Sendable, Decodable {
    public let publicKeyPrefix: Data // 6 bytes
    public let type: UInt8
    public let name: String
    public let latitude: Double?
    public let longitude: Double?

    public init(publicKeyPrefix: Data, type: UInt8, name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.publicKeyPrefix = publicKeyPrefix
        self.type = type
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public static func decode(from data: Data) throws -> AdvertisementPush {
        guard data.count >= 8 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        let type = data[6]

        // Extract name (variable length UTF-8 string)
        let nameDataEnd = data.dropFirst(7).firstIndex(of: 0) ?? data.count
        let nameData = data.subdata(in: 7 ..< min(nameDataEnd, data.count))
        let name = String(data: nameData, encoding: .utf8) ?? ""

        // Optional coordinates (if present)
        var latitude: Double?
        var longitude: Double?

        let remainingData = data.count > (7 + nameData.count + 1) ?
            data.subdata(in: (7 + nameData.count + 1) ..< data.count) : Data()

        if remainingData.count >= 8 {
            let latRaw = remainingData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) }
            let lonRaw = remainingData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }
            latitude = Double(latRaw) / 1_000_000.0
            longitude = Double(lonRaw) / 1_000_000.0
        }

        return AdvertisementPush(
            publicKeyPrefix: publicKeyPrefix,
            type: type,
            name: name,
            latitude: latitude,
            longitude: longitude,
        )
    }
}

/// Message waiting push notification (PUSH_MESSAGE_WAITING = 0x83)
public struct MessageNotificationPush: Sendable {
    public let messageCount: UInt8
    public let hasDirectMessages: Bool
    public let hasChannelMessages: Bool
    public let channelIndex: UInt8?

    public init(messageCount: UInt8, hasDirectMessages: Bool, hasChannelMessages: Bool, channelIndex: UInt8? = nil) {
        self.messageCount = messageCount
        self.hasDirectMessages = hasDirectMessages
        self.hasChannelMessages = hasChannelMessages
        self.channelIndex = channelIndex
    }

    public static func decode(from data: Data) throws -> MessageNotificationPush {
        guard data.count >= 2 else {
            throw ProtocolError.invalidPayload
        }

        let messageCount = data[0]
        let typeFlags = data[1]

        let hasDirectMessages = (typeFlags & 0x01) != 0
        let hasChannelMessages = (typeFlags & 0x02) != 0
        let channelIndex = hasChannelMessages && data.count >= 3 ? data[2] : nil

        return MessageNotificationPush(
            messageCount: messageCount,
            hasDirectMessages: hasDirectMessages,
            hasChannelMessages: hasChannelMessages,
            channelIndex: channelIndex,
        )
    }
}

/// Send confirmation push notification (PUSH_SEND_CONFIRMED = 0x82)
public struct SendConfirmationPush: Sendable {
    public let ackCode: Data // 4 bytes
    public let messageType: UInt8
    public let deliveryStatus: DeliveryStatus

    public enum DeliveryStatus: UInt8, CaseIterable, Sendable {
        case delivered = 0
        case failed = 1
        case retrying = 2
        case pending = 3

        public var description: String {
            switch self {
            case .delivered: "Delivered"
            case .failed: "Failed"
            case .retrying: "Retrying"
            case .pending: "Pending"
            }
        }
    }

    public init(ackCode: Data, messageType: UInt8, deliveryStatus: DeliveryStatus) {
        self.ackCode = ackCode
        self.messageType = messageType
        self.deliveryStatus = deliveryStatus
    }

    public static func decode(from data: Data) throws -> SendConfirmationPush {
        guard data.count >= 6 else {
            throw ProtocolError.invalidPayload
        }

        let ackCode = data.subdata(in: 0 ..< 4)
        let messageType = data[4]
        let deliveryStatusRaw = data[5]

        guard let deliveryStatus = DeliveryStatus(rawValue: deliveryStatusRaw) else {
            throw ProtocolError.invalidPayload
        }

        return SendConfirmationPush(
            ackCode: ackCode,
            messageType: messageType,
            deliveryStatus: deliveryStatus,
        )
    }
}

/// Path updated push notification (PUSH_PATH_UPDATED = 0x81)
public struct PathUpdatePush: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let newPathLength: UInt8
    public let pathData: Data

    public init(publicKeyPrefix: Data, newPathLength: UInt8, pathData: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.newPathLength = newPathLength
        self.pathData = pathData
    }

    public static func decode(from data: Data) throws -> PathUpdatePush {
        guard data.count >= 8 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        let newPathLength = data[6]
        let pathData = data.count > 7 ? data.subdata(in: 7 ..< data.count) : Data()

        return PathUpdatePush(
            publicKeyPrefix: publicKeyPrefix,
            newPathLength: newPathLength,
            pathData: pathData,
        )
    }
}

/// Telemetry push notification (PUSH_TELEMETRY_RESPONSE = 0x8B)
public struct TelemetryPush: Sendable {
    public let batteryVoltage: UInt16 // millivolts
    public let temperature: Int16 // Celsius * 100
    public let uptime: UInt32 // seconds
    public let freeMemory: UInt32 // bytes

    public init(batteryVoltage: UInt16, temperature: Int16, uptime: UInt32, freeMemory: UInt32) {
        self.batteryVoltage = batteryVoltage
        self.temperature = temperature
        self.uptime = uptime
        self.freeMemory = freeMemory
    }

    public static func decode(from data: Data) throws -> TelemetryPush {
        guard data.count >= 12 else {
            throw ProtocolError.invalidPayload
        }

        let batteryVoltage = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt16.self) }
        let temperature = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: Int16.self) }
        let uptime = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        let freeMemory = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) }

        return TelemetryPush(
            batteryVoltage: batteryVoltage,
            temperature: temperature,
            uptime: uptime,
            freeMemory: freeMemory,
        )
    }

    /// Battery percentage estimated from voltage
    public var batteryPercentage: UInt8 {
        if batteryVoltage > 4000 { return 100 }
        if batteryVoltage > 3700 { return UInt8((batteryVoltage - 3700) * 100 / 300) }
        if batteryVoltage > 3300 { return UInt8((batteryVoltage - 3300) * 70 / 400) }
        return UInt8(max(10, Int(batteryVoltage) - 3200) / 10)
    }

    /// Temperature in Celsius
    public var temperatureCelsius: Double {
        Double(temperature) / 100.0
    }

    /// Uptime as human readable string
    public var uptimeDescription: String {
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let seconds = uptime % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Free memory in KB
    public var freeMemoryKB: UInt32 {
        freeMemory / 1024
    }
}

/// Discovery response push notification (PUSH_DISCOVERY_RESPONSE = 0x8D)
public struct DiscoveryResponsePush: Sendable {
    public let discoveredNodes: [DiscoveredNode]

    public struct DiscoveredNode: Sendable {
        public let publicKeyPrefix: Data // 6 bytes
        public let rssi: Int8
        public let pathLength: UInt8

        public init(publicKeyPrefix: Data, rssi: Int8, pathLength: UInt8) {
            self.publicKeyPrefix = publicKeyPrefix
            self.rssi = rssi
            self.pathLength = pathLength
        }
    }

    public init(discoveredNodes: [DiscoveredNode]) {
        self.discoveredNodes = discoveredNodes
    }

    public static func decode(from data: Data) throws -> DiscoveryResponsePush {
        guard data.count >= 1 else {
            throw ProtocolError.invalidPayload
        }

        let nodeCount = Int(data[0])
        guard data.count >= 1 + (nodeCount * 8) else {
            throw ProtocolError.invalidPayload
        }

        var nodes: [DiscoveredNode] = []
        for i in 0 ..< nodeCount {
            let offset = 1 + (i * 8)
            let publicKeyPrefix = data.subdata(in: offset ..< (offset + 6))
            let rssi = Int8(bitPattern: data[offset + 6])
            let pathLength = data[offset + 7]

            nodes.append(DiscoveredNode(
                publicKeyPrefix: publicKeyPrefix,
                rssi: rssi,
                pathLength: pathLength,
            ))
        }

        return DiscoveryResponsePush(discoveredNodes: nodes)
    }
}

/// Control data push notification (PUSH_CONTROL_DATA = 0x8F)
public struct ControlDataPush: Sendable {
    public let dataType: UInt8
    public let data: Data

    public init(dataType: UInt8, data: Data) {
        self.dataType = dataType
        self.data = data
    }

    public static func decode(from data: Data) throws -> ControlDataPush {
        guard data.count >= 2 else {
            throw ProtocolError.invalidPayload
        }

        let dataType = data[0]
        let dataLength = Int(data[1])

        guard data.count >= 2 + dataLength else {
            throw ProtocolError.invalidPayload
        }

        let payload = data.subdata(in: 2 ..< (2 + dataLength))

        return ControlDataPush(dataType: dataType, data: payload)
    }
}

// MARK: - Additional Push Notification Models (Phase 1 Completion)

/// Raw data push notification (PUSH_RAW_DATA = 0x84)
public struct RawDataPush: Sendable {
    public let snr: Int8 // Signal-to-noise ratio * 4
    public let rssi: Int8 // Received signal strength
    public let pathLen: UInt8 // Reserved for future use (always 0xFF)
    public let payload: Data // Raw data payload

    public init(snr: Int8, rssi: Int8, pathLen: UInt8, payload: Data) {
        self.snr = snr
        self.rssi = rssi
        self.pathLen = pathLen
        self.payload = payload
    }

    public static func decode(from data: Data) throws -> RawDataPush {
        guard data.count >= 4 else {
            throw ProtocolError.invalidPayload
        }

        let snr = Int8(bitPattern: data[0])
        let rssi = Int8(bitPattern: data[1])
        let pathLen = data[2]
        let payload = data.count > 3 ? data.subdata(in: 3 ..< data.count) : Data()

        return RawDataPush(snr: snr, rssi: rssi, pathLen: pathLen, payload: payload)
    }

    /// Signal-to-noise ratio in dB
    public var snrDecibels: Double {
        Double(snr) / 4.0
    }
}

/// Login success push notification (PUSH_LOGIN_SUCCESS = 0x85)
public struct LoginSuccessPush: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let result: UInt8 // Login result (0 = success)

    public init(publicKeyPrefix: Data, result: UInt8) {
        self.publicKeyPrefix = publicKeyPrefix
        self.result = result
    }

    public static func decode(from data: Data) throws -> LoginSuccessPush {
        guard data.count >= 7 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        let result = data[6]

        return LoginSuccessPush(publicKeyPrefix: publicKeyPrefix, result: result)
    }

    public var isSuccess: Bool {
        result == 0
    }
}

/// Login fail push notification (PUSH_LOGIN_FAIL = 0x86)
public struct LoginFailPush: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let reason: UInt8 // Failure reason

    public init(publicKeyPrefix: Data, reason: UInt8) {
        self.publicKeyPrefix = publicKeyPrefix
        self.reason = reason
    }

    public static func decode(from data: Data) throws -> LoginFailPush {
        guard data.count >= 7 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        let reason = data[6]

        return LoginFailPush(publicKeyPrefix: publicKeyPrefix, reason: reason)
    }

    public var reasonDescription: String {
        switch reason {
        case 0: "Authentication failed"
        case 1: "Contact not found"
        case 2: "Invalid password"
        case 3: "Access denied"
        default: "Unknown error"
        }
    }
}

/// Status response push notification (PUSH_STATUS_RESPONSE = 0x87)
public struct StatusResponsePush: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let statusCode: UInt8 // Status code
    public let data: Data // Additional status data

    public init(publicKeyPrefix: Data, statusCode: UInt8, data: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.statusCode = statusCode
        self.data = data
    }

    public static func decode(from data: Data) throws -> StatusResponsePush {
        guard data.count >= 8 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        let statusCode = data[6]
        let additionalData = data.count > 7 ? data.subdata(in: 7 ..< data.count) : Data()

        return StatusResponsePush(publicKeyPrefix: publicKeyPrefix, statusCode: statusCode, data: additionalData)
    }
}

/// Log RX data push notification (PUSH_LOG_RX_DATA = 0x88)
public struct LogRxDataPush: Sendable {
    public let snr: Int8 // Signal-to-noise ratio * 4
    public let rssi: Int8 // Received signal strength
    public let data: Data // Log data

    public init(snr: Int8, rssi: Int8, data: Data) {
        self.snr = snr
        self.rssi = rssi
        self.data = data
    }

    public static func decode(from data: Data) throws -> LogRxDataPush {
        guard data.count >= 3 else {
            throw ProtocolError.invalidPayload
        }

        let snr = Int8(bitPattern: data[0])
        let rssi = Int8(bitPattern: data[1])
        let logData = data.count > 2 ? data.subdata(in: 2 ..< data.count) : Data()

        return LogRxDataPush(snr: snr, rssi: rssi, data: logData)
    }

    /// Signal-to-noise ratio in dB
    public var snrDecibels: Double {
        Double(snr) / 4.0
    }
}

/// Trace data push notification (PUSH_TRACE_DATA = 0x89)
public struct TraceDataPush: Sendable {
    public let reserved: UInt8 // Reserved byte (always 0)
    public let pathLen: UInt8 // Path length
    public let flags: UInt8 // Trace flags
    public let tag: UInt32 // Trace tag
    public let authCode: UInt32 // Authentication code
    public let pathHashes: Data // Path hashes
    public let pathSnrs: Data // Path SNRs
    public let finalSnr: Int8 // Final SNR to this node

    public init(reserved: UInt8, pathLen: UInt8, flags: UInt8, tag: UInt32, authCode: UInt32,
                pathHashes: Data, pathSnrs: Data, finalSnr: Int8)
    {
        self.reserved = reserved
        self.pathLen = pathLen
        self.flags = flags
        self.tag = tag
        self.authCode = authCode
        self.pathHashes = pathHashes
        self.pathSnrs = pathSnrs
        self.finalSnr = finalSnr
    }

    public static func decode(from data: Data) throws -> TraceDataPush {
        guard data.count >= 12 else {
            throw ProtocolError.invalidPayload
        }

        let reserved = data[0]
        let pathLen = data[1]
        let flags = data[2]
        let tag = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 3, as: UInt32.self) }
        let authCode = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 7, as: UInt32.self) }

        guard data.count >= 12 + (2 * Int(pathLen)) else {
            throw ProtocolError.invalidPayload
        }

        let pathHashes = data.subdata(in: 11 ..< (11 + Int(pathLen)))
        let pathSnrs = data.subdata(in: (11 + Int(pathLen)) ..< (11 + 2 * Int(pathLen)))
        let finalSnr = Int8(bitPattern: data[11 + 2 * Int(pathLen)])

        return TraceDataPush(
            reserved: reserved,
            pathLen: pathLen,
            flags: flags,
            tag: tag,
            authCode: authCode,
            pathHashes: pathHashes,
            pathSnrs: pathSnrs,
            finalSnr: finalSnr,
        )
    }

    /// Final signal-to-noise ratio in dB
    public var finalSnrDecibels: Double {
        Double(finalSnr) / 4.0
    }
}

/// Binary response push notification (PUSH_BINARY_RESPONSE = 0x8C)
public struct BinaryResponsePush: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let tag: UInt32 // Request tag
    public let data: Data // Response data

    public init(publicKeyPrefix: Data, tag: UInt32, data: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.tag = tag
        self.data = data
    }

    public static func decode(from data: Data) throws -> BinaryResponsePush {
        guard data.count >= 11 else {
            throw ProtocolError.invalidPayload
        }

        let publicKeyPrefix = data.subdata(in: 0 ..< 6)
        _ = data[6]
        let tag = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 7, as: UInt32.self) }
        let responseData = data.count > 11 ? data.subdata(in: 11 ..< data.count) : Data()

        return BinaryResponsePush(publicKeyPrefix: publicKeyPrefix, tag: tag, data: responseData)
    }
}

/// Path discovery response push notification (PUSH_PATH_DISCOVERY_RESPONSE = 0x8D)
public struct PathDiscoveryResponsePush: Sendable {
    public let reserved: UInt8 // Reserved byte (always 0)
    public let publicKeyPrefix: Data // 6 bytes
    public let outPathLen: UInt8 // Outgoing path length
    public let outPath: Data // Outgoing path
    public let inPathLen: UInt8 // Incoming path length
    public let inPath: Data // Incoming path

    public init(reserved: UInt8, publicKeyPrefix: Data, outPathLen: UInt8,
                outPath: Data, inPathLen: UInt8, inPath: Data)
    {
        self.reserved = reserved
        self.publicKeyPrefix = publicKeyPrefix
        self.outPathLen = outPathLen
        self.outPath = outPath
        self.inPathLen = inPathLen
        self.inPath = inPath
    }

    public static func decode(from data: Data) throws -> PathDiscoveryResponsePush {
        guard data.count >= 9 else {
            throw ProtocolError.invalidPayload
        }

        let reserved = data[0]
        let publicKeyPrefix = data.subdata(in: 1 ..< 7)
        let outPathLen = data[7]

        guard data.count >= 8 + Int(outPathLen) + 1 else {
            throw ProtocolError.invalidPayload
        }

        let outPath = data.subdata(in: 8 ..< (8 + Int(outPathLen)))
        let inPathStart = 8 + Int(outPathLen)
        let inPathLen = data[inPathStart]

        guard data.count >= (inPathStart + 1 + Int(inPathLen)) else {
            throw ProtocolError.invalidPayload
        }

        let inPath = data.subdata(in: (inPathStart + 1) ..< (inPathStart + 1 + Int(inPathLen)))

        return PathDiscoveryResponsePush(
            reserved: reserved,
            publicKeyPrefix: publicKeyPrefix,
            outPathLen: outPathLen,
            outPath: outPath,
            inPathLen: inPathLen,
            inPath: inPath,
        )
    }
}

// MARK: - Push Code Extension

public extension PushCode {
    /// Human-readable name for the push code
    var name: String {
        switch self {
        case .advert: "Advertisement"
        case .pathUpdated: "Path Updated"
        case .sendConfirmed: "Send Confirmed"
        case .messageWaiting: "Message Waiting"
        case .rawData: "Raw Data"
        case .loginSuccess: "Login Success"
        case .loginFail: "Login Failed"
        case .statusResponse: "Status Response"
        case .logRxData: "Log RX Data"
        case .traceData: "Trace Data"
        case .newAdvert: "New Advertisement"
        case .telemetryResponse: "Telemetry Response"
        case .binaryResponse: "Binary Response"
        case .pathDiscoveryResponse: "Path Discovery Response"
        case .controlData: "Control Data"
        }
    }
}
