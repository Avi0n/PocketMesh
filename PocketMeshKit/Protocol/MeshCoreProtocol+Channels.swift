import Foundation

extension MeshCoreProtocol {

    /// CMD_SEND_CHANNEL_TXT_MSG (3): Broadcast message to channel
    public func sendChannelTextMessage(text: String, channelIndex: UInt8) async throws {
        guard channelIndex < 8 else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()

        // Channel index (0-7)
        payload.append(channelIndex)

        // Text type (TXT_TYPE_PLAIN = 0)
        payload.append(0)

        // Text content (UTF-8, max 160 bytes minus overhead)
        guard let textData = text.data(using: .utf8), textData.count <= 160 else {
            throw ProtocolError.invalidPayload
        }
        payload.append(textData)

        let frame = ProtocolFrame(code: CommandCode.sendChannelTextMessage.rawValue, payload: payload)

        // Channel messages don't return ACK codes (broadcast)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }
}
