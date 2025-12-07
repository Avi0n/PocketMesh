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
    public let latitude: Float
    public let longitude: Float
    public let lastModified: UInt32

    public init(
        publicKey: Data,
        type: ContactType,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        name: String,
        lastAdvertTimestamp: UInt32,
        latitude: Float,
        longitude: Float,
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

    public init(
        channelIndex: UInt8,
        pathLength: UInt8,
        textType: TextType,
        timestamp: UInt32,
        text: String,
        snr: Int8? = nil
    ) {
        self.channelIndex = channelIndex
        self.pathLength = pathLength
        self.textType = textType
        self.timestamp = timestamp
        self.text = text
        self.snr = snr
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
