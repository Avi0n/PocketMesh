import Foundation
import Security

public actor PasswordManager {
    public init() {}

    /// Store password for contact in Keychain
    public func storePassword(_ password: String, for publicKey: Data) throws {
        let key = "com.pocketmesh.password.\(publicKey.hexString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: password.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasswordError.storeFailed
        }
    }

    /// Retrieve password for contact from Keychain
    public func getPassword(for publicKey: Data) throws -> String? {
        let key = "com.pocketmesh.password.\(publicKey.hexString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete stored password
    public func deletePassword(for publicKey: Data) throws {
        let key = "com.pocketmesh.password.\(publicKey.hexString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

public enum PasswordError: LocalizedError {
    case storeFailed
    case retrievalFailed

    public var errorDescription: String? {
        switch self {
        case .storeFailed: "Failed to store password securely"
        case .retrievalFailed: "Failed to retrieve password"
        }
    }
}
