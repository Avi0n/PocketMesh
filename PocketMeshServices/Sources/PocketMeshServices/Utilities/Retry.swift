import Foundation

/// Error thrown when retry attempts are exhausted without capturing an error
public enum RetryError: Error, Sendable {
    case exhaustedWithoutError
}

/// Retries an async operation with exponential backoff.
///
/// Messages are deleted from device RAM after BLE transfer, so retry is critical
/// to prevent message loss during transient persistence failures.
///
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default: 3)
///   - operation: The async throwing operation to retry
/// - Returns: The result of the successful operation
/// - Throws: The last error encountered, or `RetryError.exhaustedWithoutError`
public func withRetry<T: Sendable>(
    maxAttempts: Int = 3,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                // Exponential backoff: 100ms, 200ms, 300ms...
                try? await Task.sleep(for: .milliseconds(100 * attempt))
            }
        }
    }

    throw lastError ?? RetryError.exhaustedWithoutError
}
