import Foundation

// MARK: - BLE Connection State

/// Connection state for BLE devices
public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    /// BLE connection established, characteristics discovered.
    /// Device initialization (initializeDevice) may still fail - caller should
    /// disconnect if initialization fails.
    case connected
    /// Device fully initialized and ready for communication.
    case ready
}

// MARK: - BLE Errors

/// Errors that can occur during BLE operations
public enum BLEError: Error, Sendable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deviceNotFound
    case connectionFailed(String)
    case connectionTimeout
    case notConnected
    case characteristicNotFound
    case writeError(String)
    case invalidResponse
    case operationTimeout
    case authenticationFailed
    case authenticationRequired
    case pairingCancelled
    case pairingFailed(String)
}

// MARK: - BLEError LocalizedError Conformance

extension BLEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device."
        case .bluetoothUnauthorized:
            return "Bluetooth permission is required. Please enable it in Settings."
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Please enable Bluetooth to connect."
        case .deviceNotFound:
            return "Device not found. Please make sure it's powered on and nearby."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .notConnected:
            return "Not connected to a device."
        case .characteristicNotFound:
            return "Unable to communicate with device. Please try reconnecting."
        case .writeError(let message):
            return "Failed to send data: \(message)"
        case .invalidResponse:
            return "Invalid response from device. Please try again."
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .authenticationFailed:
            return "Authentication failed. Please check your device's PIN."
        case .authenticationRequired:
            return "Authentication required. Please enter the device PIN when prompted."
        case .pairingCancelled:
            return "Bluetooth pairing was cancelled. Please try again."
        case .pairingFailed(let reason):
            return "Bluetooth pairing failed: \(reason)"
        }
    }
}

// MARK: - Pairing Failure Detection

/// CBATTError codes that indicate pairing/authentication failure
/// These errors mean pairing was cancelled, failed, or never completed
let pairingFailureErrorCodes: Set<Int> = [
    5,   // insufficientAuthentication - pairing required but not completed
    8,   // insufficientAuthorization - authorization failed
    14,  // unlikelyError - peer removed pairing information
    15   // insufficientEncryption - encryption failed
]

/// Checks if an error indicates a BLE pairing failure
/// - Parameter error: The error from a BLE write/read operation
/// - Returns: true if this error indicates pairing failed or was cancelled
func isPairingFailureError(_ error: Error) -> Bool {
    let nsError = error as NSError
    // CBATTErrorDomain errors indicate ATT-level failures
    guard nsError.domain == "CBATTErrorDomain" else { return false }
    return pairingFailureErrorCodes.contains(nsError.code)
}
