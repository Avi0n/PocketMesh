import Foundation

public extension MeshCoreProtocol {
    /// CMD_SEND_TXT_MSG (2): Send direct message to contact
    func sendTextMessage(
        text: String,
        recipientPublicKey: Data,
        floodMode: Bool,
        scope: String? = nil,
        attempt: UInt8 = 0,
    ) async throws -> MessageSendResult {
        // If scope specified, set it before sending
        if let scope {
            try await setFloodScope(scope)
        }

        var payload = Data()

        // Attempt counter (1 byte) - matches Python implementation
        payload.append(attempt)

        // Timestamp (4 bytes, little-endian) - Unix timestamp
        let timestamp = UInt32(Date().timeIntervalSince1970)
        withUnsafeBytes(of: timestamp.littleEndian) { payload.append(contentsOf: $0) }

        // Destination public key (32 bytes)
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
    @preconcurrency
    func syncNextMessage() async throws -> IncomingMessage? {
        let frame = ProtocolFrame(code: CommandCode.syncNextMessage.rawValue)

        // All valid response codes for message polling
        let validResponseCodes = [
            ResponseCode.contactMessageReceived.rawValue, // V2 direct messages
            ResponseCode.channelMessageReceived.rawValue, // V2 channel messages
            ResponseCode.contactMessageReceivedV3.rawValue, // V3 direct messages
            ResponseCode.channelMessageReceivedV3.rawValue, // V3 channel messages
            ResponseCode.noMoreMessages.rawValue, // End of message queue
        ]

        // Send the command and wait for response
        let encodedFrame = frame.encode()
        try await bleManager.send(frame: encodedFrame)

        let response = try await waitForMultiFrameResponse(codes: validResponseCodes, timeout: 5.0)

        // Check for end of message queue
        if response.code == ResponseCode.noMoreMessages.rawValue {
            return nil
        }

        // Decode the message (IncomingMessage decoder handles V2/V3 differences)
        return try IncomingMessage.decode(from: response.payload, code: response.code)
    }

    // MARK: - Flood Scope Management

    /// CMD_SET_FLOOD_SCOPE (25): Set the flood scope for limiting message propagation by region
    /// - Parameter scope: Scope identifier (e.g., "*" for global, "#RegionName" for specific region)
    func setFloodScope(_ scope: String) async throws {
        guard let scopeData = scope.data(using: .utf8), scopeData.count <= 64 else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()
        payload.append(scopeData)

        let frame = ProtocolFrame(code: CommandCode.setFloodScope.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_GET_FLOOD_SCOPE (26): Get the current flood scope setting
    func getFloodScope() async throws -> String {
        let frame = ProtocolFrame(code: CommandCode.getFloodScope.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.floodScope.rawValue)

        guard let scope = String(data: response.payload, encoding: .utf8) else {
            throw ProtocolError.invalidPayload
        }

        return scope
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
        var snr: Double?
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

        var senderPublicKeyPrefix: Data?
        var channelIndex: UInt8?

        if isDirect {
            // Direct message: 6-byte sender public key prefix
            guard data.count >= offset + 6 else { throw ProtocolError.invalidPayload }
            senderPublicKeyPrefix = data.subdata(in: offset ..< offset + 6)
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
        let textData = data.subdata(in: offset ..< data.count)
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
            snr: snr,
        )
    }
}
