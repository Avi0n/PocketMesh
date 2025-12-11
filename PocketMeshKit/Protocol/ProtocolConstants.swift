import Foundation

// MARK: - BLE Service UUIDs

public enum BLEServiceUUID {
    public static let nordicUART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let txCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let rxCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

// MARK: - Command Codes (Client → Device)

public enum CommandCode: UInt8, Sendable {
    case appStart = 0x01
    case sendTextMessage = 0x02
    case sendChannelTextMessage = 0x03
    case getContacts = 0x04
    case getDeviceTime = 0x05
    case setDeviceTime = 0x06
    case sendSelfAdvert = 0x07
    case setAdvertName = 0x08
    case addUpdateContact = 0x09
    case syncNextMessage = 0x0A
    case setRadioParams = 0x0B
    case setRadioTxPower = 0x0C
    case resetPath = 0x0D
    case setAdvertLatLon = 0x0E
    case removeContact = 0x0F
    case shareContact = 0x10
    case exportContact = 0x11
    case importContact = 0x12
    case reboot = 0x13
    case getBatteryAndStorage = 0x14
    case setTuningParams = 0x15
    case deviceQuery = 0x16
    case exportPrivateKey = 0x17
    case importPrivateKey = 0x18
    case sendRawData = 0x19
    case sendLogin = 0x1A
    case sendStatusRequest = 0x1B
    case hasConnection = 0x1C
    case logout = 0x1D
    case getContactByKey = 0x1E
    case getChannel = 0x1F
    case setChannel = 0x20
    case signStart = 0x21
    case signData = 0x22
    case signFinish = 0x23
    case sendTracePath = 0x24
    case setDevicePin = 0x25
    case setOtherParams = 0x26
    case sendTelemetryRequest = 0x27
    case getCustomVars = 0x28
    case setCustomVar = 0x29
    case getAdvertPath = 0x2A
    case getTuningParams = 0x2B
    case sendBinaryRequest = 0x32
    case factoryReset = 0x33
    case sendPathDiscoveryRequest = 0x34
    case setFloodScope = 0x36
    case sendControlData = 0x37
    case getStats = 0x38
}

// MARK: - Response Codes (Device → Client)

public enum ResponseCode: UInt8, Sendable {
    case ok = 0x00
    case error = 0x01
    case contactsStart = 0x02
    case contact = 0x03
    case endOfContacts = 0x04
    case selfInfo = 0x05
    case sent = 0x06
    case contactMessageReceived = 0x07
    case channelMessageReceived = 0x08
    case currentTime = 0x09
    case noMoreMessages = 0x0A
    case exportContact = 0x0B
    case batteryAndStorage = 0x0C
    case deviceInfo = 0x0D
    case privateKey = 0x0E
    case disabled = 0x0F
    case contactMessageReceivedV3 = 0x10
    case channelMessageReceivedV3 = 0x11
    case channelInfo = 0x12
    case signStart = 0x13
    case signature = 0x14
    case customVars = 0x15
    case advertPath = 0x16
    case tuningParams = 0x17
    case stats = 0x18
    case hasConnection = 0x19
}

// MARK: - Push Codes (Device → Client, Unsolicited)

public enum PushCode: UInt8, Sendable {
    case advert = 0x80
    case pathUpdated = 0x81
    case sendConfirmed = 0x82
    case messageWaiting = 0x83
    case rawData = 0x84
    case loginSuccess = 0x85
    case loginFail = 0x86
    case statusResponse = 0x87
    case logRxData = 0x88
    case traceData = 0x89
    case newAdvert = 0x8A
    case telemetryResponse = 0x8B
    case binaryResponse = 0x8C
    case pathDiscoveryResponse = 0x8D
    case controlData = 0x8E
}

// MARK: - Error Codes

public enum ProtocolError: UInt8, Sendable, Error {
    case unsupportedCommand = 0x01
    case notFound = 0x02
    case tableFull = 0x03
    case badState = 0x04
    case fileIOError = 0x05
    case illegalArgument = 0x06
}

// MARK: - Protocol Limits

public enum ProtocolLimits {
    public static let publicKeySize = 32
    public static let maxPathSize = 64
    public static let maxFrameSize = 250
    public static let signatureSize = 64
    public static let maxContacts = 100
    public static let maxChannels = 8
    public static let offlineQueueSize = 16
    public static let maxNameLength = 32
    public static let channelSecretSize = 16
    public static let maxMessageLength = 160

    /// Maximum characters for direct messages (app-enforced limit per MeshCore spec)
    public static let maxDirectMessageLength = 150

    /// Calculate max channel message length based on node name
    /// Formula: 160 - nodeNameLength - 2
    public static func maxChannelMessageLength(nodeNameLength: Int) -> Int {
        max(0, 160 - nodeNameLength - 2)
    }
}

// MARK: - Contact Types

public enum ContactType: UInt8, Sendable, Codable {
    case chat = 0x01
    case repeater = 0x02
    case room = 0x03
}

// MARK: - Text Types

public enum TextType: UInt8, Sendable {
    case plain = 0x00
    case cliData = 0x01
    case signedPlain = 0x02
}

// MARK: - Stats Types

public enum StatsType: UInt8, Sendable {
    case core = 0x00
    case radio = 0x01
    case packets = 0x02
}

// MARK: - Telemetry Modes

public enum TelemetryMode: UInt8, Sendable, Codable {
    case deny = 0
    case allowFlags = 1
    case allowAll = 2
}

// MARK: - Advert Location Policy

public enum AdvertLocationPolicy: UInt8, Sendable, Codable {
    case none = 0
    case share = 1
}

// MARK: - Binary Request Types

/// Binary request types for querying remote nodes
public enum BinaryRequestType: UInt8, Sendable {
    case status = 0x01
    case keepAlive = 0x02
    case telemetry = 0x03
    case mma = 0x04  // Min/Max/Avg historical data
    case acl = 0x05  // Access Control List
    case neighbours = 0x06
}

// MARK: - Control Data Types

/// Control data message types for node discovery
public enum ControlDataType: UInt8, Sendable {
    case nodeDiscoverRequest = 0x80
    case nodeDiscoverResponse = 0x90
}
