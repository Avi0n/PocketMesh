import Foundation

extension MeshCoreProtocol {

    /// CMD_SEND_TXT_MSG (2): Send direct message to contact
    public func sendTextMessage(
        text: String,
        recipientPublicKey: Data,
        floodMode: Bool
    ) async throws -> MessageSendResult {
        var payload = Data()

        // Recipient public key (32 bytes)
        payload.append(recipientPublicKey)

        // Flood mode flag (1 byte)
        payload.append(floodMode ? 1 : 0)

        // Text type (TXT_TYPE_PLAIN = 0)
        payload.append(0)

        // Text content (UTF-8, max 160 bytes)
        guard let textData = text.data(using: .utf8), textData.count <= 160 else {
            throw ProtocolError.invalidPayload
        }
        payload.append(textData)

        let frame = ProtocolFrame(code: CommandCode.sendTextMessage.rawValue, payload: payload)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)

        return try MessageSendResult.decode(from: response.payload)
    }

    /// CMD_SYNC_NEXT_MESSAGE (10): Poll for next queued incoming message
    public func syncNextMessage() async throws -> IncomingMessage? {
        let frame = ProtocolFrame(code: CommandCode.syncNextMessage.rawValue)

        // We need to handle multiple possible response codes
        // For now, we'll implement a simplified version that expects one of the message received codes
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.contactMessageReceivedV3.rawValue)

        if response.code == ResponseCode.noMoreMessages.rawValue {
            return nil
        }

        return try IncomingMessage.decode(from: response.payload, code: response.code)
    }
}

// MARK: - Supporting Types

public struct MessageSendResult: Sendable {
    let ackCode: UInt32
    let timeoutSeconds: UInt16

    static func decode(from data: Data) throws -> MessageSendResult {
        guard data.count >= 6 else {
            throw ProtocolError.invalidPayload
        }

        let ackCode = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let timeoutSeconds = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self) }

        return MessageSendResult(ackCode: ackCode, timeoutSeconds: timeoutSeconds)
    }
}

public struct IncomingMessage: Sendable {
    let isDirect: Bool // true for direct, false for channel
    let senderTimestamp: Date
    let senderPublicKeyPrefix: Data? // 6 bytes for direct messages
    let channelIndex: UInt8? // For channel messages
    let pathLength: UInt8 // 0xFF = direct (no hops)
    let textType: UInt8
    let text: String
    let snr: Double? // SNR * 4 (v3 only)

    static func decode(from data: Data, code: UInt8) throws -> IncomingMessage {
        let isV3 = (code == ResponseCode.contactMessageReceivedV3.rawValue ||
                    code == ResponseCode.channelMessageReceivedV3.rawValue)
        let isDirect = (code == ResponseCode.contactMessageReceived.rawValue ||
                        code == ResponseCode.contactMessageReceivedV3.rawValue)

        var offset = 0

        // SNR (v3 only, at start)
        var snr: Double? = nil
        if isV3 {
            guard data.count > offset else { throw ProtocolError.invalidPayload }
            let snrRaw = Int8(bitPattern: data[offset])
            snr = Double(snrRaw) / 4.0
            offset += 1
        }

        // Sender timestamp (uint32)
        guard data.count >= offset + 4 else { throw ProtocolError.invalidPayload }
        let timestamp = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        let senderTimestamp = Date(timeIntervalSince1970: TimeInterval(timestamp))
        offset += 4

        var senderPublicKeyPrefix: Data? = nil
        var channelIndex: UInt8? = nil

        if isDirect {
            // Direct message: 6-byte sender public key prefix
            guard data.count >= offset + 6 else { throw ProtocolError.invalidPayload }
            senderPublicKeyPrefix = data.subdata(in: offset..<offset + 6)
            offset += 6
        } else {
            // Channel message: channel index
            guard data.count > offset else { throw ProtocolError.invalidPayload }
            channelIndex = data[offset]
            offset += 1
        }

        // Path length
        guard data.count > offset else { throw ProtocolError.invalidPayload }
        let pathLength = data[offset]
        offset += 1

        // Text type
        guard data.count > offset else { throw ProtocolError.invalidPayload }
        let textType = data[offset]
        offset += 1

        // Text content (rest of payload)
        let textData = data.subdata(in: offset..<data.count)
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload
        }

        return IncomingMessage(
            isDirect: isDirect,
            senderTimestamp: senderTimestamp,
            senderPublicKeyPrefix: senderPublicKeyPrefix,
            channelIndex: channelIndex,
            pathLength: pathLength,
            textType: textType,
            text: text,
            snr: snr
        )
    }
}
