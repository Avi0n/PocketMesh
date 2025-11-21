import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Telemetry")

public extension MeshCoreProtocol {
    // MARK: - Telemetry Requests

    /// CMD_REQ_TELEMETRY (31): Request LPP-encoded telemetry data from sensor/repeater
    func requestTelemetry(
        from contact: ContactData,
        timeout: TimeInterval = 10.0,
    ) async throws -> TelemetryData {
        var payload = Data()

        // Target public key (32 bytes)
        payload.append(contact.publicKey)

        let frame = ProtocolFrame(code: CommandCode.requestTelemetry.rawValue, payload: payload)

        // Send request
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info("Telemetry request sent to \(contact.name), timeout: \(sendResult.timeoutSeconds)s")

        // Wait for TELEMETRY_RESPONSE push (0x8B)
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.timeoutSeconds)
        let telemetryPush = try await waitForPushCode(
            code: PushCode.telemetryResponse.rawValue,
            matchingPublicKey: contact.publicKey.prefix(6),
            timeout: actualTimeout,
        )

        return try TelemetryData.decode(from: telemetryPush)
    }

    // MARK: - Status Requests

    /// CMD_REQ_STATUS (32): Request repeater status information
    func requestStatus(from contact: ContactData, timeout: TimeInterval = 10.0) async throws -> StatusData {
        guard contact.type == .repeater || contact.type == .room else {
            throw ProtocolError.invalidPayload // Status only works for repeaters
        }

        var payload = Data()
        payload.append(contact.publicKey)

        let frame = ProtocolFrame(code: CommandCode.requestStatus.rawValue, payload: payload)

        // Send request
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info("Status request sent to \(contact.name), timeout: \(sendResult.timeoutSeconds)s")

        // Wait for STATUS_RESPONSE push (0x87)
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.timeoutSeconds)
        let statusPush = try await waitForPushCode(
            code: PushCode.statusResponse.rawValue,
            matchingPublicKey: contact.publicKey.prefix(6),
            timeout: actualTimeout,
        )

        return try StatusData.decode(from: statusPush)
    }

    // MARK: - Neighbour Table Requests

    /// CMD_REQ_NEIGHBOURS (33): Request neighbour table from repeater
    func requestNeighbours(
        from contact: ContactData,
        timeout: TimeInterval = 15.0,
    ) async throws -> [NeighbourEntry] {
        guard contact.type == .repeater || contact.type == .room else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()
        payload.append(contact.publicKey)

        let frame = ProtocolFrame(code: CommandCode.requestNeighbours.rawValue, payload: payload)

        // Send request (neighbours come as multiple binary responses)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info("Neighbours request sent to \(contact.name), timeout: \(sendResult.timeoutSeconds)s")

        // Collect multiple BINARY_RESPONSE pushes until timeout
        var neighbours: [NeighbourEntry] = []
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.timeoutSeconds)
        let deadline = Date().addingTimeInterval(actualTimeout)

        while Date() < deadline {
            do {
                let remainingTimeout = deadline.timeIntervalSinceNow
                guard remainingTimeout > 0 else { break }

                let neighbourPush = try await waitForPushCode(
                    code: PushCode.binaryResponse.rawValue,
                    matchingPublicKey: contact.publicKey.prefix(6),
                    timeout: remainingTimeout,
                )

                let entry = try NeighbourEntry.decode(from: neighbourPush)
                neighbours.append(entry)

            } catch ProtocolError.timeout {
                // Timeout indicates no more neighbours
                break
            }
        }

        logger.info("Received \(neighbours.count) neighbours from \(contact.name)")
        return neighbours
    }

    // MARK: - Sensor MMA Requests

    /// CMD_REQ_MMA (34): Request min/max/avg sensor data over time range
    func requestMMA(
        from contact: ContactData,
        fromSeconds: Int,
        toSeconds: Int,
        timeout: TimeInterval = 15.0,
    ) async throws -> MMAData {
        guard contact.type == .repeater else {
            throw ProtocolError.invalidPayload // MMA only for sensors (type 4 in CLI)
        }

        var payload = Data()

        // Target public key (32 bytes)
        payload.append(contact.publicKey)

        // Time range (uint32 little-endian, seconds ago from now)
        let fromSecsU32 = UInt32(fromSeconds)
        let toSecsU32 = UInt32(toSeconds)

        withUnsafeBytes(of: fromSecsU32.littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: toSecsU32.littleEndian) { payload.append(contentsOf: $0) }

        let frame = ProtocolFrame(code: CommandCode.requestMMA.rawValue, payload: payload)

        // Send request
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info(
            """
            MMA request sent to \(contact.name), range: \(fromSeconds)s-\(toSeconds)s, \
            timeout: \(sendResult.timeoutSeconds)s
            """,
        )

        // Wait for BINARY_RESPONSE push (0x8C)
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.timeoutSeconds)
        let mmaPush = try await waitForPushCode(
            code: PushCode.binaryResponse.rawValue,
            matchingPublicKey: contact.publicKey.prefix(6),
            timeout: actualTimeout,
        )

        return try MMAData.decode(from: mmaPush)
    }

    // MARK: - Push Code Matching with Public Key

    /// Wait for push code with public key prefix matching
    private func waitForPushCode(code: UInt8, matchingPublicKey: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            // Register this specific response expectation
            let key = "pubkey:\(matchingPublicKey.hexString)"
            MeshCoreProtocol.registerPendingPush(code: code, key: key, continuation: continuation)

            // Set up timeout with safety flag
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                continuation.resume(throwing: ProtocolError.timeout)
            }
        }
    }

    // MARK: - Keep Alive Requests

    /// SEND_KEEP_ALIVE (BinaryReqType.KEEP_ALIVE = 0x02): Send keep-alive ping to repeater/sensor
    func sendKeepAlive(to contact: ContactData, timeout: TimeInterval = 10.0) async throws -> KeepAliveResult {
        var payload = Data()

        // Target public key (32 bytes)
        payload.append(contact.publicKey)

        // Binary request type (KEEP_ALIVE = 0x02)
        payload.append(0x02)

        let frame = ProtocolFrame(code: CommandCode.sendCommand.rawValue, payload: payload)

        // Send keep-alive request
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.sent.rawValue)
        let sendResult = try MessageSendResult.decode(from: response.payload)

        logger.info("Keep-alive sent to \(contact.name), timeout: \(sendResult.timeoutSeconds)s")

        // Wait for BINARY_RESPONSE push (0x8C) with keep-alive data
        let actualTimeout = timeout > 0 ? timeout : Double(sendResult.timeoutSeconds)
        let keepAlivePush = try await waitForPushCode(
            code: PushCode.binaryResponse.rawValue,
            matchingPublicKey: contact.publicKey.prefix(6),
            timeout: actualTimeout,
        )

        return try KeepAliveResult.decode(from: keepAlivePush)
    }
}

// MARK: - Telemetry Data Types

public struct TelemetryData: Sendable {
    public let publicKeyPrefix: Data // 6 bytes
    public let lppData: Data // LPP-encoded sensor data
    public let timestamp: Date

    // Parsed LPP fields (extend as needed)
    public var temperature: Double?
    public var humidity: Double?
    public var pressure: Double?
    public var batteryVoltage: Double?

    static func decode(from data: Data) throws -> TelemetryData {
        guard data.count >= 6 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key prefix (6 bytes)
        let publicKeyPrefix = data.subdata(in: offset ..< offset + 6)
        offset += 6

        // LPP data (rest of payload)
        let lppData = data.subdata(in: offset ..< data.count)

        // Parse LPP format (Cayenne LPP: channel | type | value)
        var temperature: Double?
        var humidity: Double?
        var pressure: Double?
        var batteryVoltage: Double?

        var lppOffset = 0
        while lppOffset < lppData.count - 2 {
            let channel = lppData[lppOffset]
            let type = lppData[lppOffset + 1]
            lppOffset += 2

            // Temperature (type 103, 2 bytes, int16 * 0.1)
            if type == 103, lppData.count >= lppOffset + 2 {
                let tempRaw = lppData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: lppOffset, as: Int16.self)
                }
                temperature = Double(tempRaw) / 10.0
                lppOffset += 2
            }

            // Humidity (type 104, 1 byte, uint8 * 0.5)
            else if type == 104, lppData.count >= lppOffset + 1 {
                let humRaw = lppData[lppOffset]
                humidity = Double(humRaw) / 2.0
                lppOffset += 1
            }

            // Barometric pressure (type 115, 2 bytes, uint16 * 0.1)
            else if type == 115, lppData.count >= lppOffset + 2 {
                let pressRaw = lppData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: lppOffset, as: UInt16.self)
                }
                pressure = Double(pressRaw) / 10.0
                lppOffset += 2
            }

            // Analog input / battery (type 2, 2 bytes, uint16 * 0.01)
            else if type == 2, lppData.count >= lppOffset + 2 {
                let voltRaw = lppData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: lppOffset, as: UInt16.self)
                }
                batteryVoltage = Double(voltRaw) / 100.0
                lppOffset += 2
            } else {
                // Unknown type, skip
                break
            }
        }

        return TelemetryData(
            publicKeyPrefix: publicKeyPrefix,
            lppData: lppData,
            timestamp: Date(),
            temperature: temperature,
            humidity: humidity,
            pressure: pressure,
            batteryVoltage: batteryVoltage,
        )
    }
}

public struct KeepAliveResult: Sendable {
    public let publicKeyPrefix: Data
    public let timestamp: Date
    public let uptime: TimeInterval // Seconds since boot
    public let sequenceNumber: UInt8

    static func decode(from data: Data) throws -> KeepAliveResult {
        guard data.count >= 8 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key prefix (6 bytes)
        let publicKeyPrefix = data.subdata(in: offset ..< offset + 6)
        offset += 6

        // Sequence number (1 byte)
        let sequenceNumber = data[offset]
        offset += 1

        // Uptime (uint32 seconds, but we only have 1 byte left in minimum format)
        // For keep-alive, uptime might be truncated or encoded differently
        let uptimeSeconds: TimeInterval = if data.count >= offset + 4 {
            // Full 4-byte uptime available
            TimeInterval(data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            })
        } else if data.count > offset {
            // Single byte uptime (0-255 seconds)
            TimeInterval(data[offset])
        } else {
            // No uptime data, use current time
            0
        }

        return KeepAliveResult(
            publicKeyPrefix: publicKeyPrefix,
            timestamp: Date(),
            uptime: uptimeSeconds,
            sequenceNumber: sequenceNumber,
        )
    }
}
