import Foundation

// MARK: - Timeout Error

/// Error thrown when an async operation exceeds its timeout.
public struct TimeoutError: Error, LocalizedError, Sendable {
    public let operationName: String
    public let timeout: Duration

    public var errorDescription: String? {
        "Operation '\(operationName)' timed out after \(timeout)"
    }
}

// MARK: - Timeout Helper

/// Races an async operation against a deadline using structured concurrency.
/// When the timeout fires, the operation task is cancelled via `group.cancelAll()`.
/// When the operation completes first, the sleep task is cancelled.
public func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operationName: String = #function,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            // Use SuspendingClock so timeouts pause while the app is suspended by iOS.
            // All current callers wrap BLE operations that should not time out during
            // suspension. If a future caller needs wall-clock timeout, use
            // Task.sleep(for:clock: .continuous) directly in a task group.
            try await Task.sleep(for: timeout, clock: .suspending)
            throw TimeoutError(operationName: operationName, timeout: timeout)
        }

        // First task to complete wins
        guard let result = try await group.next() else {
            throw TimeoutError(operationName: operationName, timeout: timeout)
        }
        group.cancelAll()
        return result
    }
}
