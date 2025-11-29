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

    // Registry for pending push notification responses
    var pendingPushResponses: [UInt8: [String: CheckedContinuation<Data, Error>]] = [:]

    public init(bleManager: BLEManagerProtocol) {
        self.bleManager = bleManager

        // Subscribe to incoming frames using AsyncStream (preferred) or Combine (fallback)
        Task {
            // Prefer AsyncStream if available, fall back to Combine
            for await frame in bleManager.frameStream {
                await handleIncomingFrame(frame)
            }
        }
    }

    // MARK: - Core Commands

    /// CMD_DEVICE_QUERY (22): Initial handshake to get device info
    public func deviceQuery() async throws -> DeviceInfo {
        // Protocol requires: 0x16 (command) + 0x03 (protocol version)
        var payload = Data()
        payload.append(0x03) // Protocol version byte
        let frame = ProtocolFrame(code: CommandCode.deviceQuery.rawValue, payload: payload)
        // Use legacy path without request IDs to match MeshCore spec exactly
        let response = try await sendCommandLegacy(frame, expectingResponse: ResponseCode.deviceInfo.rawValue)
        return try DeviceInfo.decode(from: response.payload)
    }

    /// CMD_APP_START (1): Get self-info including public key and radio params
    public func appStart(appName: String = "PocketMesh") async throws -> SelfInfo {
        // Firmware expects: [1][reserved:7][app_name:null_terminated]
        var payload = Data()
        payload.append(contentsOf: repeatElement(0, count: 7)) // reserved:7 bytes
        payload.append(contentsOf: appName.data(using: .utf8) ?? Data()) // app_name (null-terminated)

        let frame = ProtocolFrame(code: CommandCode.appStart.rawValue, payload: payload)
        // Use legacy path without request IDs to match MeshCore spec exactly
        let response = try await sendCommandLegacy(frame, expectingResponse: ResponseCode.selfInfo.rawValue)
        return try SelfInfo.decode(from: response.payload)
    }

    // MARK: - Internal Helpers

    public func sendCommand(
        _ frame: ProtocolFrame,
        expectingResponse expectedCode: UInt8,
    ) async throws -> ProtocolFrame {
        try await sendCommandWithRequestID(frame, expectingResponse: expectedCode)
    }

    private func handleIncomingFrame(_ data: Data) async {
        do {
            let frame = try ProtocolFrame.decode(data)
            logger.debug("Received frame code: \(frame.code)")

            // Try to extract request ID from response payload
            let requestId = extractRequestID(from: frame.payload)

            // First try to match by request ID
            if let requestId,
               let wrapper = pendingRequests.removeValue(forKey: requestId)
            {
                // Only clean up from legacy tracking if this continuation was stored there
                // (which it won't be for request ID commands)
                if responseContinuations[frame.code]?.id == wrapper.id {
                    responseContinuations.removeValue(forKey: frame.code)
                }
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
                    let strippedPayload = frame.payload.subdata(in: 4 ..< frame.payload.count)
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
                // Handle unsolicited frames - check for response continuations first
                if let continuation = responseContinuations[frame.code] {
                    // There's an active continuation waiting for this response code
                    logger.debug("Resuming continuation for response code: \(frame.code)")
                    let wrapper = continuation
                    responseContinuations.removeValue(forKey: frame.code)
                    activeContinuationIds.remove(wrapper.id)

                    var mutableWrapper = wrapper
                    mutableWrapper.resume(returning: frame)
                } else {
                    logger.debug("No continuation found for response code: \(frame.code), checking responseContinuations count: \(self.responseContinuations.count)")
                    if frame.code >= 0x80 {
                        // Handle as push notification (codes 0x80+)
                        handlePushNotification(frame)
                    } else {
                        // Handle as unsolicited response code (codes 0-127) - no active continuation
                        await handleUnsolicitedResponse(frame)
                    }
                }
            }

        } catch {
            logger.error("Failed to decode frame: \(error.localizedDescription)")
        }
    }

    private func handlePushNotification(_ frame: ProtocolFrame) {
        // Handle push codes (0x80+)
        guard let pushCode = PushCode(rawValue: frame.code) else {
            logger.warning("Unhandled push notification code: \(frame.code)")
            return
        }

        logger.info("Received push notification: \(pushCode.rawValue)")

        // First try the new registry system
        handlePushNotification(code: frame.code, payload: frame.payload)

        // Also maintain existing handler system for backwards compatibility
        Task {
            for handler in pushHandlers {
                await handler(frame.code, frame.payload)
            }
        }
    }

    private func handleUnsolicitedResponse(_ frame: ProtocolFrame) async {
        // Handle response codes (0-127) that aren't matched to pending commands
        guard let responseCode = ResponseCode(rawValue: frame.code) else {
            logger.warning("Unhandled response code: \(frame.code)")
            return
        }

        logger.debug("Received unsolicited response: \(responseCode.rawValue)")

        // Try to match with pending command first
        if await tryMatchWithPendingCommand(responseCode: responseCode, data: frame.payload) {
            return
        }

        // Handle as unsolicited response or ignore based on type
        switch responseCode {
        case .ok, .error, .contactsStart, .contact, .endOfContacts, .selfInfo, .sent, .deviceInfo, .batteryAndStorage, .privateKey, .disabled, .currentTime, .noMoreMessages, .channelInfo:
            logger.info("Received unsolicited response code: \(responseCode.rawValue) - no pending command to match")

        default:
            logger.warning("Received unexpected unsolicited response code: \(responseCode.rawValue)")
        }
    }

    private func tryMatchWithPendingCommand(responseCode: ResponseCode, data: Data) async -> Bool {
        // Try to match with any pending request ID based requests
        for (requestId, wrapper) in pendingRequests {
            // Only match if the response code is one that should match a pending request
            // Allow contact sync responses to be matched when using getContacts
            switch responseCode {
            case .ok, .error, .selfInfo, .sent, .deviceInfo, .batteryAndStorage, .privateKey, .disabled, .currentTime, .noMoreMessages, .channelInfo, .contactsStart, .contact, .endOfContacts:
                // These can be matched with pending commands
                break
            default:
                continue
            }

            var mutableWrapper = wrapper
            let responseFrame = ProtocolFrame(code: responseCode.rawValue, payload: data)

            // Remove from pending
            pendingRequests.removeValue(forKey: requestId)

            // Only clean up from legacy tracking if this continuation was stored there
            // (which it won't be for request ID commands)
            if responseContinuations[responseCode.rawValue]?.id == wrapper.id {
                responseContinuations.removeValue(forKey: responseCode.rawValue)
            }
            activeContinuationIds.remove(wrapper.id)

            // Resume the continuation
            mutableWrapper.resume(returning: responseFrame)
            return true
        }

        return false
    }

    // MARK: - Push Notification Support

    /// Register a pending push notification response
    func registerPendingPush(
        code: UInt8,
        key: String,
        continuation: CheckedContinuation<Data, Error>,
    ) {
        if pendingPushResponses[code] == nil {
            pendingPushResponses[code] = [:]
        }
        pendingPushResponses[code]?[key] = continuation
    }

    /// Subscribe to push notifications from the device
    public func subscribeToPushNotifications(handler: @escaping @Sendable (UInt8, Data) async -> Void) {
        pushHandlers.append(handler)
    }

    /// Subscribe to specific push notification types with typed handlers
    public func subscribeToAdvertisements(handler: @escaping @Sendable (AdvertisementPush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.advert.rawValue || code == PushCode.newAdvert.rawValue {
                if let advert = try? AdvertisementPush.decode(from: payload) {
                    Task {
                        await handler(advert)
                    }
                }
            }
        }
    }

    public func subscribeToMessageNotifications(handler: @escaping @Sendable (MessageNotificationPush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.messageWaiting.rawValue {
                if let notification = try? MessageNotificationPush.decode(from: payload) {
                    Task {
                        await handler(notification)
                    }
                }
            }
        }
    }

    public func subscribeToSendConfirmations(handler: @escaping @Sendable (SendConfirmationPush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.sendConfirmed.rawValue {
                if let confirmation = try? SendConfirmationPush.decode(from: payload) {
                    Task {
                        await handler(confirmation)
                    }
                }
            }
        }
    }

    public func subscribeToPathUpdates(handler: @escaping @Sendable (PathUpdatePush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.pathUpdated.rawValue {
                if let update = try? PathUpdatePush.decode(from: payload) {
                    Task {
                        await handler(update)
                    }
                }
            }
        }
    }

    public func subscribeToTelemetry(handler: @escaping @Sendable (TelemetryPush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.telemetryResponse.rawValue {
                if let telemetry = try? TelemetryPush.decode(from: payload) {
                    Task {
                        await handler(telemetry)
                    }
                }
            }
        }
    }

    public func subscribeToDiscoveryResponses(handler: @escaping @Sendable (DiscoveryResponsePush) async -> Void) async {
        subscribeToPushNotifications { code, payload in
            if code == PushCode.pathDiscoveryResponse.rawValue {
                if let discovery = try? DiscoveryResponsePush.decode(from: payload) {
                    Task {
                        await handler(discovery)
                    }
                }
            }
        }
    }

    /// Wait for specific push notification with timeout
    public func waitForAdvertisementPush(timeout: TimeInterval = 30.0) async throws -> AdvertisementPush {
        try await waitForPushNotification(code: PushCode.newAdvert.rawValue, timeout: timeout) { payload in
            try AdvertisementPush.decode(from: payload)
        }
    }

    public func waitForMessageNotification(timeout: TimeInterval = 30.0) async throws -> MessageNotificationPush {
        try await waitForPushNotification(code: PushCode.messageWaiting.rawValue, timeout: timeout) { payload in
            try MessageNotificationPush.decode(from: payload)
        }
    }

    public func waitForSendConfirmation(ackCode: Data, timeout: TimeInterval = 30.0) async throws -> SendConfirmationPush {
        let key = "ack:\(ackCode.hexString)"
        return try await waitForPushNotification(code: PushCode.sendConfirmed.rawValue, timeout: timeout, key: key) { payload in
            try SendConfirmationPush.decode(from: payload)
        }
    }

    /// Generic wait for push notification with timeout and type conversion
    private func waitForPushNotification<T: Sendable>(
        code: UInt8,
        timeout: TimeInterval = 30.0,
        key: String? = nil,
        converter: @escaping @Sendable (Data) throws -> T,
    ) async throws -> T {
        // Create a simple adapter using actor isolation
        let waitResult = try await withThrowingTaskGroup(of: T.self) { [self] group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ProtocolError.timeout
            }

            // Add push notification waiting task
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    // Set up push notification handler
                    let handler: @Sendable (UInt8, Data) async -> Void = { receivedCode, payload in
                        guard receivedCode == code else { return }

                        // Check if this matches our key (if provided)
                        if let key {
                            // Simple key matching for now
                            if key.hasPrefix("ack:") {
                                _ = String(key.dropFirst(4))
                                // Skip complex hex matching for now, just accept any push
                            }
                        }

                        do {
                            let converted = try converter(payload)
                            continuation.resume(returning: converted)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                    // Subscribe temporarily
                    Task { [self] in
                        await subscribeToPushNotifications(handler: handler)
                    }
                }
            }

            // Return the first result
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        return waitResult
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

        logger.debug("🔄 sendCommandWithRequestID: Starting, code: \(frame.code), requestId: \(requestId)")

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
        timeout: TimeInterval = 5.0,
    ) async throws -> ProtocolFrame {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let wrapper = ContinuationWrapper(continuation: continuation, id: Int(requestId))
                pendingRequests[requestId] = wrapper

                // Set up timeout
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                    // Check if request is still pending and timeout
                    if let pendingWrapper = pendingRequests[requestId], pendingWrapper.id == wrapper.id {
                        pendingRequests.removeValue(forKey: requestId)
                        continuation.resume(throwing: ProtocolError.timeout)
                        logger.debug("Command timed out for request ID: \(requestId)")
                    }
                }

                // Don't store in responseContinuations when using request IDs to prevent double processing
                // The request ID handling will take care of resuming the continuation

                do {
                    let encodedFrame = frame.encode()
                    logger.debug("🔄 sendCommandWithRequestID: About to call bleManager.send, frame size: \(encodedFrame.count) bytes")
                    try await bleManager.send(frame: encodedFrame)
                    logger.debug("✅ Sent command code: \(frame.code) with request ID: \(requestId), timeout: \(timeout)s")
                    logger.debug("✅ sendCommandWithRequestID: bleManager.send completed successfully")
                } catch {
                    logger.error("❌ sendCommandWithRequestID: bleManager.send failed: \(error)")
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

// MARK: - Self Info Response

// Use the SelfInfo model from PocketMeshKit/Models/SelfInfo.swift
// This follows the exact firmware specification with all required fields
