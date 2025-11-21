import Foundation

/// Represents a MeshCore protocol frame (command or response)
public struct ProtocolFrame: Sendable {
    let code: UInt8
    let payload: Data

    public init(code: UInt8, payload: Data = Data()) {
        self.code = code
        self.payload = payload
    }

    /// Encode frame for BLE transmission
    func encode() -> Data {
        var data = Data()
        data.append(code)
        data.append(payload)
        return data
    }

    /// Decode frame from BLE characteristic value
    static func decode(_ data: Data) throws -> ProtocolFrame {
        guard !data.isEmpty else {
            throw ProtocolError.invalidFrame
        }

        let code = data[0]
        let payload = data.count > 1 ? data.subdata(in: 1 ..< data.count) : Data()

        return ProtocolFrame(code: code, payload: payload)
    }
}

// MARK: - Protocol Constants

public enum CommandCode: UInt8, Sendable {
    case appStart = 1
    case sendTextMessage = 2
    case sendChannelTextMessage = 3
    case getContacts = 4
    case getDeviceTime = 5
    case setDeviceTime = 6
    case sendSelfAdvert = 7
    case setAdvertName = 8
    case addUpdateContact = 9
    case syncNextMessage = 10
    case setRadioParams = 11
    case setRadioTxPower = 12
    case resetPath = 13
    case setAdvertLatLon = 14
    case removeContact = 15
    case shareContact = 16
    case exportContact = 17
    case importContact = 18
    case reboot = 19
    case getBatteryAndStorage = 20
    case setTuningParams = 21
    case deviceQuery = 22
    case exportPrivateKey = 23 // CMD_EXPORT_PRIVATE_KEY
    case getMultiAcks = 24 // CMD_GET_MULTI_ACKS
    case setFloodScope = 25 // CMD_SET_FLOOD_SCOPE
    case getFloodScope = 26 // CMD_GET_FLOOD_SCOPE
    case requestStatus = 27 // CMD_REQ_STATUS (send_statusreq - 0x1b)
    case changeContactPath = 28 // CMD_CHANGE_CONTACT_PATH
    case sendCommand = 29 // CMD_SEND_CMD (generic command to repeater/sensor)
    case getChannel = 31 // CMD_GET_CHANNEL (get_channel - 0x1f)
    case setChannel = 32 // CMD_SET_CHANNEL (set_channel - 0x20)
    case requestTelemetry = 33 // CMD_REQ_TELEMETRY (binary req)
    case requestNeighbours = 34 // CMD_REQ_NEIGHBOURS (binary req)
    case requestMMA = 35 // CMD_REQ_MMA (binary req)
    case requestACL = 36 // CMD_REQ_ACL (binary req)
    case sendNodeDiscovery = 37 // CMD_SEND_NODE_DISCOVER_REQ
    case setOtherParams = 38 // CMD_SET_OTHER_PARAMS (0x26)
    case sendTrace = 39 // CMD_SEND_TRACE (0x27)
    case sendPathDiscovery = 52 // CMD_SEND_PATH_DISCOVERY (0x34)
    case getCustomVars = 40 // CMD_GET_CUSTOM_VARS
    case setCustomVar = 41 // CMD_SET_CUSTOM_VAR
    // ... additional commands as needed
}

public enum ResponseCode: UInt8, Sendable {
    case ok = 0
    case error = 1
    case contactsStart = 2
    case contact = 3
    case endOfContacts = 4
    case selfInfo = 5
    case sent = 6
    case contactMessageReceived = 7
    case channelMessageReceived = 8
    case currentTime = 9
    case noMoreMessages = 10
    case exportContact = 11
    case batteryAndStorage = 12
    case deviceInfo = 13
    case privateKey = 14 // RESPONSE_PRIVATE_KEY
    case disabled = 15 // RESPONSE_DISABLED
    case contactMessageReceivedV3 = 16
    case channelMessageReceivedV3 = 17
    case channelInfo = 18 // RESP_CODE_CHANNEL_INFO - Fixed to match Python: PacketType.CHANNEL_INFO = 18
    case multiAcksStatus = 19 // RESP_CODE_MULTI_ACKS_STATUS
    case floodScope = 20 // RESP_CODE_FLOOD_SCOPE
    case pathDiscoveryResponse = 21 // RESP_PATH_DISCOVERY
    case customVars = 22 // RESPONSE_CUSTOM_VARS
    // ... additional response codes
}

public enum PushCode: UInt8, Sendable {
    case advert = 0x80
    case pathUpdated = 0x81
    case sendConfirmed = 0x82
    case messageWaiting = 0x83
    case rawData = 0x84
    case loginSuccess = 0x85
    case loginFail = 0x86
    case statusResponse = 0x87
    case traceData = 0x89
    case newAdvert = 0x8A
    case telemetryResponse = 0x8B
    case binaryResponse = 0x8C
    case discoveryResponse = 0x8D // PUSH_DISCOVERY_RESPONSE
    case neighboursResponse = 0x8E // PUSH_NEIGHBOURS_RESPONSE
    case controlData = 0x8F // PUSH_CONTROL_DATA
}

public enum ProtocolError: LocalizedError, Equatable {
    case invalidFrame
    case unsupportedCommand
    case invalidPayload
    case deviceError(code: UInt8)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidFrame: "Invalid protocol frame"
        case .unsupportedCommand: "Unsupported command"
        case .invalidPayload: "Invalid payload data"
        case let .deviceError(code): "Device error code: \(code)"
        case .timeout: "Operation timed out"
        }
    }
}
