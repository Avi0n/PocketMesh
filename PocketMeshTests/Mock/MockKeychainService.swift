import Foundation
@testable import PocketMeshServices

/// Mock keychain service for testing remote node authentication
public actor MockKeychainService: KeychainServiceProtocol {
    private var storage: [Data: String] = [:]

    public init() {}

    public func storePassword(_ password: String, forNodeKey publicKey: Data) async throws {
        storage[publicKey] = password
    }

    public func retrievePassword(forNodeKey publicKey: Data) async throws -> String? {
        storage[publicKey]
    }

    public func deletePassword(forNodeKey publicKey: Data) async throws {
        storage.removeValue(forKey: publicKey)
    }

    public func hasPassword(forNodeKey publicKey: Data) async -> Bool {
        storage[publicKey] != nil
    }

    // MARK: - Test Helpers

    /// Get all stored passwords for verification
    public func getAllStoredKeys() -> [Data] {
        Array(storage.keys)
    }

    /// Clear all stored passwords
    public func clear() {
        storage.removeAll()
    }
}
