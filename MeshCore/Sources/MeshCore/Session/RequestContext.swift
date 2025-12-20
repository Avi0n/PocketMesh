import Foundation

/// Metadata for tracking pending requests (without continuation - that's managed by PendingRequests actor)
public struct RequestContext: Sendable {
    public let expectedAck: Data
    public let requestType: BinaryRequestType?
    public let publicKeyPrefix: Data?
    public let expiresAt: Date
    public let context: [String: Int]  // Additional context (e.g., prefixLength for neighbours)

    public init(
        expectedAck: Data,
        requestType: BinaryRequestType?,
        publicKeyPrefix: Data?,
        expiresAt: Date,
        context: [String: Int] = [:]
    ) {
        self.expectedAck = expectedAck
        self.requestType = requestType
        self.publicKeyPrefix = publicKeyPrefix
        self.expiresAt = expiresAt
        self.context = context
    }
}

/// Composite key for binary response routing (tag + type correlation)
private struct BinaryRequestKey: Hashable {
    let publicKeyPrefix: Data
    let requestType: BinaryRequestType
}

/// Actor for managing pending request continuations safely
/// Keeps CheckedContinuation out of Sendable structs
/// Supports sophisticated routing with tag + type correlation for binary responses
public actor PendingRequests {
    private var requests: [Data: CheckedContinuation<MeshEvent?, Never>] = [:]
    private var metadata: [Data: RequestContext] = [:]

    // Additional index for binary request routing by (publicKeyPrefix, requestType)
    private var binaryRequestIndex: [BinaryRequestKey: Data] = [:]

    /// Register a new pending request and wait for response
    public func register(
        tag: Data,
        requestType: BinaryRequestType? = nil,
        publicKeyPrefix: Data? = nil,
        timeout: TimeInterval,
        context: [String: Int] = [:]
    ) async -> MeshEvent? {
        let requestContext = RequestContext(
            expectedAck: tag,
            requestType: requestType,
            publicKeyPrefix: publicKeyPrefix,
            expiresAt: Date().addingTimeInterval(timeout),
            context: context
        )
        metadata[tag] = requestContext

        // Index binary requests for routing
        if let type = requestType, let prefix = publicKeyPrefix {
            let key = BinaryRequestKey(publicKeyPrefix: prefix, requestType: type)
            binaryRequestIndex[key] = tag
        }

        return await withCheckedContinuation { continuation in
            requests[tag] = continuation

            // Schedule timeout
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                await self.timeout(tag: tag)
            }
        }
    }

    /// Complete a pending request with an event
    public func complete(tag: Data, with event: MeshEvent) {
        if let context = metadata[tag], let type = context.requestType, let prefix = context.publicKeyPrefix {
            let key = BinaryRequestKey(publicKeyPrefix: prefix, requestType: type)
            binaryRequestIndex.removeValue(forKey: key)
        }
        requests.removeValue(forKey: tag)?.resume(returning: event)
        metadata.removeValue(forKey: tag)
    }

    /// Complete a binary request by public key prefix and type
    /// Used when response contains the prefix but not the original tag
    public func completeBinaryRequest(publicKeyPrefix: Data, type: BinaryRequestType, with event: MeshEvent) {
        let key = BinaryRequestKey(publicKeyPrefix: publicKeyPrefix, requestType: type)
        guard let tag = binaryRequestIndex[key] else { return }
        complete(tag: tag, with: event)
    }

    /// Timeout a pending request
    private func timeout(tag: Data) {
        if let context = metadata[tag], let type = context.requestType, let prefix = context.publicKeyPrefix {
            let key = BinaryRequestKey(publicKeyPrefix: prefix, requestType: type)
            binaryRequestIndex.removeValue(forKey: key)
        }
        requests.removeValue(forKey: tag)?.resume(returning: nil)
        metadata.removeValue(forKey: tag)
    }

    /// Check if a tag matches any pending binary request
    public func matchesBinaryRequest(tag: Data, type: BinaryRequestType) -> Bool {
        guard let context = metadata[tag] else { return false }
        return context.requestType == type
    }

    /// Check if there's a pending request for this public key prefix and type
    public func hasPendingBinaryRequest(publicKeyPrefix: Data, type: BinaryRequestType) -> Bool {
        let key = BinaryRequestKey(publicKeyPrefix: publicKeyPrefix, requestType: type)
        return binaryRequestIndex[key] != nil
    }

    /// Clean up expired requests
    public func cleanupExpired() {
        let now = Date()
        for (tag, context) in metadata where context.expiresAt < now {
            timeout(tag: tag)
        }
    }

    /// Get binary request info by tag (expected_ack)
    /// Returns nil if no pending request matches the tag
    public func getBinaryRequestInfo(tag: Data) -> (type: BinaryRequestType, publicKeyPrefix: Data, context: [String: Int])? {
        guard let requestContext = metadata[tag],
              let type = requestContext.requestType,
              let prefix = requestContext.publicKeyPrefix else {
            return nil
        }
        return (type, prefix, requestContext.context)
    }
}
