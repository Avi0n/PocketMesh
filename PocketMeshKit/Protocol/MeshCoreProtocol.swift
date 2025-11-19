import Foundation
import OSLog
import Combine

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Protocol")

/// High-level protocol handler for MeshCore commands and responses
public actor MeshCoreProtocol {

    let bleManager: BLEManager
    private var responseContinuations: [UInt8: CheckedContinuation<ProtocolFrame, Error>] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Push notification handlers
    private var pushHandlers: [@Sendable (UInt8, Data) async -> Void] = []

    public init(bleManager: BLEManager) {
        self.bleManager = bleManager

        // Subscribe to incoming frames
        Task { @MainActor in
            for await frame in bleManager.framePublisher.values {
                await self.handleIncomingFrame(frame)
            }
        }
    }

    // MARK: - Core Commands

    /// CMD_DEVICE_QUERY (22): Initial handshake to get device info
    public func deviceQuery() async throws -> DeviceInfo {
        let frame = ProtocolFrame(code: CommandCode.deviceQuery.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.deviceInfo.rawValue)
        return try DeviceInfo.decode(from: response.payload)
    }

    /// CMD_APP_START (1): Get self-info including public key and radio params
    public func appStart() async throws -> SelfInfo {
        let frame = ProtocolFrame(code: CommandCode.appStart.rawValue)
        let response = try await sendCommand(frame, expectingResponse: ResponseCode.selfInfo.rawValue)
        return try SelfInfo.decode(from: response.payload)
    }

    // MARK: - Internal Helpers

    public func sendCommand(_ frame: ProtocolFrame, expectingResponse expectedCode: UInt8) async throws -> ProtocolFrame {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Store continuation for this expected response code
                responseContinuations[expectedCode] = continuation

                do {
                    let encodedFrame = frame.encode()
                    try await bleManager.send(frame: encodedFrame)
                    logger.debug("Sent command code: \(frame.code)")
                } catch {
                    responseContinuations.removeValue(forKey: expectedCode)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handleIncomingFrame(_ data: Data) {
        do {
            let frame = try ProtocolFrame.decode(data)
            logger.debug("Received frame code: \(frame.code)")

            // Check if we're waiting for this response
            if let continuation = responseContinuations.removeValue(forKey: frame.code) {
                continuation.resume(returning: frame)
            } else {
                // Handle unsolicited frames (push notifications, etc.)
                handlePushNotification(frame)
            }

        } catch {
            logger.error("Failed to decode frame: \(error.localizedDescription)")
        }
    }

    private func handlePushNotification(_ frame: ProtocolFrame) {
        // Handle push codes (0x80+)
        guard let pushCode = PushCode(rawValue: frame.code) else {
            logger.warning("Unhandled frame code: \(frame.code)")
            return
        }

        logger.info("Received push notification: \(pushCode.rawValue)")

        // Dispatch to registered handlers
        Task {
            for handler in pushHandlers {
                await handler(frame.code, frame.payload)
            }
        }
    }

    // MARK: - Push Notification Support

    /// Subscribe to push notifications from the device
    public func subscribeToPushNotifications(handler: @escaping @Sendable (UInt8, Data) async -> Void) {
        pushHandlers.append(handler)
    }

    // MARK: - Multi-Frame Response Support

    /// Wait for a specific response code with timeout
    public func waitForResponse(code: UInt8, timeout: TimeInterval) async throws -> ProtocolFrame {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Store continuation
                responseContinuations[code] = continuation

                // Set up timeout
                Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if responseContinuations.removeValue(forKey: code) != nil {
                        continuation.resume(throwing: ProtocolError.timeout)
                    }
                }
            }
        }
    }

    /// Wait for one of multiple response codes (for multi-frame protocols)
    public func waitForMultiFrameResponse(codes: [UInt8], timeout: TimeInterval) async throws -> ProtocolFrame {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Store continuation for all expected codes
                for code in codes {
                    responseContinuations[code] = continuation
                }

                // Set up timeout
                Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                    // Clean up all continuations if timeout occurs
                    var didTimeout = false
                    for code in codes {
                        if responseContinuations.removeValue(forKey: code) != nil {
                            didTimeout = true
                        }
                    }

                    if didTimeout {
                        continuation.resume(throwing: ProtocolError.timeout)
                    }
                }
            }
        }
    }
}

// MARK: - Device Info Response

public struct DeviceInfo: Sendable {
    public let firmwareVersion: String
    public let maxContacts: UInt16
    public let maxChannels: UInt8
    public let blePin: UInt32
    public let manufacturer: String
    public let model: String
    public let buildDate: String

    public static func decode(from data: Data) throws -> DeviceInfo {
        // Parse per protocol spec (example structure)
        guard data.count >= 20 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Read firmware version (4 bytes: major.minor.patch.build)
        let major = data[offset]
        let minor = data[offset + 1]
        let patch = data[offset + 2]
        let build = data[offset + 3]
        let firmwareVersion = "\(major).\(minor).\(patch).\(build)"
        offset += 4

        // Read max contacts (uint16 little-endian)
        let maxContacts = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        offset += 2

        // Read max channels (uint8)
        let maxChannels = data[offset]
        offset += 1

        // Read BLE PIN (uint32 little-endian)
        let blePin = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        // Read strings (null-terminated or fixed length - adjust per actual protocol)
        let manufacturer = "MeshCore" // Placeholder
        let model = "Radio v1" // Placeholder
        let buildDate = "2025-11-17" // Placeholder

        return DeviceInfo(
            firmwareVersion: firmwareVersion,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            blePin: blePin,
            manufacturer: manufacturer,
            model: model,
            buildDate: buildDate
        )
    }
}

// MARK: - Self Info Response

public struct SelfInfo: Sendable {
    public let publicKey: Data // 32 bytes
    public let txPower: Int8 // dBm
    public let latitude: Double?
    public let longitude: Double?
    public let radioFrequency: UInt32
    public let radioBandwidth: UInt32
    public let radioSpreadingFactor: UInt8
    public let radioCodingRate: UInt8

    public static func decode(from data: Data) throws -> SelfInfo {
        guard data.count >= 50 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Read 32-byte public key
        let publicKey = data.subdata(in: offset..<offset + 32)
        offset += 32

        // Read TX power (int8)
        let txPower = Int8(bitPattern: data[offset])
        offset += 1

        // Read coordinates (int32 * 1E6, little-endian)
        let latRaw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        let latitude: Double? = latRaw != 0 ? Double(latRaw) / 1_000_000.0 : nil
        offset += 4

        let lonRaw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        let longitude: Double? = lonRaw != 0 ? Double(lonRaw) / 1_000_000.0 : nil
        offset += 4

        // Read radio params (all uint32 little-endian)
        let radioFrequency = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        let radioBandwidth = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4

        let radioSpreadingFactor = data[offset]
        offset += 1

        let radioCodingRate = data[offset]

        return SelfInfo(
            publicKey: publicKey,
            txPower: txPower,
            latitude: latitude,
            longitude: longitude,
            radioFrequency: radioFrequency,
            radioBandwidth: radioBandwidth,
            radioSpreadingFactor: radioSpreadingFactor,
            radioCodingRate: radioCodingRate
        )
    }
}
