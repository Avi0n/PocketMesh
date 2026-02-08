import Foundation
import MeshCore

// MARK: - WiFiTransportError LocalizedError Conformance

extension WiFiTransportError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            "Connection failed: \(reason)"
        case .connectionTimeout:
            "Connection timed out. Check the IP address and ensure the device is on the same network."
        case .notConnected:
            "Not connected to device."
        case .sendFailed(let reason):
            "Failed to send data: \(reason)"
        case .sendTimeout:
            "Send operation timed out."
        case .invalidHost:
            "Invalid IP address."
        case .invalidPort:
            "Invalid port number."
        case .notConfigured:
            "Connection not configured."
        }
    }
}
