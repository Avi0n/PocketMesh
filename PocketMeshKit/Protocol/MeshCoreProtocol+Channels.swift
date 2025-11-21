import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Channels")

public extension MeshCoreProtocol {
    /// CMD_SEND_CHANNEL_TXT_MSG (3): Broadcast message to channel
    func sendChannelTextMessage(
        text: String,
        channelIndex: UInt8,
        scope: String? = nil,
        attempt: UInt8 = 0,
    ) async throws {
        guard channelIndex < 8 else {
            throw ProtocolError.invalidPayload
        }

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

    // MARK: - Channel Management

    /// CMD_GET_CHANNEL (31): Get channel configuration
    func getChannel(channelIndex: UInt8) async throws -> ChannelInfo {
        var payload = Data()
        payload.append(channelIndex)

        let frame = ProtocolFrame(code: CommandCode.getChannel.rawValue, payload: payload)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.channelInfo.rawValue)

        return try ChannelInfo.decode(from: response.payload)
    }

    /// CMD_SET_CHANNEL (32): Set channel configuration with secret key
    func setChannel(channelIndex: UInt8, name: String, secret: Data? = nil) async throws {
        guard channelIndex < 8 else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()

        // Channel index (1 byte)
        payload.append(channelIndex)

        // Channel name processing (null-terminated, padded to 32 bytes)
        let nameBytes = name.data(using: .utf8) ?? Data()
        let truncatedName = nameBytes.prefix(32)
        var paddedName = Data(count: 32)
        paddedName.replaceSubrange(0 ..< truncatedName.count, with: truncatedName)

        payload.append(paddedName)

        // Secret key processing
        var finalSecret: Data
        if let providedSecret = secret {
            // Use provided secret
            guard providedSecret.count == 16 else {
                throw ProtocolError.invalidPayload
            }
            finalSecret = providedSecret
        } else if name.hasPrefix("#") {
            // Auto-generate secret from hash for channels starting with #
            let hash = SHA256.hash(data: name.data(using: .utf8) ?? Data())
            finalSecret = Data(hash.prefix(16))
        } else {
            // No secret for regular channels
            finalSecret = Data(count: 16) // 16 bytes of zeros
        }

        payload.append(finalSecret)

        let frame = ProtocolFrame(code: CommandCode.setChannel.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Channel \(channelIndex) configured with name '\(name)'")
    }
}

// MARK: - Supporting Types

/// Channel information returned by getChannel command
public struct ChannelInfo: Sendable {
    public let channelIndex: UInt8
    public let channelName: String
    public let channelSecret: Data
    public let isActive: Bool

    public init(channelIndex: UInt8, channelName: String, channelSecret: Data, isActive: Bool) {
        self.channelIndex = channelIndex
        self.channelName = channelName
        self.channelSecret = channelSecret
        self.isActive = isActive
    }

    /// Decode channel info from response payload
    static func decode(from data: Data) throws -> ChannelInfo {
        guard data.count >= 33 else {
            throw ProtocolError.invalidPayload
        }

        let channelIndex = data[0]
        let secretData = data.subdata(in: 1 ..< 17) // 16 bytes secret
        let nameData = data.subdata(in: 17 ..< data.count)

        // Find null terminator or use all remaining data
        let nameEndIndex = nameData.firstIndex(of: 0) ?? nameData.count
        let nameBytes = nameData.prefix(nameEndIndex)

        guard let channelName = String(data: nameBytes, encoding: .utf8) else {
            throw ProtocolError.invalidPayload
        }

        let isActive = !secretData.allSatisfy { $0 == 0 } // Non-zero secret means active

        return ChannelInfo(
            channelIndex: channelIndex,
            channelName: channelName,
            channelSecret: secretData,
            isActive: isActive,
        )
    }
}
