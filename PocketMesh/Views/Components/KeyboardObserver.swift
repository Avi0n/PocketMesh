import SwiftUI
import UIKit

/// Observes keyboard show/hide to provide height for docked keyboards only.
/// Uses both notification type AND geometric validation (WWDC 2023 guidance)
/// to reliably distinguish docked from floating/undocked keyboards.
/// Use with `.ignoresSafeArea(.keyboard)` to disable SwiftUI's automatic avoidance.
@Observable @MainActor
final class KeyboardObserver {
    /// Height to add as bottom padding when keyboard is docked (0 when floating/hidden)
    private(set) var keyboardHeight: CGFloat = 0

    // nonisolated(unsafe) is required because NSObjectProtocol is not Sendable
    // and deinit is nonisolated. Tokens are only set once in setupObservers() on MainActor
    // and read in deinit (which runs after all references are released).
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
        guard isDockedKeyboard(keyboardFrame) else { return }
        let newHeight = calculateKeyboardOverlap(keyboardFrame)
        guard abs(newHeight - keyboardHeight) > 0.5 else { return }
        keyboardHeight = newHeight
    }

    private func handleKeyboardFrameChange(_ keyboardFrame: CGRect) {
        // Only update if keyboard is currently shown (height > 0)
        // This avoids reacting to change notifications during hide transitions
        guard keyboardHeight > 0 else { return }

        // If keyboard moved away from docked position (e.g. undocked/floated),
        // clear the height immediately rather than waiting for keyboardWillHide
        guard isDockedKeyboard(keyboardFrame) else {
            keyboardHeight = 0
            return
        }

        let newHeight = calculateKeyboardOverlap(keyboardFrame)
        guard abs(newHeight - keyboardHeight) > 0.5 else { return }
        keyboardHeight = newHeight
    }

    /// A docked keyboard spans the full screen width and sits at the bottom edge.
    /// Floating/undocked/split keyboards are narrower or positioned elsewhere.
    private func isDockedKeyboard(_ keyboardFrame: CGRect) -> Bool {
        guard let windowScene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive }) else {
            return false
        }
        let screenBounds = windowScene.screen.bounds
        let isAtBottom = keyboardFrame.maxY >= screenBounds.height - 1
        let isFullWidth = keyboardFrame.width >= screenBounds.width - 1
        return isAtBottom && isFullWidth
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

        guard !intersection.isNull else { return 0 }

        // Subtract bottom safe area inset (home indicator) because the input bar
        // is already positioned above it by the safe area system. Without this,
        // the home indicator height is double-counted, creating a visible gap
        // between the input bar and keyboard on iPad.
        let bottomSafeArea = keyWindow.safeAreaInsets.bottom
        return max(0, intersection.height - bottomSafeArea)
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

    /// Manual keyboard avoidance is only needed on iPadOS 26+ where
    /// `.ignoresSafeArea(.keyboard)` correctly suppresses SwiftUI's avoidance.
    /// On iPadOS 18, `.ignoresSafeArea(.keyboard)` leaks through `.safeAreaInset`
    /// (FB11957786), causing double-avoidance. Native SwiftUI avoidance is used instead.
    private var shouldApplyManualAvoidance: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content: Content) -> some View {
        if shouldApplyManualAvoidance {
            content
                .padding(.bottom, keyboardObserver.keyboardHeight)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85),
                    value: keyboardObserver.keyboardHeight
                )
        } else {
            content
        }
    }
}

extension View {
    /// Applies padding for docked keyboards on iPad only.
    /// Use with `.ignoresSafeArea(.keyboard)` on iPad to disable
    /// SwiftUI's automatic keyboard avoidance.
    func floatingKeyboardAware() -> some View {
        modifier(FloatingKeyboardAwareModifier())
    }

    /// Conditionally ignores keyboard safe area on iPad running iPadOS 26+.
    /// On iPadOS 18, `.ignoresSafeArea(.keyboard)` doesn't fully suppress avoidance
    /// when combined with `.safeAreaInset` (FB11957786), so native avoidance is used.
    @ViewBuilder
    func ignoreKeyboardOnIPad() -> some View {
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            self.ignoresSafeArea(.keyboard)
        } else {
            self
        }
    }
}
