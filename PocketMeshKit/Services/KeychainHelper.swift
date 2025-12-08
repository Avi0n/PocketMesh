import Foundation
import Security

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, Sendable {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
}

/// Helper for securely storing device PINs in iOS Keychain
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let service = "com.pocketmesh.devicepin"

    private init() {}

    /// Saves a PIN for a device UUID
    /// - Parameters:
    ///   - pin: The 6-digit PIN string
    ///   - deviceUUID: The device's UUID
    public func savePIN(_ pin: String, forDeviceUUID deviceUUID: UUID) throws {
        guard let pinData = pin.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceUUID.uuidString,
            kSecValueData as String: pinData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it instead
            try updatePIN(pin, forDeviceUUID: deviceUUID)
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieves the PIN for a device UUID
    /// - Parameter deviceUUID: The device's UUID
    /// - Returns: The stored PIN, or nil if not found
    public func retrievePIN(forDeviceUUID deviceUUID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceUUID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let pinData = result as? Data,
              let pin = String(data: pinData, encoding: .utf8) else {
            return nil
        }

        return pin
    }

    /// Updates the PIN for a device UUID
    private func updatePIN(_ newPIN: String, forDeviceUUID deviceUUID: UUID) throws {
        guard let pinData = newPIN.data(using: .utf8) else {
            throw KeychainError.invalidItemFormat
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceUUID.uuidString
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: pinData
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes the PIN for a device UUID
    /// - Parameter deviceUUID: The device's UUID
    public func deletePIN(forDeviceUUID deviceUUID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceUUID.uuidString
        ]

        SecItemDelete(query as CFDictionary)
        // Ignore status - we don't care if item didn't exist
    }

    /// Checks if a PIN is stored for a device
    /// - Parameter deviceUUID: The device's UUID
    /// - Returns: True if a PIN is stored
    public func hasPIN(forDeviceUUID deviceUUID: UUID) -> Bool {
        retrievePIN(forDeviceUUID: deviceUUID) != nil
    }
}
