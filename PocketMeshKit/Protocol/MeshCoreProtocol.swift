import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Protocol")

/// High-level protocol handler for MeshCore commands and responses
public actor MeshCoreProtocol {
    let bleManager: BLEManagerProtocol
    private struct ContinuationWrapper {
        let continuation: CheckedContinuation<ProtocolFrame, Error>
        let id: Int
        private var hasResumed: Bool = false

        init(continuation: CheckedContinuation<ProtocolFrame, Error>, id: Int) {
            self.continuation = continuation
            self.id = id
        }

        mutating func resume(returning value: ProtocolFrame) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }

        mutating func resume(throwing error: Error) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }

    private var responseContinuations: [UInt8: ContinuationWrapper] = [:]
    private var multiFrameContinuations: [Int: Set<UInt8>] = [:]
    private var resumedContinuations: Set<Int> = []
    private var continuationIdCounter: Int = 0
    private var cancellables = Set<AnyCancellable>()

    // Add debugging for continuation tracking
    private var activeContinuationIds: Set<Int> = []

    // Request queue management for concurrent requests
    private var requestQueue: [UInt8: [ContinuationWrapper]] = [:] // Allow multiple waiters per code

    // Request ID tracking for enhanced concurrent request handling
    private var requestIdCounter: UInt32 = 0
    private var pendingRequests: [UInt32: ContinuationWrapper] = [:]

    // Push notification handlers
    private var pushHandlers: [@Sendable (UInt8, Data) async -> Void] = []

    public init(bleManager: BLEManagerProtocol) {
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

    public func sendCommand(
        _ frame: ProtocolFrame,
        expectingResponse expectedCode: UInt8,
    ) async throws -> ProtocolFrame {
        try await sendCommandWithRequestID(frame, expectingResponse: expectedCode)
    }

    private func handleIncomingFrame(_ data: Data) {
        do {
            let frame = try ProtocolFrame.decode(data)
            logger.debug("Received frame code: \(frame.code)")

            // Try to extract request ID from response payload
            let requestId = extractRequestID(from: frame.payload)

            // First try to match by request ID
            if let requestId,
               let wrapper = pendingRequests.removeValue(forKey: requestId)
            {
                // Clean up from legacy tracking
                responseContinuations.removeValue(forKey: frame.code)
                activeContinuationIds.remove(wrapper.id)

                // Remove from request queue as well (for backward compatibility)
                if var waiters = requestQueue[frame.code] {
                    waiters.removeAll { $0.id == wrapper.id }
                    if waiters.isEmpty {
                        requestQueue.removeValue(forKey: frame.code)
                    } else {
                        requestQueue[frame.code] = waiters
                    }
                }

                // Strip request ID from response payload before returning
                let responseWithoutRequestId: ProtocolFrame
                if frame.payload.count >= 4 {
                    let strippedPayload = frame.payload.subdata(in: 4..<frame.payload.count)
                    responseWithoutRequestId = ProtocolFrame(code: frame.code, payload: strippedPayload)
                } else {
                    responseWithoutRequestId = frame
                }

                var mutableWrapper = wrapper
                mutableWrapper.resume(returning: responseWithoutRequestId)
                return
            }

            // Fall back to existing response code matching for backward compatibility
            if var waiters = requestQueue[frame.code], !waiters.isEmpty {
                // Resume the first waiter and remove it from queue
                let wrapper = waiters.removeFirst()

                if waiters.isEmpty {
                    requestQueue.removeValue(forKey: frame.code)
                } else {
                    requestQueue[frame.code] = waiters
                }

                // Clean up from responseContinuations
                responseContinuations.removeValue(forKey: frame.code)

                // Remove from active tracking
                activeContinuationIds.remove(wrapper.id)

                // Check if this is a multi-frame continuation
                let continuationId = wrapper.id
                if continuationId >= 0 {
                    resumedContinuations.insert(continuationId)

                    if let associatedCodes = multiFrameContinuations[continuationId] {
                        for code in associatedCodes {
                            // Remove this continuation from other codes as well
                            if var otherWaiters = requestQueue[code] {
                                otherWaiters.removeAll { $0.id == continuationId }
                                if otherWaiters.isEmpty {
                                    requestQueue.removeValue(forKey: code)
                                } else {
                                    requestQueue[code] = otherWaiters
                                }
                            }
                            responseContinuations.removeValue(forKey: code)
                        }
                        multiFrameContinuations.removeValue(forKey: continuationId)
                    }
                }

                var mutableWrapper = wrapper
                mutableWrapper.resume(returning: frame)
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

        // First try the new registry system
        Self.handlePushNotification(code: frame.code, payload: frame.payload)

        // Also maintain existing handler system for backwards compatibility
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
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let continuationId = continuationIdCounter
                continuationIdCounter += 1

                // Track active continuation for debugging
                activeContinuationIds.insert(continuationId)

                var wrapper = ContinuationWrapper(continuation: continuation, id: continuationId)
                if requestQueue[code] == nil {
                    requestQueue[code] = []
                }
                requestQueue[code]?.append(wrapper)
                responseContinuations[code] = wrapper

                // Set up timeout with enhanced cleanup
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                    // Check if continuation is still active
                    guard activeContinuationIds.contains(continuationId) else {
                        return // Already handled
                    }

                    // Remove from active tracking
                    activeContinuationIds.remove(continuationId)

                    // Clean up request queue with better error handling
                    if var waiters = requestQueue[code] {
                        waiters.removeAll { $0.id == continuationId }
                        if waiters.isEmpty {
                            requestQueue.removeValue(forKey: code)
                        } else {
                            requestQueue[code] = waiters
                        }
                    }

                    // Clean up from responseContinuations
                    responseContinuations.removeValue(forKey: code)

                    // Clean up from pendingRequests if this was a request ID based request
                    if continuationId >= 0 {
                        pendingRequests.removeValue(forKey: UInt32(continuationId))
                    }

                    // Resume with timeout
                    wrapper.resume(throwing: ProtocolError.timeout)
                }
            }
        }
    }

    /// Wait for one of multiple response codes (for multi-frame protocols)
    public func waitForMultiFrameResponse(codes: [UInt8], timeout: TimeInterval) async throws -> ProtocolFrame {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let continuationId = continuationIdCounter
                continuationIdCounter += 1
                let codeSet = Set(codes)

                // Track which codes belong to this continuation
                multiFrameContinuations[continuationId] = codeSet

                // Store continuation for all expected codes
                var wrapper = ContinuationWrapper(continuation: continuation, id: continuationId)
                for code in codes {
                    if requestQueue[code] == nil {
                        requestQueue[code] = []
                    }
                    requestQueue[code]?.append(wrapper)
                    responseContinuations[code] = wrapper
                }

                // Set up timeout with state tracking to prevent double-resume
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                    // Atomically check and mark as resumed
                    let wasResumed = !resumedContinuations.insert(continuationId).inserted

                    if !wasResumed {
                        // Clean up all associated continuations from request queue
                        for code in codeSet {
                            if var waiters = requestQueue[code] {
                                waiters.removeAll { $0.id == continuationId }
                                if waiters.isEmpty {
                                    requestQueue.removeValue(forKey: code)
                                } else {
                                    requestQueue[code] = waiters
                                }
                            }
                            responseContinuations.removeValue(forKey: code)
                        }
                        multiFrameContinuations.removeValue(forKey: continuationId)

                        // Clean up from pendingRequests if this was a request ID based request
                        if continuationId >= 0 {
                            pendingRequests.removeValue(forKey: UInt32(continuationId))
                        }

                        // Only resume if it hasn't been resumed already
                        wrapper.resume(throwing: ProtocolError.timeout)
                    }
                }
            }
        }
    }

    // MARK: - Legacy Fallback Mechanism

    private func sendCommandLegacy(
        _ frame: ProtocolFrame,
        expectingResponse expectedCode: UInt8,
    ) async throws -> ProtocolFrame {
        // Use existing implementation for commands that can't be modified
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let wrapper = ContinuationWrapper(continuation: continuation, id: -1)
                responseContinuations[expectedCode] = wrapper

                do {
                    let encodedFrame = frame.encode()
                    try await bleManager.send(frame: encodedFrame)
                    logger.debug("Sent legacy command code: \(frame.code)")
                } catch {
                    responseContinuations.removeValue(forKey: expectedCode)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Enhanced Request Tracking

    private func sendCommandWithRequestID(
        _ frame: ProtocolFrame,
        expectingResponse expectedCode: UInt8,
    ) async throws -> ProtocolFrame {
        let requestId = requestIdCounter
        requestIdCounter += 1

        // Add request ID to frame payload if not already present
        let frameWithID = ProtocolFrame(
            code: frame.code,
            payload: addRequestID(frame.payload, id: requestId),
        )

        // Use enhanced continuation tracking
        return try await sendCommandWithTracking(frameWithID, expectingResponse: expectedCode, requestId: requestId)
    }

    public func sendCommandWithTracking(
        _ frame: ProtocolFrame,
        expectingResponse expectedCode: UInt8,
        requestId: UInt32,
    ) async throws -> ProtocolFrame {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let wrapper = ContinuationWrapper(continuation: continuation, id: Int(requestId))
                pendingRequests[requestId] = wrapper

                // Also maintain existing responseContinuations for backward compatibility
                responseContinuations[expectedCode] = wrapper

                do {
                    let encodedFrame = frame.encode()
                    try await bleManager.send(frame: encodedFrame)
                    logger.debug("Sent command code: \(frame.code) with request ID: \(requestId)")
                } catch {
                    pendingRequests.removeValue(forKey: requestId)
                    responseContinuations.removeValue(forKey: expectedCode)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Request ID Helper Functions

    private func addRequestID(_ payload: Data, id: UInt32) -> Data {
        var newPayload = Data()
        withUnsafeBytes(of: id.littleEndian) { newPayload.append(contentsOf: $0) }
        newPayload.append(payload)
        return newPayload
    }

    private func extractRequestID(from payload: Data) -> UInt32? {
        guard payload.count >= 4 else { return nil }
        return payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
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
            buildDate: buildDate,
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
        let publicKey = data.subdata(in: offset ..< offset + 32)
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
            radioCodingRate: radioCodingRate,
        )
    }
}
