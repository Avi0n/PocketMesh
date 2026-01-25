import SwiftUI
import UIKit

/// Observes keyboard show/hide to provide height for docked keyboards only.
/// Key insight: iOS sends `keyboardWillHide` for floating/undocked keyboards,
/// so we only get `keyboardWillShow` for docked keyboards.
/// Use with `.ignoresSafeArea(.keyboard)` to disable SwiftUI's automatic avoidance.
@Observable @MainActor
final class KeyboardObserver {
    /// Height to add as bottom padding when keyboard is docked (0 when floating/hidden)
    private(set) var keyboardHeight: CGFloat = 0

    nonisolated(unsafe) private var showToken: (any NSObjectProtocol)?
    nonisolated(unsafe) private var hideToken: (any NSObjectProtocol)?
    nonisolated(unsafe) private var changeToken: (any NSObjectProtocol)?

    init() {
        setupObservers()
    }

    deinit {
        if let token = showToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = hideToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = changeToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupObservers() {
        // keyboardWillShow is only sent for docked keyboards
        // Floating/undocked keyboards send keyboardWillHide instead
        showToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            Task { @MainActor in
                self?.handleKeyboardShow(keyboardFrame)
            }
        }

        hideToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleKeyboardHide()
            }
        }

        // Handle keyboard size changes while visible (QuickType, keyboard switches, dictation)
        changeToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            Task { @MainActor in
                self?.handleKeyboardFrameChange(keyboardFrame)
            }
        }
    }

    private func handleKeyboardShow(_ keyboardFrame: CGRect) {
        let newHeight = calculateKeyboardOverlap(keyboardFrame)
        guard abs(newHeight - keyboardHeight) > 0.5 else { return }
        keyboardHeight = newHeight
    }

    private func handleKeyboardFrameChange(_ keyboardFrame: CGRect) {
        // Only update if keyboard is currently shown (height > 0)
        // This avoids reacting to change notifications during hide transitions
        guard keyboardHeight > 0 else { return }

        let newHeight = calculateKeyboardOverlap(keyboardFrame)
        guard abs(newHeight - keyboardHeight) > 0.5 else { return }
        keyboardHeight = newHeight
    }

    /// Calculates actual keyboard overlap with the key window
    private func calculateKeyboardOverlap(_ keyboardFrame: CGRect) -> CGFloat {
        // Find the key window - the one actually receiving input
        guard let keyWindow = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })?
                  .keyWindow else {
            return 0
        }

        // Convert keyboard frame from screen coordinates to window coordinates
        let keyboardInWindow = keyWindow.convert(keyboardFrame, from: nil)

        // Calculate actual overlap between keyboard and window bounds
        let windowBounds = keyWindow.bounds
        let intersection = windowBounds.intersection(keyboardInWindow)

        // Return overlap height, or 0 if no overlap
        return intersection.isNull ? 0 : intersection.height
    }

    private func handleKeyboardHide() {
        guard keyboardHeight > 0 else { return }
        keyboardHeight = 0
    }
}

// MARK: - View Modifier

struct FloatingKeyboardAwareModifier: ViewModifier {
    @Environment(KeyboardObserver.self) private var keyboardObserver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content: Content) -> some View {
        content
            .padding(.bottom, isIPad ? keyboardObserver.keyboardHeight : 0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85),
                value: keyboardObserver.keyboardHeight
            )
    }
}

extension View {
    /// Applies padding for docked keyboards on iPad only.
    /// Use with `.ignoresSafeArea(.keyboard)` on iPad to disable
    /// SwiftUI's automatic keyboard avoidance.
    func floatingKeyboardAware() -> some View {
        modifier(FloatingKeyboardAwareModifier())
    }

    /// Conditionally ignores keyboard safe area on iPad only.
    /// iPhone uses SwiftUI's default keyboard avoidance.
    @ViewBuilder
    func ignoreKeyboardOnIPad() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.ignoresSafeArea(.keyboard)
        } else {
            self
        }
    }
}
