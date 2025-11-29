import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "PathDiscovery")

public extension MeshCoreProtocol {
    // MARK: - Path Discovery

    /// CMD_SEND_PATH_DISCOVERY (28): Discover bidirectional path to contact
    /// Returns: in_path (from contact to self) and out_path (from self to contact)
    func discoverPath(
        to contact: ContactData,
        timeout: TimeInterval = 10.0,
    ) async throws -> PathDiscoveryResult {
        var payload = Data()

        // Recipient public key (32 bytes)
        payload.append(contact.publicKey)

        let frame = ProtocolFrame(code: CommandCode.sendPathDiscovery.rawValue, payload: payload)

        // Send command
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info("Path discovery request sent, suggested timeout: \(sendResult.estimatedTimeout)ms")

        // Wait for path discovery response with timeout
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.estimatedTimeout) / 1000.0
        let pathResponse = try await waitForResponse(
            code: ResponseCode.pathDiscoveryResponse.rawValue,
            timeout: actualTimeout,
        )

        return try PathDiscoveryResult.decode(from: pathResponse.payload)
    }

    // MARK: - Trace Protocol

    /// CMD_SEND_TRACE (27): Send trace packet along specified path
    /// - Parameter path: Comma-separated hex path (e.g., "a1,b2,c3" or direct contact pubkey prefix)
    func sendTrace(path: String, timeout: TimeInterval = 10.0) async throws -> TraceResult {
        guard let pathData = path.data(using: .utf8), pathData.count <= 128 else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()
        payload.append(pathData)

        let frame = ProtocolFrame(code: CommandCode.sendTrace.rawValue, payload: payload)

        // Send command
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        // Extract tag from ACK code (little-endian uint32)
        let tag = sendResult.expectedAck

        logger.info("Trace request sent, tag: \(String(format: "%08X", tag)), timeout: \(sendResult.estimatedTimeout)ms")

        // Wait for TRACE_DATA push notification (0x89)
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.estimatedTimeout) / 1000.0
        let traceResponse = try await waitForPushCode(
            code: PushCode.traceData.rawValue,
            matchingTag: tag,
            timeout: actualTimeout,
        )

        return try TraceResult.decode(from: traceResponse)
    }

    /// CMD_RESET_PATH (13): Clear cached routing path for a contact
    /// Called when switching to flood mode to clear stale direct path
    func resetPath(publicKey: Data) async throws {
        guard publicKey.count == 32 else {
            throw ProtocolError.invalidParameter
        }

        var payload = Data()
        payload.append(publicKey)

        let frame = ProtocolFrame(code: CommandCode.resetPath.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_CHANGE_CONTACT_PATH (29): Manually set contact routing path
    func changeContactPath(for contact: ContactData, path: String) async throws {
        var payload = Data()

        // Public key (32 bytes)
        payload.append(contact.publicKey)

        // Path (hex string converted to bytes)
        let pathBytes = Data(hexString: path.replacingOccurrences(of: ",", with: ""))
        guard pathBytes.count <= 64 else {
            throw ProtocolError.invalidPayload
        }

        // Path length (1 byte)
        payload.append(UInt8(pathBytes.count))

        // Path data (up to 64 bytes)
        payload.append(pathBytes)

        let frame = ProtocolFrame(code: CommandCode.changeContactPath.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Changed path for \(contact.name) to: \(path)")
    }

    // MARK: - Push Code Matching

    /// Wait for a specific push code with tag matching
    private func waitForPushCode(code: UInt8, matchingTag: UInt32, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            // Register this specific response expectation
            let key = "tag:\(String(format: "%08X", matchingTag))"
            registerPendingPush(code: code, key: key, continuation: continuation)

            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                continuation.resume(throwing: ProtocolError.timeout)
            }
        }
    }
}

// MARK: - Supporting Types

public struct PathDiscoveryResult: Sendable {
    public let inPath: Data // Path from contact to self (hex bytes)
    public let outPath: Data // Path from self to contact (hex bytes)

    public var inPathHex: String {
        inPath.hexString
    }

    public var outPathHex: String {
        outPath.hexString
    }

    public var inPathHops: Int {
        inPath.count / 2 // Each hop is 2 hex chars (1 byte)
    }

    public var outPathHops: Int {
        outPath.count / 2
    }

    static func decode(from data: Data) throws -> PathDiscoveryResult {
        guard data.count >= 2 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Out path length (1 byte)
        let outPathLen = Int(data[offset])
        offset += 1

        guard data.count >= offset + outPathLen else {
            throw ProtocolError.invalidPayload
        }

        // Out path data
        let outPath = data.subdata(in: offset ..< offset + outPathLen)
        offset += outPathLen

        // In path length (1 byte)
        guard data.count >= offset + 1 else {
            throw ProtocolError.invalidPayload
        }

        let inPathLen = Int(data[offset])
        offset += 1

        guard data.count >= offset + inPathLen else {
            throw ProtocolError.invalidPayload
        }

        // In path data
        let inPath = data.subdata(in: offset ..< offset + inPathLen)

        return PathDiscoveryResult(inPath: inPath, outPath: outPath)
    }
}

public struct TraceResult: Sendable {
    public struct Hop: Sendable {
        public let nodeHash: String // 2-char hex public key prefix
        public let snr: Double // Signal-to-noise ratio in dB
        public let rssi: Int16 // Received signal strength
    }

    public let tag: UInt32
    public let hops: [Hop]

    static func decode(from data: Data) throws -> TraceResult {
        guard data.count >= 4 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Tag (uint32 little-endian)
        let tag = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        // Number of hops (1 byte)
        guard data.count > offset else {
            throw ProtocolError.invalidPayload
        }

        let hopCount = Int(data[offset])
        offset += 1

        var hops: [Hop] = []

        // Each hop: hash(1 byte) + snr(1 byte int8) + rssi(2 bytes int16)
        for _ in 0 ..< hopCount {
            guard data.count >= offset + 4 else {
                throw ProtocolError.invalidPayload
            }

            let hashByte = data[offset]
            let nodeHash = String(format: "%02x", hashByte)
            offset += 1

            let snrRaw = Int8(bitPattern: data[offset])
            let snr = Double(snrRaw) / 4.0 // SNR is encoded as int8 * 4
            offset += 1

            let rssi = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int16.self) }
            offset += 2

            hops.append(Hop(nodeHash: nodeHash, snr: snr, rssi: rssi))
        }

        return TraceResult(tag: tag, hops: hops)
    }
}

// Helper extension for hex string conversion
extension Data {
    init(hexString: String) {
        var data = Data()
        var hex = hexString

        while hex.count >= 2 {
            let index = hex.index(hex.startIndex, offsetBy: 2)
            let byteString = String(hex[..<index])
            hex = String(hex[index...])

            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
        }

        self = data
    }
}
