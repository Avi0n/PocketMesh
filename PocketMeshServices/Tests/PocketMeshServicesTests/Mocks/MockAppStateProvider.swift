import Foundation
@testable import PocketMeshServices

/// Mock implementation of AppStateProvider for testing.
/// Uses actor for thread-safe mutable state access.
public actor MockAppStateProvider: AppStateProvider {

    /// Configurable foreground state for tests
    private var _isInForeground: Bool

    public var isInForeground: Bool {
        get async { _isInForeground }
    }

    public init(isInForeground: Bool = true) {
        self._isInForeground = isInForeground
    }

    /// Set foreground state (for test configuration)
    public func setForeground(_ value: Bool) {
        _isInForeground = value
    }
}
