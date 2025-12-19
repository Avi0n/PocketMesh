/// Command codes sent TO the device
public enum CommandCode: UInt8, Sendable {
    case appStart = 0x01
    case sendMessage = 0x02
    case sendChannelMessage = 0x03
    case getContacts = 0x04
    case getTime = 0x05
    case setTime = 0x06
    case sendAdvertisement = 0x07
    case setName = 0x08
    case updateContact = 0x09
    case getMessage = 0x0A
    case setRadio = 0x0B
    case setTxPower = 0x0C
    case resetPath = 0x0D
    case setCoordinates = 0x0E
    case removeContact = 0x0F
    case shareContact = 0x10
    case exportContact = 0x11
    case importContact = 0x12
    case reboot = 0x13
    case getBattery = 0x14
    case setTuning = 0x15
    case deviceQuery = 0x16
    case exportPrivateKey = 0x17
    case importPrivateKey = 0x18
    case sendLogin = 0x1A
    case sendStatusRequest = 0x1B
    case sendLogout = 0x1D
    case getChannel = 0x1F
    case setChannel = 0x20
    case signStart = 0x21
    case signData = 0x22
    case signFinish = 0x23
    case sendTrace = 0x24
    case setDevicePin = 0x25
    case setOtherParams = 0x26
    case getSelfTelemetry = 0x27
    case getCustomVars = 0x28
    case setCustomVar = 0x29
    case binaryRequest = 0x32
    case factoryReset = 0x33
    case pathDiscovery = 0x34
    case setFloodScope = 0x36
    case sendControlData = 0x37
    case getStats = 0x38
}

/// Response codes received FROM the device
public enum ResponseCode: UInt8, Sendable {
    case ok = 0x00
    case error = 0x01
    case contactStart = 0x02
    case contact = 0x03
    case contactEnd = 0x04
    case selfInfo = 0x05
    case messageSent = 0x06
    case contactMessageReceived = 0x07
    case channelMessageReceived = 0x08
    case currentTime = 0x09
    case noMoreMessages = 0x0A
    case contactURI = 0x0B
    case battery = 0x0C
    case deviceInfo = 0x0D
    case privateKey = 0x0E
    case disabled = 0x0F
    case contactMessageReceivedV3 = 0x10
    case channelMessageReceivedV3 = 0x11
    case channelInfo = 0x12
    case signStart = 0x13
    case signature = 0x14
    case customVars = 0x15
    case stats = 0x18  // Sub-type in data[1]: 0x00=core, 0x01=radio, 0x02=packets

    // Push notifications (0x80+)
    case advertisement = 0x80
    case pathUpdate = 0x81
    case ack = 0x82
    case messagesWaiting = 0x83
    case rawData = 0x84
    case loginSuccess = 0x85
    case loginFailed = 0x86
    case statusResponse = 0x87
    case logData = 0x88
    case traceData = 0x89
    case newAdvertisement = 0x8A
    case telemetryResponse = 0x8B
    case binaryResponse = 0x8C
    case pathDiscoveryResponse = 0x8D
    case controlData = 0x8E
}

/// Binary request types for async operations
public enum BinaryRequestType: UInt8, Sendable {
    case status = 0x01
    case keepAlive = 0x02
    case telemetry = 0x03
    case mma = 0x04
    case acl = 0x05
    case neighbours = 0x06
}

/// Control data types
public enum ControlType: UInt8, Sendable {
    case nodeDiscoverRequest = 0x80
    case nodeDiscoverResponse = 0x90
}

/// Stats types
public enum StatsType: UInt8, Sendable {
    case core = 0x00
    case radio = 0x01
    case packets = 0x02
}

/// Text/message type encoding (per protocol docs)
public enum TextType: UInt8, Sendable {
    case plainText = 0x00
    case binary = 0x01
    case signed = 0x02
}

// MARK: - Response Categories

/// Response categories for routing to domain-specific parsers
public enum ResponseCategory: Sendable {
    case simple          // ok, error
    case device          // selfInfo, deviceInfo, battery, currentTime, privateKey, disabled
    case contact         // contactStart, contact, contactEnd, contactURI
    case message         // msgSent, contactMsgRecv, channelMsgRecv, noMoreMsgs
    case push            // advertisement, pathUpdate, ack, messagesWaiting, statusResponse, etc.
    case login           // loginSuccess, loginFailed
    case signing         // signStart, signature
    case misc            // stats, customVars, channelInfo, rawData, logData, traceData
}

extension ResponseCode {
    /// Category for routing to domain-specific parser
    public var category: ResponseCategory {
        switch self {
        case .ok, .error:
            return .simple
        case .selfInfo, .deviceInfo, .battery, .currentTime, .privateKey, .disabled:
            return .device
        case .contactStart, .contact, .contactEnd, .contactURI:
            return .contact
        case .messageSent, .contactMessageReceived, .contactMessageReceivedV3,
             .channelMessageReceived, .channelMessageReceivedV3, .noMoreMessages:
            return .message
        case .advertisement, .pathUpdate, .ack, .messagesWaiting, .newAdvertisement,
             .statusResponse, .telemetryResponse, .binaryResponse, .pathDiscoveryResponse, .controlData:
            return .push
        case .loginSuccess, .loginFailed:
            return .login
        case .signStart, .signature:
            return .signing
        case .stats, .customVars, .channelInfo, .rawData, .logData, .traceData:
            return .misc
        }
    }
}
