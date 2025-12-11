import Foundation

// MARK: - Binary Protocol Errors

public enum BinaryProtocolError: Error, Sendable {
    case notConnected
    case invalidResponse
    case requestTimeout
    case sendFailed(String)
}

// MARK: - Pending Binary Request

/// Tracks pending binary protocol requests for correlation with responses
public struct PendingBinaryRequest: Sendable {
    public let requestType: BinaryRequestType
    public let publicKeyPrefix: Data
    public let sentAt: Date
    public let timeout: TimeInterval
    public let context: [String: Int]  // Simplified to [String: Int] for Sendable

    public init(
        requestType: BinaryRequestType,
        publicKeyPrefix: Data,
        sentAt: Date,
        timeout: TimeInterval,
        context: [String: Int] = [:]
    ) {
        self.requestType = requestType
        self.publicKeyPrefix = publicKeyPrefix
        self.sentAt = sentAt
        self.timeout = timeout
        self.context = context
    }
}

// MARK: - Binary Protocol Service

/// Service for binary protocol operations with remote mesh nodes
public actor BinaryProtocolService {

    // MARK: - Properties

    private let bleTransport: any BLETransport
    private var pendingRequests: [Data: PendingBinaryRequest] = [:]

    /// Handler for status responses
    private var statusResponseHandler: (@Sendable (RemoteNodeStatus) -> Void)?

    /// Handler for neighbours responses
    private var neighboursResponseHandler: (@Sendable (NeighboursResponse) -> Void)?

    // MARK: - Initialization

    public init(bleTransport: any BLETransport) {
        self.bleTransport = bleTransport
    }

    // MARK: - Request Methods

    /// Request status from a remote node
    /// - Parameters:
    ///   - publicKey: Full 32-byte public key of recipient
    ///   - timeout: Request timeout in seconds
    /// - Returns: Tag data for tracking the request, or nil if send failed
    public func requestStatus(
        from publicKey: Data,
        timeout: TimeInterval = 30.0
    ) async throws -> Data? {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw BinaryProtocolError.notConnected
        }

        let frameData = FrameCodec.encodeBinaryRequest(
            recipientPublicKey: publicKey,
            requestType: .status
        )

        guard let response = try await bleTransport.send(frameData) else {
            return nil
        }

        // Parse MSG_SENT response to get expected ACK tag and timeout
        guard response.count >= 9,
              response[0] == ResponseCode.sent.rawValue else {
            return nil
        }

        let expectedTag = response.subdata(in: 2..<6)
        let suggestedTimeout = response.subdata(in: 6..<10).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }

        // Track pending request
        pendingRequests[expectedTag] = PendingBinaryRequest(
            requestType: .status,
            publicKeyPrefix: publicKey.prefix(6),
            sentAt: Date(),
            timeout: max(timeout, Double(suggestedTimeout) / 1000.0)
        )

        return expectedTag
    }

    /// Request neighbours list from a remote node
    /// - Parameters:
    ///   - publicKey: Full 32-byte public key of recipient
    ///   - count: Maximum number of neighbours to return
    ///   - offset: Pagination offset
    ///   - pubkeyPrefixLength: Length of public key prefix in response
    /// - Returns: Tag data for tracking the request, or nil if send failed
    public func requestNeighbours(
        from publicKey: Data,
        count: UInt8 = 255,
        offset: UInt16 = 0,
        pubkeyPrefixLength: UInt8 = 4
    ) async throws -> Data? {
        let connectionState = await bleTransport.connectionState
        guard connectionState == .ready else {
            throw BinaryProtocolError.notConnected
        }

        let frameData = FrameCodec.encodeNeighboursRequest(
            recipientPublicKey: publicKey,
            count: count,
            offset: offset,
            pubkeyPrefixLength: pubkeyPrefixLength
        )

        guard let response = try await bleTransport.send(frameData) else {
            return nil
        }

        guard response.count >= 9,
              response[0] == ResponseCode.sent.rawValue else {
            return nil
        }

        let expectedTag = response.subdata(in: 2..<6)

        pendingRequests[expectedTag] = PendingBinaryRequest(
            requestType: .neighbours,
            publicKeyPrefix: publicKey.prefix(6),
            sentAt: Date(),
            timeout: 30.0,
            context: ["pubkeyPrefixLength": Int(pubkeyPrefixLength)]
        )

        return expectedTag
    }

    // MARK: - Response Handling

    /// Handle binary response push notification
    /// - Parameter data: Raw push data starting with PushCode.binaryResponse
    /// - Returns: Parsed response if request was tracked, nil otherwise
    public func handleBinaryResponse(_ data: Data) async throws -> Any? {
        let response = try FrameCodec.decodeBinaryResponse(from: data)

        guard let pending = pendingRequests[response.tag] else {
            return nil
        }

        pendingRequests.removeValue(forKey: response.tag)

        switch pending.requestType {
        case .status:
            let status = try FrameCodec.decodeRemoteNodeStatus(
                from: response.rawData,
                publicKeyPrefix: pending.publicKeyPrefix
            )
            statusResponseHandler?(status)
            return status

        case .neighbours:
            let prefixLength = pending.context["pubkeyPrefixLength"] ?? 4
            let neighbours = try FrameCodec.decodeNeighboursResponse(
                from: response.rawData,
                tag: response.tag,
                pubkeyPrefixLength: prefixLength
            )
            neighboursResponseHandler?(neighbours)
            return neighbours

        case .telemetry, .keepAlive, .mma, .acl:
            // Will be implemented in future phases
            return nil
        }
    }

    // MARK: - Handler Setup

    /// Sets a handler for status response notifications
    public func setStatusResponseHandler(_ handler: @escaping @Sendable (RemoteNodeStatus) -> Void) {
        statusResponseHandler = handler
    }

    /// Sets a handler for neighbours response notifications
    public func setNeighboursResponseHandler(_ handler: @escaping @Sendable (NeighboursResponse) -> Void) {
        neighboursResponseHandler = handler
    }

    // MARK: - Cleanup

    /// Clean up expired pending requests
    public func cleanupExpiredRequests() {
        let now = Date()
        pendingRequests = pendingRequests.filter { _, request in
            now.timeIntervalSince(request.sentAt) < request.timeout
        }
    }

    /// Returns the number of pending requests
    public var pendingRequestCount: Int {
        pendingRequests.count
    }
}
