import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "BinaryProtocol")

/// Binary request types per MeshCore firmware specification
public enum BinaryRequestType: UInt8, Sendable, Codable {
    case getStatus = 1 // REQ_TYPE_GET_STATUS
    case keepAlive = 2 // REQ_TYPE_KEEP_ALIVE
    case getTelemetry = 3 // REQ_TYPE_GET_TELEMETRY_DATA
}

/// Binary request for firmware binary protocol
public struct BinaryRequest: Codable, Sendable {
    public let destinationPublicKey: Data // pub_key:32
    public let requestType: BinaryRequestType
    public let requestData: Data? // req_data:variable

    public init(destinationPublicKey: Data, requestType: BinaryRequestType, requestData: Data? = nil) {
        self.destinationPublicKey = destinationPublicKey
        self.requestType = requestType
        self.requestData = requestData
    }

    public func encode() -> Data {
        var payload = Data()
        payload.append(CommandCode.sendBinaryReq.rawValue) // 50
        payload.append(destinationPublicKey) // pub_key:32
        payload.append(requestType.rawValue)
        if let requestData {
            payload.append(requestData)
        }
        return payload
    }
}

/// Binary response from firmware
public struct BinaryResponse: Sendable {
    public let responseType: UInt8
    public let tag: UInt8 // Binary request correlation tag
    public let payload: Data

    public init(responseType: UInt8, tag: UInt8, payload: Data) {
        self.responseType = responseType
        self.tag = tag
        self.payload = payload
    }

    public static func decode(from frame: ProtocolFrame) throws -> BinaryResponse {
        guard frame.payload.count >= 1 else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid binary response"))
        }

        let tag = frame.payload[0]
        let responseData = Data(frame.payload.dropFirst(1))

        return BinaryResponse(responseType: frame.code, tag: tag, payload: responseData)
    }
}

public extension MeshCoreProtocol {
    /// CMD_SEND_BINARY_REQ (50): Send binary request to contact
    func sendBinaryRequest(_ request: BinaryRequest) async throws {
        let frame = ProtocolFrame(code: CommandCode.sendBinaryReq.rawValue, payload: request.encode())
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        // Binary responses come as PUSH_CODE_BINARY_RESPONSE (0x8C) asynchronously
    }

    /// Request telemetry from a device
    func requestTelemetry(from devicePublicKey: Data) async throws {
        let request = BinaryRequest(
            destinationPublicKey: devicePublicKey,
            requestType: .getTelemetry,
        )
        try await sendBinaryRequest(request)
    }
}
