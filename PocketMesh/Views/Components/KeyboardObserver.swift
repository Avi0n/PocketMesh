import SwiftUI
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "KeyboardObserver")

/// Observes keyboard frame changes and provides a correction value for undocked keyboards.
/// SwiftUI's automatic keyboard avoidance doesn't handle iPad's floating/undocked/split keyboards,
/// so this observer detects when the keyboard is undocked and publishes a correction value.
@Observable @MainActor
final class KeyboardObserver {
    private(set) var bottomCorrection: CGFloat = 0
    nonisolated(unsafe) private var observerToken: (any NSObjectProtocol)?

    init() {
        setupObservers()
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupObservers() {
        observerToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract values before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            Task { @MainActor in
                self?.handleKeyboardFrameChange(keyboardFrame)
            }
        }
    }

    private func handleKeyboardFrameChange(_ keyboardFrame: CGRect) {
        guard let window = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first?.windows.first else {
            return
        }

        let windowBounds = window.bounds

        // Keyboard is undocked if:
        // - Its bottom edge doesn't reach the window bottom (floating/undocked)
        // - OR its width doesn't span the full window (split keyboard)
        let isUndocked = keyboardFrame.maxY < windowBounds.height - 1
            || keyboardFrame.width < windowBounds.width - 1

        let newCorrection = isUndocked ? -keyboardFrame.height : 0

        // Avoid redundant updates
        guard abs(newCorrection - bottomCorrection) > 0.5 else { return }

        logger.debug("Keyboard state: undocked=\(isUndocked), correction=\(newCorrection)")
        bottomCorrection = newCorrection
    }
}

/// View modifier that applies keyboard correction for undocked iPad keyboards.
struct FloatingKeyboardAwareModifier: ViewModifier {
    @Environment(KeyboardObserver.self) private var keyboardObserver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardObserver.bottomCorrection)
            .animation(
                reduceMotion
                    ? .none
                    : .spring(response: 0.25, dampingFraction: 0.85),
                value: keyboardObserver.bottomCorrection
            )
    }
}

extension View {
    /// Applies correction for iPad's floating/undocked/split keyboard.
    /// Use on views positioned with `.safeAreaInset(edge: .bottom)` that need
    /// to move down when the keyboard undocks.
    func floatingKeyboardAware() -> some View {
        modifier(FloatingKeyboardAwareModifier())
    }
}
