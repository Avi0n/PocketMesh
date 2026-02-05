// ConnectionIntent.swift

import Foundation

/// Represents the user's connection intent, replacing three separate flags:
/// `shouldBeConnected`, `userExplicitlyDisconnected`, and `pendingForceFullSync`.
public enum ConnectionIntent: Sendable, Equatable {

    /// No active connection intent (initial state)
    case none

    /// User explicitly disconnected — suppress auto-reconnect and disconnected pill
    case userDisconnected

    /// User wants to be connected
    case wantsConnection(forceFullSync: Bool = false)

    // MARK: - Persistence

    private static let persistenceKey = "com.pocketmesh.userExplicitlyDisconnected"

    /// Persists the `userDisconnected` state to UserDefaults.
    /// Only `.userDisconnected` is persisted; other states are transient.
    func persist() {
        switch self {
        case .userDisconnected:
            UserDefaults.standard.set(true, forKey: Self.persistenceKey)
        case .none, .wantsConnection:
            UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        }
    }

    /// Restores intent from UserDefaults on launch.
    /// Returns `.userDisconnected` if persisted, otherwise `.none`.
    static func restored() -> ConnectionIntent {
        if UserDefaults.standard.bool(forKey: persistenceKey) {
            return .userDisconnected
        }
        return .none
    }

    // MARK: - Convenience

    /// Whether the user wants to be connected
    var wantsConnection: Bool {
        if case .wantsConnection = self { return true }
        return false
    }

    /// Whether the user explicitly disconnected
    var isUserDisconnected: Bool {
        self == .userDisconnected
    }
}
