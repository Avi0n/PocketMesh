import Foundation

/// Manages app-side trusted contacts for telemetry filtering
@MainActor
@Observable
public final class TrustedContactsManager {
    private let userDefaultsKey = "trustedContactPublicKeys"

    /// Set of public key prefixes (hex strings) for trusted contacts
    public private(set) var trustedPublicKeyPrefixes: Set<String> = []

    /// Whether to filter telemetry by trusted contacts
    public var filterByTrustedContacts: Bool = false {
        didSet {
            UserDefaults.standard.set(filterByTrustedContacts, forKey: "filterTelemetryByTrustedContacts")
        }
    }

    public init() {
        loadFromDefaults()
    }

    private func loadFromDefaults() {
        if let stored = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
            trustedPublicKeyPrefixes = Set(stored)
        }
        filterByTrustedContacts = UserDefaults.standard.bool(forKey: "filterTelemetryByTrustedContacts")
    }

    private func saveToDefaults() {
        UserDefaults.standard.set(Array(trustedPublicKeyPrefixes), forKey: userDefaultsKey)
    }

    /// Add a contact to trusted list
    public func addTrusted(publicKeyPrefix: Data) {
        let hex = publicKeyPrefix.map { String(format: "%02X", $0) }.joined()
        trustedPublicKeyPrefixes.insert(hex)
        saveToDefaults()
    }

    /// Remove a contact from trusted list
    public func removeTrusted(publicKeyPrefix: Data) {
        let hex = publicKeyPrefix.map { String(format: "%02X", $0) }.joined()
        trustedPublicKeyPrefixes.remove(hex)
        saveToDefaults()
    }

    /// Check if a contact is trusted
    public func isTrusted(publicKeyPrefix: Data) -> Bool {
        let hex = publicKeyPrefix.map { String(format: "%02X", $0) }.joined()
        return trustedPublicKeyPrefixes.contains(hex)
    }

    /// Clear all trusted contacts
    public func clearAll() {
        trustedPublicKeyPrefixes.removeAll()
        saveToDefaults()
    }
}
