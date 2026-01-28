import SwiftUI
import UIKit

/// Invisible UITextView that captures keyboard input while allowing visual rendering elsewhere.
/// Tracks cursor position and supports cursor movement via callbacks.
struct HiddenTextViewFocusable: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var cursorPosition: Int
    var onSubmit: () -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void

    func makeUIView(context: Context) -> FocusableTextView {
        let textView = FocusableTextView()
        textView.customDelegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.returnKeyType = .default

        // Make invisible but still interactive
        textView.backgroundColor = .clear
        textView.textColor = .clear
        textView.tintColor = .clear

        return textView
    }

    func updateUIView(_ textView: FocusableTextView, context: Context) {
        // Update text if changed externally
        if textView.text != text {
            textView.text = text
        }

        // Sync cursor position from SwiftUI to UITextView
        let clampedPosition = min(cursorPosition, textView.text.count)
        if let startPosition = textView.position(from: textView.beginningOfDocument, offset: clampedPosition) {
            let currentOffset = textView.selectedTextRange.map {
                textView.offset(from: textView.beginningOfDocument, to: $0.start)
            } ?? 0

            if currentOffset != clampedPosition {
                textView.selectedTextRange = textView.textRange(from: startPosition, to: startPosition)
            }
        }

        // Manage focus
        if isFocused && !textView.isFirstResponder {
            Task { @MainActor in
                textView.becomeFirstResponder()
            }
        } else if !isFocused && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            cursorPosition: $cursorPosition,
            onSubmit: onSubmit,
            onHistoryUp: onHistoryUp,
            onHistoryDown: onHistoryDown
        )
    }

    class Coordinator: NSObject, FocusableTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var cursorPosition: Int
        let onSubmit: () -> Void
        let onHistoryUp: () -> Void
        let onHistoryDown: () -> Void

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            cursorPosition: Binding<Int>,
            onSubmit: @escaping () -> Void,
            onHistoryUp: @escaping () -> Void,
            onHistoryDown: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            _cursorPosition = cursorPosition
            self.onSubmit = onSubmit
            self.onHistoryUp = onHistoryUp
            self.onHistoryDown = onHistoryDown
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView.text.contains("\n") {
                textView.text = ""
                Task { @MainActor in
                    // Call onSubmit first while tab selection state is still valid
                    // The handler will either apply a suggestion or execute the command
                    self.onSubmit()
                    self.cursorPosition = self.text.count
                }
            } else {
                text = textView.text
                updateCursorPosition(from: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateCursorPosition(from: textView)
        }

        private func updateCursorPosition(from textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else {
                cursorPosition = text.count
                return
            }
            cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            Task { @MainActor in
                self.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            Task { @MainActor in
                self.isFocused = false
            }
        }

        func historyUp() {
            onHistoryUp()
        }

        func historyDown() {
            onHistoryDown()
        }

        func moveCursor(by offset: Int, in textView: FocusableTextView) {
            guard let selectedRange = textView.selectedTextRange else { return }
            guard let newPosition = textView.position(from: selectedRange.start, offset: offset) else { return }
            textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
        }

        func moveCursorToEnd(in textView: FocusableTextView) {
            guard let endPosition = textView.position(from: textView.endOfDocument, offset: 0) else { return }
            textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
        }
    }
}

// MARK: - Custom UITextView with Key Commands

protocol FocusableTextViewDelegate: UITextViewDelegate {
    func historyUp()
    func historyDown()
    func moveCursor(by offset: Int, in textView: FocusableTextView)
    func moveCursorToEnd(in textView: FocusableTextView)
}

class FocusableTextView: UITextView {
    weak var customDelegate: FocusableTextViewDelegate? {
        didSet { delegate = customDelegate }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUpArrow)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDownArrow))
        ]
        // Note: Left/right arrows not intercepted - let UITextView handle them natively
    }

    @objc private func handleUpArrow() {
        customDelegate?.historyUp()
    }

    @objc private func handleDownArrow() {
        customDelegate?.historyDown()
    }

    // Public methods for programmatic cursor movement (called from accessory bar buttons)
    func moveCursorLeft() {
        customDelegate?.moveCursor(by: -1, in: self)
    }

    func moveCursorRight() {
        customDelegate?.moveCursor(by: 1, in: self)
    }

    func moveCursorToEnd() {
        customDelegate?.moveCursorToEnd(in: self)
    }
}
