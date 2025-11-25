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
    case appStart = 1 // CMD_APP_START
    case sendTextMessage = 2 // CMD_SEND_TXT_MSG
    case sendChannelTextMessage = 3 // CMD_SEND_CHANNEL_TXT_MSG
    case getContacts = 4 // CMD_GET_CONTACTS
    case getDeviceTime = 5 // CMD_GET_DEVICE_TIME
    case setDeviceTime = 6 // CMD_SET_DEVICE_TIME
    case sendSelfAdvert = 7 // CMD_SEND_SELF_ADVERT
    case setAdvertName = 8 // CMD_SET_ADVERT_NAME
    case addUpdateContact = 9 // CMD_ADD_UPDATE_CONTACT
    case syncNextMessage = 10 // CMD_SYNC_NEXT_MESSAGE
    case setRadioParams = 11 // CMD_SET_RADIO_PARAMS
    case setRadioTxPower = 12 // CMD_SET_RADIO_TX_POWER
    case resetPath = 13 // CMD_RESET_PATH
    case setAdvertLatLon = 14 // CMD_SET_ADVERT_LATLON
    case removeContact = 15 // CMD_REMOVE_CONTACT
    case shareContact = 16 // CMD_SHARE_CONTACT
    case exportContact = 17 // CMD_EXPORT_CONTACT
    case importContact = 18 // CMD_IMPORT_CONTACT
    case reboot = 19 // CMD_REBOOT
    case getBatteryAndStorage = 20 // CMD_GET_BATT_AND_STORAGE
    case setTuningParams = 21 // CMD_SET_TUNING_PARAMS
    case deviceQuery = 22 // CMD_DEVICE_QEURY (note: typo in C++ name)

    // Security Commands:
    case exportPrivateKey = 23 // CMD_EXPORT_PRIVATE_KEY
    case importPrivateKey = 24 // CMD_IMPORT_PRIVATE_KEY

    // System Commands:
    case sendRawData = 25 // CMD_SEND_RAW_DATA
    case sendLogin = 26 // CMD_SEND_LOGIN
    case sendStatusReq = 27 // CMD_SEND_STATUS_REQ
    case hasConnection = 28 // CMD_HAS_CONNECTION
    case logout = 29 // CMD_LOGOUT

    // Contact and Channel Commands:
    case getContactByKey = 30 // CMD_GET_CONTACT_BY_KEY
    case getChannel = 31 // CMD_GET_CHANNEL
    case setChannel = 32 // CMD_SET_CHANNEL

    // Security Commands (continued):
    case signStart = 33 // CMD_SIGN_START
    case signData = 34 // CMD_SIGN_DATA
    case signFinish = 35 // CMD_SIGN_FINISH

    // Advanced Path and Trace Commands:
    case sendTracePath = 36 // CMD_SEND_TRACE_PATH
    case setDevicePin = 37 // CMD_SET_DEVICE_PIN
    case setOtherParams = 38 // CMD_SET_OTHER_PARAMS
    case sendTelemetryReq = 39 // CMD_SEND_TELEMETRY_REQ

    // Configuration Commands:
    case getCustomVars = 40 // CMD_GET_CUSTOM_VARS
    case setCustomVar = 41 // CMD_SET_CUSTOM_VAR
    case getAdvertPath = 42 // CMD_GET_ADVERT_PATH
    case getTuningParams = 43 // CMD_GET_TUNING_PARAMS

    // Advanced Features:
    case sendBinaryReq = 50 // CMD_SEND_BINARY_REQ
    case factoryReset = 51 // CMD_FACTORY_RESET
    case sendPathDiscoveryReq = 52 // CMD_SEND_PATH_DISCOVERY_REQ

    // Flood and Control Commands (v8+):
    case setFloodScope = 54 // CMD_SET_FLOOD_SCOPE
    case sendControlData = 55 // CMD_SEND_CONTROL_DATA
    case getMultiAcks = 56 // CMD_GET_MULTI_ACKS
    case getFloodScope = 57 // CMD_GET_FLOOD_SCOPE
    case sendPathDiscovery = 58 // CMD_SEND_PATH_DISCOVERY
    case sendTrace = 59 // CMD_SEND_TRACE
    case changeContactPath = 60 // CMD_CHANGE_CONTACT_PATH
    case requestTelemetry = 61 // CMD_REQUEST_TELEMETRY
    case requestStatus = 62 // CMD_REQUEST_STATUS
    case requestNeighbours = 63 // CMD_REQUEST_NEIGHBOURS
    case requestMMA = 64 // CMD_REQUEST_MMA
    case sendCommand = 65 // CMD_SEND_COMMAND
    case requestACL = 66 // CMD_REQUEST_ACL
}

public enum ResponseCode: UInt8, Sendable {
    case ok = 0 // RESP_CODE_OK
    case error = 1 // RESP_CODE_ERR
    case contactsStart = 2 // RESP_CODE_CONTACTS_START
    case contact = 3 // RESP_CODE_CONTACT
    case endOfContacts = 4 // RESP_CODE_END_OF_CONTACTS
    case selfInfo = 5 // RESP_CODE_SELF_INFO
    case sent = 6 // RESP_CODE_SENT
    case contactMessageReceived = 7 // RESP_CODE_CONTACT_MSG_RECV
    case channelMessageReceived = 8 // RESP_CODE_CHANNEL_MSG_RECV
    case currentTime = 9 // RESP_CODE_CURR_TIME
    case noMoreMessages = 10 // RESP_CODE_NO_MORE_MESSAGES
    case exportContact = 11 // RESP_CODE_EXPORT_CONTACT
    case batteryAndStorage = 12 // RESP_CODE_BATT_AND_STORAGE
    case deviceInfo = 13 // RESP_CODE_DEVICE_INFO
    case privateKey = 14 // RESP_CODE_PRIVATE_KEY
    case disabled = 15 // RESP_CODE_DISABLED
    case contactMessageReceivedV3 = 16 // RESP_CODE_CONTACT_MSG_RECV_V3
    case channelMessageReceivedV3 = 17 // RESP_CODE_CHANNEL_MSG_RECV_V3
    case channelInfo = 18 // RESP_CODE_CHANNEL_INFO
    case signStart = 19 // RESP_CODE_SIGN_START
    case signature = 20 // RESP_CODE_SIGNATURE
    case customVars = 21 // RESP_CODE_CUSTOM_VARS
    case advertPath = 22 // RESP_CODE_ADVERT_PATH
    case tuningParams = 23 // RESP_CODE_TUNING_PARAMS
    case multiAcksStatus = 24 // RESP_CODE_MULTI_ACKS_STATUS
    case floodScope = 25 // RESP_CODE_FLOOD_SCOPE
    case pathDiscoveryResponse = 26 // RESP_CODE_PATH_DISCOVERY_RESPONSE

    // Additional response codes from firmware (v8+)
    case loginSuccess = 0x85 // PUSH_CODE_LOGIN_SUCCESS (used as response in some contexts)
    case loginFail = 0x86 // PUSH_CODE_LOGIN_FAIL (used as response in some contexts)
    case statusResponse = 0x87 // PUSH_CODE_STATUS_RESPONSE (used as response in some contexts)
    case logRxData = 0x88 // PUSH_CODE_LOG_RX_DATA (used as response in some contexts)
    case traceData = 0x89 // PUSH_CODE_TRACE_DATA (used as response in some contexts)
    case newAdvert = 0x8A // PUSH_CODE_NEW_ADVERT (used as response in some contexts)
    case telemetryResponse = 0x8B // PUSH_CODE_TELEMETRY_RESPONSE (used as response in some contexts)
    case binaryResponse = 0x8C // PUSH_CODE_BINARY_RESPONSE (used as response in some contexts)
    case pathDiscoveryResponsePush = 0x8D // PUSH_CODE_PATH_DISCOVERY_RESPONSE (used as response in some contexts)
    case controlData = 0x8E // PUSH_CODE_CONTROL_DATA (used as response in some contexts)
}

public enum PushCode: UInt8, Sendable {
    case advert = 0x80 // PUSH_CODE_ADVERT
    case pathUpdated = 0x81 // PUSH_CODE_PATH_UPDATED
    case sendConfirmed = 0x82 // PUSH_CODE_SEND_CONFIRMED
    case messageWaiting = 0x83 // PUSH_CODE_MSG_WAITING
    case rawData = 0x84 // PUSH_CODE_RAW_DATA
    case loginSuccess = 0x85 // PUSH_CODE_LOGIN_SUCCESS
    case loginFail = 0x86 // PUSH_CODE_LOGIN_FAIL
    case statusResponse = 0x87 // PUSH_CODE_STATUS_RESPONSE
    case logRxData = 0x88 // PUSH_CODE_LOG_RX_DATA
    case traceData = 0x89 // PUSH_CODE_TRACE_DATA
    case newAdvert = 0x8A // PUSH_CODE_NEW_ADVERT
    case telemetryResponse = 0x8B // PUSH_CODE_TELEMETRY_RESPONSE
    case binaryResponse = 0x8C // PUSH_CODE_BINARY_RESPONSE
    case pathDiscoveryResponse = 0x8D // PUSH_CODE_PATH_DISCOVERY_RESPONSE
    case controlData = 0x8E // PUSH_CODE_CONTROL_DATA (v8+)
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
