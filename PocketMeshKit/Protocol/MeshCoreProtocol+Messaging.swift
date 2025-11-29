import Foundation

/// Text message types per MeshCore firmware specification
public enum TextMessageType: UInt8, Sendable {
    case plain = 0 // TXT_TYPE_PLAIN
    case cliData = 1 // TXT_TYPE_CLI_DATA
}

public extension MeshCoreProtocol {
    /// CMD_SEND_TXT_MSG (2): Send direct message to contact
    func sendTextMessage(
        text: String,
        recipientPublicKey: Data,
        floodMode: Bool,
        scope: String? = nil,
        attempt: UInt8 = 0,
        messageType: TextMessageType = .plain,
    ) async throws -> MessageSendResult {
        // If flood mode requested, set flood scope first (before sending message)
        if floodMode {
            let floodScope = scope ?? "*" // Use provided scope or global "*"
            try await setFloodScope(floodScope)
        }

        // Firmware expects: [2][txt_type][attempt][timestamp:4][pub_key_prefix:6][text]
        var payload = Data()

        // Text message type (1 byte)
        payload.append(messageType.rawValue)

        // Attempt counter (1 byte)
        payload.append(attempt)

        // Timestamp (4 bytes, little-endian) - Unix timestamp
        let timestamp = UInt32(Date().timeIntervalSince1970)
        var timestampLE = timestamp.littleEndian
        withUnsafeBytes(of: &timestampLE) { payload.append(contentsOf: $0) }

        // Public key prefix (first 6 bytes of 32-byte key) - firmware optimization
        let pubKeyPrefix = Data(recipientPublicKey.prefix(6))
        payload.append(pubKeyPrefix)

        // Message text (UTF-8 encoded, max 160 bytes)
        // Note: floodMode is NOT part of the message payload
        // It is set via CMD_SET_FLOOD_SCOPE before sending
        guard let textData = text.data(using: .utf8), textData.count <= 160 else {
            throw ProtocolError.invalidPayload
        }
        payload.append(textData)

        let frame = ProtocolFrame(code: CommandCode.sendTextMessage.rawValue, payload: payload)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)

        return try MessageSendResult.decode(from: response.payload)
    }

    /// CMD_SYNC_NEXT_MESSAGE (10): Poll for next queued incoming message
    func syncNextMessage() async throws -> IncomingMessage? {
        let frame = ProtocolFrame(code: CommandCode.syncNextMessage.rawValue, payload: Data())

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
        let frame = ProtocolFrame(code: CommandCode.getFloodScope.rawValue, payload: Data())
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.floodScope.rawValue)

        guard let scope = String(data: response.payload, encoding: .utf8) else {
            throw ProtocolError.invalidPayload
        }

        return scope
    }
}

// MARK: - Supporting Types

public struct MessageSendResult: Sendable {
    let isFlood: Bool // is_flood: 0=direct, 1=flood
    let expectedAck: UInt32 // expected_ack: message tag for confirmation
    let estimatedTimeout: UInt32 // est_timeout: timeout in milliseconds

    static func decode(from data: Data) throws -> MessageSendResult {
        guard data.count >= 9 else { // 1 + 4 + 4 = 9 bytes
            throw ProtocolError.invalidPayload
        }

        let isFlood = data[0] != 0
        let expectedAck = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 1, as: UInt32.self) }
        let estimatedTimeout = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 5, as: UInt32.self) }

        return MessageSendResult(isFlood: isFlood, expectedAck: expectedAck, estimatedTimeout: estimatedTimeout)
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
