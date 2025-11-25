import Foundation

/// Represents a protocol frame (matches ProtocolFrame but internal to mock)
public struct RadioFrame: Sendable {
    public let code: UInt8
    public let payload: Data

    public init(code: UInt8, payload: Data = Data()) {
        self.code = code
        self.payload = payload
    }

    /// Encode to BLE characteristic value
    public func encode() -> Data {
        var data = Data()
        data.append(code)
        data.append(payload)
        return data
    }

    /// Decode from BLE characteristic value
    public static func decode(_ data: Data) throws -> RadioFrame {
        guard !data.isEmpty else {
            throw RadioError.invalidFrame
        }
        let code = data[0]
        let payload = data.count > 1 ? data.subdata(in: 1 ..< data.count) : Data()
        return RadioFrame(code: code, payload: payload)
    }
}

/// Offline queue entry (matches MyMesh::Frame)
struct OfflineQueueEntry: Sendable {
    let frame: RadioFrame
    let timestamp: Date

    func isChannelMsg() -> Bool {
        frame.code == 0x08 || frame.code == 0x11 // RESP_CODE_CHANNEL_MSG_RECV*
    }
}

/// Expected ACK table entry (matches MyMesh::AckTableEntry)
struct ExpectedAckEntry: Sendable {
    let ackCode: UInt32
    let timestamp: Date
    let contactPublicKey: Data // 6-byte prefix
}

/// Radio errors
public enum RadioError: Error, Sendable {
    case invalidFrame
    case queueFull
    case notConnected
    case characteristicNotFound
    case mtuExceeded
}
