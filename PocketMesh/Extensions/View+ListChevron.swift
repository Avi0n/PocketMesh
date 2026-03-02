import SwiftUI

extension View {
    /// Adds a trailing chevron aligned with the top row of a list item.
    /// Used with hidden NavigationLink pattern to control chevron positioning.
    func listChevron(offset: CGFloat = -8) -> some View {
        HStack(spacing: 12) {
            self
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .offset(y: offset)
        }
    }
}
