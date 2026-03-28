import SwiftUI

struct LabelsToggleButton: View {
    @Binding var showLabels: Bool

    var body: some View {
        Button(showLabels ? L10n.Map.Map.Controls.hideLabels : L10n.Map.Map.Controls.showLabels, systemImage: "character.textbox") {
            withAnimation {
                showLabels.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(showLabels ? .blue : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}
