import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "PushRegistry")

extension MeshCoreProtocol {
    // MARK: - Push Response Registry

    /// Register a pending push notification response
    func registerPendingPushForPushNotification(
        code: UInt8,
        key: String,
        continuation: CheckedContinuation<Data, Error>,
    ) {
        registerPendingPush(code: code, key: key, continuation: continuation)
    }

    /// Handle incoming push notification and match with pending requests
    func handlePushNotification(code: UInt8, payload: Data) {
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

    private func isMatchingPush(key: String, payload: Data) -> Bool {
        // Helper function to convert hex string to Data using PathDiscovery implementation
        func hexToData(_ hex: String) -> Data? {
            let string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard string.count % 2 == 0 else { return nil }

            var data = Data()
            var index = string.startIndex

            while index < string.endIndex {
                let nextIndex = string.index(index, offsetBy: 2)
                let byteString = string[index ..< nextIndex]
                guard let byte = UInt8(byteString, radix: 16) else { return nil }
                data.append(byte)
                index = nextIndex
            }

            return data
        }

        // Implement matching logic for different push types
        if key.hasPrefix("tag:") {
            // Tag-based matching for trace responses
            let keyString = String(key)
            let startIndex = keyString.index(keyString.startIndex, offsetBy: 4)
            let expectedTag = UInt32(String(keyString[startIndex...]), radix: 16) ?? 0
            guard payload.count >= 4 else { return false }
            let receivedTag = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            return receivedTag == expectedTag
        } else if key.hasPrefix("pubkey:") {
            // Public key prefix matching for telemetry/status responses
            let keyString = String(key)
            let startIndex = keyString.index(keyString.startIndex, offsetBy: 7)
            guard let expectedPrefix = hexToData(String(keyString[startIndex...])) else { return false }
            guard payload.count >= expectedPrefix.count else { return false }
            let receivedPrefix = payload.prefix(expectedPrefix.count)
            return receivedPrefix == expectedPrefix
        } else if key.hasPrefix("ack:") {
            // ACK code matching for send confirmations
            let keyString = String(key)
            let startIndex = keyString.index(keyString.startIndex, offsetBy: 4)
            let expectedAckHex = String(keyString[startIndex...])
            guard let expectedAck = hexToData(expectedAckHex) else { return false }
            guard payload.count >= expectedAck.count else { return false }
            let receivedAck = payload.prefix(expectedAck.count)
            return receivedAck == expectedAck
        }
        return false
    }
}
