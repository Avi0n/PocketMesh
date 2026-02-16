import SwiftUI
import TipKit

/// Tip style matching the default appearance but without the close button.
/// Used for tips on Menu views where the close button's tap is intercepted.
struct NoCloseButtonTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.image?
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                configuration.title?
                    .font(.headline)
                configuration.message?
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
