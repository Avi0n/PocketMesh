import SwiftUI
import Combine

/// A view modifier that displays a toolbar above the keyboard using safeAreaInset.
/// This works around the known SwiftUI bug where .toolbar(placement: .keyboard) fails to appear.
private struct KeyboardToolbarModifier<Toolbar: View>: ViewModifier {
    @State private var isKeyboardVisible = false
    private let toolbar: Toolbar

    init(@ViewBuilder toolbar: () -> Toolbar) {
        self.toolbar = toolbar()
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isKeyboardVisible {
                    toolbar
                        .background(.bar)
                }
            }
            .onReceive(keyboardWillShow) { _ in
                withAnimation(.easeInOut(duration: 0.16)) {
                    isKeyboardVisible = true
                }
            }
            .onReceive(keyboardWillHide) { _ in
                withAnimation(.easeInOut(duration: 0.16)) {
                    isKeyboardVisible = false
                }
            }
    }

    private var keyboardWillShow: AnyPublisher<Notification, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .eraseToAnyPublisher()
    }

    private var keyboardWillHide: AnyPublisher<Notification, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .eraseToAnyPublisher()
    }
}

extension View {
    /// Adds a toolbar that appears above the keyboard when it's visible.
    /// Use this instead of .toolbar(placement: .keyboard) which has known bugs.
    func keyboardToolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        modifier(KeyboardToolbarModifier(toolbar: content))
    }

    /// Adds a "Done" button toolbar above the keyboard that dismisses focus.
    func keyboardDoneButton(action: @escaping () -> Void) -> some View {
        keyboardToolbar {
            HStack {
                Spacer()
                Button("Done", action: action)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}
