import SwiftUI
import PocketMeshServices

struct NotificationLevelPicker: View {
    @Binding var selection: NotificationLevel
    let availableLevels: [NotificationLevel]

    init(selection: Binding<NotificationLevel>, availableLevels: [NotificationLevel] = NotificationLevel.allCases) {
        self._selection = selection
        self.availableLevels = availableLevels
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(availableLevels, id: \.self) { level in
                NotificationLevelPill(
                    level: level,
                    isSelected: selection == level
                ) {
                    selection = level
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification level")
        .accessibilityValue(selection.accessibilityDescription)
        .accessibilityHint("Choose when to receive notifications")
    }
}

private struct NotificationLevelPill: View {
    let level: NotificationLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: level.iconName)
                    .font(.title3)
                Text(level.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
