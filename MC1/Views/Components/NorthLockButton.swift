import SwiftUI

struct NorthLockButton: View {
    @Binding var isNorthLocked: Bool

    var body: some View {
        Button(
            isNorthLocked ? L10n.Map.Map.Controls.unlockNorth : L10n.Map.Map.Controls.lockNorth,
            systemImage: isNorthLocked ? "location.north.line.fill" : "location.north.line"
        ) {
            withAnimation {
                isNorthLocked.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(isNorthLocked ? .blue : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}
