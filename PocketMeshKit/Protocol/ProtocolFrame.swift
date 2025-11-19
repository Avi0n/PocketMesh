import Foundation

/// Represents a MeshCore protocol frame (command or response)
public struct ProtocolFrame {
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
        let payload = data.count > 1 ? data.subdata(in: 1..<data.count) : Data()

        return ProtocolFrame(code: code, payload: payload)
    }
}

// MARK: - Protocol Constants

public enum CommandCode: UInt8 {
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
    // ... additional commands as needed
}

public enum ResponseCode: UInt8 {
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
    case contactMessageReceivedV3 = 16
    case channelMessageReceivedV3 = 17
    // ... additional response codes
}

public enum PushCode: UInt8 {
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
}

public enum ProtocolError: LocalizedError {
    case invalidFrame
    case unsupportedCommand
    case invalidPayload
    case deviceError(code: UInt8)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidFrame: return "Invalid protocol frame"
        case .unsupportedCommand: return "Unsupported command"
        case .invalidPayload: return "Invalid payload data"
        case .deviceError(let code): return "Device error code: \(code)"
        case .timeout: return "Operation timed out"
        }
    }
}
