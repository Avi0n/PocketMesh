import SwiftUI

// MARK: - Keyboard-Aware Scroll Edge Effect

extension View {
    @ViewBuilder
    func keyboardAwareScrollEdgeEffect(isFocused: Bool) -> some View {
        if #available(iOS 26.0, *) {
            // When keyboard is visible (focused), use hard edge - content doesn't scroll behind
            // When keyboard is hidden, use soft edge - content scrolls beneath with blur
            self.scrollEdgeEffectStyle(isFocused ? .hard : .soft, for: .bottom)
        } else {
            self
        }
    }
}
