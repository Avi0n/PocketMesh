import Foundation

// MARK: - Sendable Frame Types

public struct DeviceInfo: Sendable, Equatable {
    public let firmwareVersion: UInt8
    public let maxContacts: UInt8
    public let maxChannels: UInt8
    public let blePin: UInt32
    public let buildDate: String
    public let manufacturerName: String
    public let firmwareVersionString: String

    public init(
        firmwareVersion: UInt8,
        maxContacts: UInt8,
        maxChannels: UInt8,
        blePin: UInt32,
        buildDate: String,
        manufacturerName: String,
        firmwareVersionString: String
    ) {
        self.firmwareVersion = firmwareVersion
        self.maxContacts = maxContacts
        self.maxChannels = maxChannels
        self.blePin = blePin
        self.buildDate = buildDate
        self.manufacturerName = manufacturerName
        self.firmwareVersionString = firmwareVersionString
    }
}

public struct SelfInfo: Sendable, Equatable {
    public let nodeType: UInt8
    public let txPower: UInt8
    public let maxTxPower: UInt8
    public let publicKey: Data
    public let latitude: Double
    public let longitude: Double
    public let multiAcks: UInt8
    public let advertLocationPolicy: AdvertLocationPolicy
    public let telemetryModes: UInt8
    public let manualAddContacts: UInt8
    public let frequency: UInt32
    public let bandwidth: UInt32
    public let spreadingFactor: UInt8
    public let codingRate: UInt8
    public let nodeName: String

    public init(
        nodeType: UInt8,
        txPower: UInt8,
        maxTxPower: UInt8,
        publicKey: Data,
        latitude: Double,
        longitude: Double,
        multiAcks: UInt8,
        advertLocationPolicy: AdvertLocationPolicy,
        telemetryModes: UInt8,
        manualAddContacts: UInt8,
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
        nodeName: String
    ) {
        self.nodeType = nodeType
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.publicKey = publicKey
        self.latitude = latitude
        self.longitude = longitude
        self.multiAcks = multiAcks
        self.advertLocationPolicy = advertLocationPolicy
        self.telemetryModes = telemetryModes
        self.manualAddContacts = manualAddContacts
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.nodeName = nodeName
    }
}

public struct ContactFrame: Sendable, Equatable {
    public let publicKey: Data
    public let type: ContactType
    public let flags: UInt8
    public let outPathLength: Int8
    public let outPath: Data
    public let name: String
    public let lastAdvertTimestamp: UInt32
    public let latitude: Double
    public let longitude: Double
    public let lastModified: UInt32

    public init(
        publicKey: Data,
        type: ContactType,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        name: String,
        lastAdvertTimestamp: UInt32,
        latitude: Double,
        longitude: Double,
        lastModified: UInt32
    ) {
        self.publicKey = publicKey
        self.type = type
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.name = name
        self.lastAdvertTimestamp = lastAdvertTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
    }
}

public struct MessageFrame: Sendable, Equatable {
    public let senderPublicKeyPrefix: Data
    public let pathLength: UInt8
    public let textType: TextType
    public let timestamp: UInt32
    public let text: String
    public let snr: Int8?
    public let extraData: Data?

    public init(
        senderPublicKeyPrefix: Data,
        pathLength: UInt8,
        textType: TextType,
        timestamp: UInt32,
        text: String,
        snr: Int8? = nil,
        extraData: Data? = nil
    ) {
        self.senderPublicKeyPrefix = senderPublicKeyPrefix
        self.pathLength = pathLength
        self.textType = textType
        self.timestamp = timestamp
        self.text = text
        self.snr = snr
        self.extraData = extraData
    }
}

public struct ChannelMessageFrame: Sendable, Equatable {
    public let channelIndex: UInt8
    public let pathLength: UInt8
    public let textType: TextType
    public let timestamp: UInt32
    public let text: String
    public let snr: Int8?
    public let senderNodeName: String?  // NEW: Parsed from "NodeName: MessageText" format

    public init(
        channelIndex: UInt8,
        pathLength: UInt8,
        textType: TextType,
        timestamp: UInt32,
        text: String,
        snr: Int8? = nil,
        senderNodeName: String? = nil  // NEW
    ) {
        self.channelIndex = channelIndex
        self.pathLength = pathLength
        self.textType = textType
        self.timestamp = timestamp
        self.text = text
        self.snr = snr
        self.senderNodeName = senderNodeName
    }
}

public struct SentResponse: Sendable, Equatable {
    public let isFlood: Bool
    public let ackCode: UInt32
    public let estimatedTimeout: UInt32

    public init(isFlood: Bool, ackCode: UInt32, estimatedTimeout: UInt32) {
        self.isFlood = isFlood
        self.ackCode = ackCode
        self.estimatedTimeout = estimatedTimeout
    }
}

public struct BatteryAndStorage: Sendable, Equatable {
    public let batteryMillivolts: UInt16
    public let storageUsedKB: UInt32
    public let storageTotalKB: UInt32

    public init(batteryMillivolts: UInt16, storageUsedKB: UInt32, storageTotalKB: UInt32) {
        self.batteryMillivolts = batteryMillivolts
        self.storageUsedKB = storageUsedKB
        self.storageTotalKB = storageTotalKB
    }
}

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

public struct SendConfirmation: Sendable, Equatable {
    public let ackCode: UInt32
    public let roundTripTime: UInt32

    public init(ackCode: UInt32, roundTripTime: UInt32) {
        self.ackCode = ackCode
        self.roundTripTime = roundTripTime
    }
}

public struct LoginResult: Sendable, Equatable {
    public let success: Bool
    public let isAdmin: Bool
    public let publicKeyPrefix: Data
    public let serverTimestamp: UInt32?
    public let aclPermissions: UInt8?
    public let firmwareLevel: UInt8?

    public init(
        success: Bool,
        isAdmin: Bool,
        publicKeyPrefix: Data,
        serverTimestamp: UInt32? = nil,
        aclPermissions: UInt8? = nil,
        firmwareLevel: UInt8? = nil
    ) {
        self.success = success
        self.isAdmin = isAdmin
        self.publicKeyPrefix = publicKeyPrefix
        self.serverTimestamp = serverTimestamp
        self.aclPermissions = aclPermissions
        self.firmwareLevel = firmwareLevel
    }
}

public struct CoreStats: Sendable, Equatable {
    public let batteryMillivolts: UInt16
    public let uptimeSeconds: UInt32
    public let errorFlags: UInt16
    public let queueLength: UInt8

    public init(batteryMillivolts: UInt16, uptimeSeconds: UInt32, errorFlags: UInt16, queueLength: UInt8) {
        self.batteryMillivolts = batteryMillivolts
        self.uptimeSeconds = uptimeSeconds
        self.errorFlags = errorFlags
        self.queueLength = queueLength
    }
}

public struct RadioStats: Sendable, Equatable {
    public let noiseFloor: Int16
    public let lastRSSI: Int8
    public let lastSNR: Int8
    public let txAirSeconds: UInt32
    public let rxAirSeconds: UInt32

    public init(noiseFloor: Int16, lastRSSI: Int8, lastSNR: Int8, txAirSeconds: UInt32, rxAirSeconds: UInt32) {
        self.noiseFloor = noiseFloor
        self.lastRSSI = lastRSSI
        self.lastSNR = lastSNR
        self.txAirSeconds = txAirSeconds
        self.rxAirSeconds = rxAirSeconds
    }
}

public struct PacketStats: Sendable, Equatable {
    public let packetsReceived: UInt32
    public let packetsSent: UInt32
    public let floodSent: UInt32
    public let directSent: UInt32
    public let floodReceived: UInt32
    public let directReceived: UInt32

    public init(
        packetsReceived: UInt32,
        packetsSent: UInt32,
        floodSent: UInt32,
        directSent: UInt32,
        floodReceived: UInt32,
        directReceived: UInt32
    ) {
        self.packetsReceived = packetsReceived
        self.packetsSent = packetsSent
        self.floodSent = floodSent
        self.directSent = directSent
        self.floodReceived = floodReceived
        self.directReceived = directReceived
    }
}

public struct TuningParams: Sendable, Equatable {
    public let rxDelayBase: Float
    public let airtimeFactor: Float

    public init(rxDelayBase: Float, airtimeFactor: Float) {
        self.rxDelayBase = rxDelayBase
        self.airtimeFactor = airtimeFactor
    }
}

// MARK: - Binary Protocol Frames

/// Remote node status from binary protocol request
public struct RemoteNodeStatus: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let batteryMillivolts: UInt16
    public let txQueueLength: UInt16
    public let noiseFloor: Int16
    public let lastRssi: Int16
    public let packetsReceived: UInt32
    public let packetsSent: UInt32
    public let airtimeSeconds: UInt32
    public let uptimeSeconds: UInt32
    public let sentFlood: UInt32
    public let sentDirect: UInt32
    public let receivedFlood: UInt32
    public let receivedDirect: UInt32
    public let fullEvents: UInt16
    public let lastSnr: Float  // Stored as Int16 * 4 in protocol
    public let directDuplicates: UInt16
    public let floodDuplicates: UInt16
    public let rxAirtimeSeconds: UInt32

    public init(
        publicKeyPrefix: Data,
        batteryMillivolts: UInt16,
        txQueueLength: UInt16,
        noiseFloor: Int16,
        lastRssi: Int16,
        packetsReceived: UInt32,
        packetsSent: UInt32,
        airtimeSeconds: UInt32,
        uptimeSeconds: UInt32,
        sentFlood: UInt32,
        sentDirect: UInt32,
        receivedFlood: UInt32,
        receivedDirect: UInt32,
        fullEvents: UInt16,
        lastSnr: Float,
        directDuplicates: UInt16,
        floodDuplicates: UInt16,
        rxAirtimeSeconds: UInt32
    ) {
        self.publicKeyPrefix = publicKeyPrefix
        self.batteryMillivolts = batteryMillivolts
        self.txQueueLength = txQueueLength
        self.noiseFloor = noiseFloor
        self.lastRssi = lastRssi
        self.packetsReceived = packetsReceived
        self.packetsSent = packetsSent
        self.airtimeSeconds = airtimeSeconds
        self.uptimeSeconds = uptimeSeconds
        self.sentFlood = sentFlood
        self.sentDirect = sentDirect
        self.receivedFlood = receivedFlood
        self.receivedDirect = receivedDirect
        self.fullEvents = fullEvents
        self.lastSnr = lastSnr
        self.directDuplicates = directDuplicates
        self.floodDuplicates = floodDuplicates
        self.rxAirtimeSeconds = rxAirtimeSeconds
    }
}

// MARK: - RemoteNodeStatus Role-Specific Interpretation

extension RemoteNodeStatus {
    /// Room server interpretation: total posts stored on the server
    /// Bytes 48-49 of the status response (little-endian UInt16)
    ///
    /// Note: The underlying `rxAirtimeSeconds` is decoded as little-endian UInt32 by
    /// `decodeRemoteNodeStatus()`. This property extracts the low 16 bits, which
    /// corresponds to bytes 48-49 of the original frame in little-endian order.
    public var roomPostsCount: UInt16 {
        UInt16(truncatingIfNeeded: rxAirtimeSeconds & 0xFFFF)
    }

    /// Room server interpretation: total posts pushed to clients
    /// Bytes 50-51 of the status response (little-endian UInt16)
    ///
    /// Note: Extracts the high 16 bits of `rxAirtimeSeconds`, corresponding to
    /// bytes 50-51 of the original frame in little-endian order.
    public var roomPostPushCount: UInt16 {
        UInt16(truncatingIfNeeded: (rxAirtimeSeconds >> 16) & 0xFFFF)
    }

    /// Repeater interpretation: total receive airtime in seconds
    /// This is the default interpretation (bytes 48-51 as little-endian UInt32)
    public var repeaterRxAirtimeSeconds: UInt32 {
        rxAirtimeSeconds
    }
}

/// Neighbor information from binary protocol request
public struct NeighbourInfo: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let secondsAgo: Int32
    public let snr: Float

    public init(publicKeyPrefix: Data, secondsAgo: Int32, snr: Float) {
        self.publicKeyPrefix = publicKeyPrefix
        self.secondsAgo = secondsAgo
        self.snr = snr
    }
}

/// Neighbours response from binary protocol
public struct NeighboursResponse: Sendable, Equatable {
    public let tag: Data
    public let totalCount: Int16
    public let resultsCount: Int16
    public let neighbours: [NeighbourInfo]

    public init(tag: Data, totalCount: Int16, resultsCount: Int16, neighbours: [NeighbourInfo]) {
        self.tag = tag
        self.totalCount = totalCount
        self.resultsCount = resultsCount
        self.neighbours = neighbours
    }
}

/// Binary response with raw data and optional parsed content
public struct BinaryResponse: Sendable, Equatable {
    public let tag: Data
    public let rawData: Data

    public init(tag: Data, rawData: Data) {
        self.tag = tag
        self.rawData = rawData
    }
}

// MARK: - Telemetry Frames

/// Telemetry response containing LPP sensor data
public struct TelemetryResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let dataPoints: [LPPDataPoint]

    public init(publicKeyPrefix: Data, dataPoints: [LPPDataPoint]) {
        self.publicKeyPrefix = publicKeyPrefix
        self.dataPoints = dataPoints
    }
}

// MARK: - Advert Path Frames

/// Response from querying cached advertisement path
public struct AdvertPathResponse: Sendable, Equatable {
    /// Timestamp when this path was learned from an advertisement
    public let timestamp: UInt32
    /// Path length (0 = direct, >0 = via repeaters)
    public let pathLength: UInt8
    /// Path data (repeater hash bytes)
    public let path: Data

    public init(timestamp: UInt32, pathLength: UInt8, path: Data) {
        self.timestamp = timestamp
        self.pathLength = pathLength
        self.path = path
    }
}

// MARK: - Path Discovery Frames

/// Path discovery response containing outbound and inbound paths
public struct PathDiscoveryResponse: Sendable, Equatable {
    public let publicKeyPrefix: Data
    public let outboundPath: Data
    public let inboundPath: Data

    public init(publicKeyPrefix: Data, outboundPath: Data, inboundPath: Data) {
        self.publicKeyPrefix = publicKeyPrefix
        self.outboundPath = outboundPath
        self.inboundPath = inboundPath
    }
}

// MARK: - Trace Frames

/// A single node in a trace path with its hash byte and SNR
public struct TracePathNode: Sendable, Equatable {
    public let hashByte: UInt8
    public let snr: Float

    public init(hashByte: UInt8, snr: Float) {
        self.hashByte = hashByte
        self.snr = snr
    }
}

/// Trace data response containing path diagnostics
public struct TraceData: Sendable, Equatable {
    public let tag: UInt32
    public let authCode: UInt32
    public let flags: UInt8
    public let path: [TracePathNode]
    public let finalSnr: Float

    public init(tag: UInt32, authCode: UInt32, flags: UInt8, path: [TracePathNode], finalSnr: Float) {
        self.tag = tag
        self.authCode = authCode
        self.flags = flags
        self.path = path
        self.finalSnr = finalSnr
    }
}

// MARK: - Control Data Frames

/// Control data packet received from mesh network
public struct ControlDataPacket: Sendable, Equatable {
    public let snr: Float
    public let rssi: Int8
    public let pathLength: UInt8
    public let payloadType: UInt8
    public let payload: Data

    public init(snr: Float, rssi: Int8, pathLength: UInt8, payloadType: UInt8, payload: Data) {
        self.snr = snr
        self.rssi = rssi
        self.pathLength = pathLength
        self.payloadType = payloadType
        self.payload = payload
    }
}

/// Node discovery response from control data protocol
public struct NodeDiscoverResponse: Sendable, Equatable {
    public let snr: Float
    public let rssi: Int8
    public let pathLength: UInt8
    public let nodeType: UInt8
    public let snrIn: Float
    public let tag: Data
    public let publicKey: Data

    public init(
        snr: Float,
        rssi: Int8,
        pathLength: UInt8,
        nodeType: UInt8,
        snrIn: Float,
        tag: Data,
        publicKey: Data
    ) {
        self.snr = snr
        self.rssi = rssi
        self.pathLength = pathLength
        self.nodeType = nodeType
        self.snrIn = snrIn
        self.tag = tag
        self.publicKey = publicKey
    }
}
