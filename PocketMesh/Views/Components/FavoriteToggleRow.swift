import SwiftUI

struct FavoriteToggleRow: View {
    @Binding var isFavorite: Bool

    var body: some View {
        HStack {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? .yellow : .secondary)

            Text("Favorite")

            Spacer()

            Toggle("", isOn: $isFavorite)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Favorite")
        .accessibilityValue(isFavorite ? "On" : "Off")
    }
}
