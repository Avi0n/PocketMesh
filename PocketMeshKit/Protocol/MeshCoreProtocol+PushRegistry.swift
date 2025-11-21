import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "PushRegistry")

extension MeshCoreProtocol {
    // MARK: - Push Response Registry

    /// Registry for pending push notification responses
    private nonisolated(unsafe) static var pendingPushResponses: [
        UInt8: [String: CheckedContinuation<Data, Error>]
    ] = [:]

    /// Register a pending push notification response
    static func registerPendingPush(
        code: UInt8,
        key: String,
        continuation: CheckedContinuation<Data, Error>,
    ) {
        if pendingPushResponses[code] == nil {
            pendingPushResponses[code] = [:]
        }
        pendingPushResponses[code]?[key] = continuation
    }

    /// Handle incoming push notification and match with pending requests
    static func handlePushNotification(code: UInt8, payload: Data) {
        guard var handlers = pendingPushResponses[code] else { return }

        logger.info("Received push notification: 0x\(String(format: "%02X", code))")

        // Find matching handler based on payload content
        for (key, continuation) in handlers {
            if isMatchingPush(key: key, payload: payload) {
                continuation.resume(returning: payload)
                handlers.removeValue(forKey: key)
                break
            }
        }

        pendingPushResponses[code] = handlers.isEmpty ? nil : handlers
    }

    private static func isMatchingPush(key: String, payload: Data) -> Bool {
        // Implement matching logic for different push types
        if key.hasPrefix("tag:") {
            // Tag-based matching for trace responses
            let expectedTag = UInt32(key.dropFirst(4), radix: 16) ?? 0
            guard payload.count >= 4 else { return false }
            let receivedTag = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            return receivedTag == expectedTag
        } else if key.hasPrefix("pubkey:") {
            // Public key prefix matching for telemetry/status responses
            let expectedPrefix = Data(hexString: String(key.dropFirst(7)))
            guard payload.count >= expectedPrefix.count else { return false }
            let receivedPrefix = payload.prefix(expectedPrefix.count)
            return receivedPrefix == expectedPrefix
        }
        return false
    }
}
