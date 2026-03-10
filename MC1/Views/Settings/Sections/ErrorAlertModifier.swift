import SwiftUI

/// ViewModifier for presenting error alerts with proper state binding
struct ErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?

    private var isPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(L10n.Settings.Alert.Error.title, isPresented: isPresented) {
                Button(L10n.Localizable.Common.ok) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension View {
    func errorAlert(_ errorMessage: Binding<String?>) -> some View {
        modifier(ErrorAlertModifier(errorMessage: errorMessage))
    }
}
