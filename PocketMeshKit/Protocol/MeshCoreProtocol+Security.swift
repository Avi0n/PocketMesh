import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Security")

public extension MeshCoreProtocol {
    // MARK: - Security Features

    /// CMD_EXPORT_PRIVATE_KEY (23): Export device private key
    ///
    /// This command exports the device's private key for backup/migration purposes.
    /// Requires:
    /// - Device running companion radio firmware
    /// - ENABLE_PRIVATE_KEY_EXPORT compile-time flag enabled
    /// - Authenticated BLE connection with PIN
    ///
    /// - Returns: 64-byte private key data or throws if disabled/not supported
    func exportPrivateKey() async throws -> Data {
        let frame = ProtocolFrame(code: CommandCode.exportPrivateKey.rawValue, payload: Data())

        // Send command and wait for one of the expected responses
        let encodedFrame = frame.encode()
        try await bleManager.send(frame: encodedFrame)

        // Wait for response (could be PRIVATE_KEY, DISABLED, or ERROR)
        let response = try await waitForMultiFrameResponse(
            codes: [
                ResponseCode.privateKey.rawValue, // Success - private key data
                ResponseCode.disabled.rawValue, // Feature disabled
                ResponseCode.error.rawValue, // Error occurred
            ],
            timeout: 10.0,
        )

        switch response.code {
        case ResponseCode.privateKey.rawValue:
            // Success - expect exactly 64 bytes of private key data
            guard response.payload.count == 64 else {
                logger.error("Private key response has invalid length: \(response.payload.count) bytes")
                throw ProtocolError.invalidPayload
            }

            logger.info("Private key exported successfully (64 bytes)")
            return response.payload

        case ResponseCode.disabled.rawValue:
            // Feature is disabled on this device
            logger.warning("Private key export is disabled on this device")
            throw SecurityError.privateKeyExportDisabled

        case ResponseCode.error.rawValue:
            // Device reported an error
            let errorMessage = String(data: response.payload, encoding: .utf8) ?? "Unknown error"
            logger.error("Private key export failed: \(errorMessage)")
            throw SecurityError.privateKeyExportFailed(errorMessage)

        default:
            throw ProtocolError.unsupportedCommand
        }
    }
}

// MARK: - Supporting Types

/// Security-related errors
public enum SecurityError: LocalizedError {
    case privateKeyExportDisabled
    case privateKeyExportFailed(String)
    case pinRequired
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .privateKeyExportDisabled:
            "Private key export is disabled on this device. This feature requires companion radio firmware with ENABLE_PRIVATE_KEY_EXPORT=1."
        case let .privateKeyExportFailed(reason):
            "Private key export failed: \(reason)"
        case .pinRequired:
            "PIN authentication is required for this operation"
        case .authenticationFailed:
            "Authentication failed - invalid PIN or insufficient permissions"
        }
    }
}

/// Private key export response information
public struct PrivateKeyExportResult: Sendable {
    public let privateKey: Data
    public let timestamp: Date
    public let deviceModel: String?

    public init(privateKey: Data, timestamp: Date = Date(), deviceModel: String? = nil) {
        self.privateKey = privateKey
        self.timestamp = timestamp
        self.deviceModel = deviceModel
    }

    /// Export private key to file with metadata
    public func exportToURL(_ url: URL) throws {
        var metadata: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "keyFormat": "raw",
            "keyLength": privateKey.count,
        ]

        if let deviceModel {
            metadata["deviceModel"] = deviceModel
        }

        // Create JSON metadata
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)

        // Combine metadata and key data
        var exportData = Data()
        let metadataLength = UInt32(jsonData.count)
        exportData.append(withUnsafeBytes(of: metadataLength.littleEndian) { Data($0) })
        exportData.append(jsonData)
        exportData.append(privateKey)

        try exportData.write(to: url)
    }

    /// Import private key from file
    public static func importFromURL(_ url: URL) throws -> PrivateKeyExportResult {
        let data = try Data(contentsOf: url)
        guard data.count >= 4 else {
            throw SecurityError.privateKeyExportFailed("Invalid export file format")
        }

        // Read metadata length
        let metadataLength = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        guard data.count >= 4 + metadataLength + 64 else {
            throw SecurityError.privateKeyExportFailed("Invalid export file format")
        }

        // Parse metadata
        let metadataData = data.subdata(in: 4 ..< (4 + metadataLength))
        guard let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
            throw SecurityError.privateKeyExportFailed("Invalid metadata format")
        }

        // Extract timestamp
        let timestamp: Date
        if let timestampString = metadata["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else {
            timestamp = Date()
        }

        // Extract device model
        let deviceModel = metadata["deviceModel"] as? String

        // Extract private key
        let privateKeyStart = 4 + metadataLength
        let privateKey = data.subdata(in: privateKeyStart ..< (privateKeyStart + 64))

        guard privateKey.count == 64 else {
            throw SecurityError.privateKeyExportFailed("Invalid private key length")
        }

        return PrivateKeyExportResult(
            privateKey: privateKey,
            timestamp: timestamp,
            deviceModel: deviceModel,
        )
    }
}
