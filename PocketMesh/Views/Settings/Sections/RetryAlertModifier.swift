import SwiftUI
import PocketMeshKit

/// Maximum number of retries before showing final error
private let maxRetries = 3

/// State container for retry alert with retry counting
@Observable
@MainActor
final class RetryAlertState {
    var isPresented: Bool = false
    var message: String = ""
    var retryCount: Int = 0
    var onRetry: (() -> Void)?
    var onMaxRetriesExceeded: (() -> Void)?

    /// Show a retry alert, incrementing the retry count
    func show(message: String, onRetry: @escaping () -> Void, onMaxRetriesExceeded: @escaping () -> Void) {
        self.retryCount += 1
        self.message = message
        self.onRetry = onRetry
        self.onMaxRetriesExceeded = onMaxRetriesExceeded
        self.isPresented = true
    }

    /// Reset retry count (call when operation succeeds or user cancels)
    func reset() {
        retryCount = 0
        onRetry = nil
        onMaxRetriesExceeded = nil
    }

    /// Whether max retries have been exceeded
    var isMaxRetriesExceeded: Bool {
        retryCount >= maxRetries
    }
}

/// ViewModifier for presenting retry alerts with retry counting
struct RetryAlertModifier: ViewModifier {
    @Bindable var state: RetryAlertState

    func body(content: Content) -> some View {
        content
            .alert(
                state.isMaxRetriesExceeded ? "Unable to Save Setting" : "Connection Error",
                isPresented: $state.isPresented
            ) {
                if state.isMaxRetriesExceeded {
                    Button("OK") {
                        state.onMaxRetriesExceeded?()
                        state.reset()
                    }
                } else {
                    Button("Retry") {
                        state.onRetry?()
                    }
                    Button("Cancel", role: .cancel) {
                        state.reset()
                    }
                }
            } message: {
                if state.isMaxRetriesExceeded {
                    Text("Please ensure your device is connected.")
                } else {
                    Text(state.message)
                }
            }
    }
}

extension View {
    func retryAlert(_ state: RetryAlertState) -> some View {
        modifier(RetryAlertModifier(state: state))
    }
}
