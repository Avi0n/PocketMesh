import SwiftUI
import PocketMeshServices

struct ConversationQuickActionsSection: View {
    @Binding var notificationLevel: NotificationLevel
    @Binding var isFavorite: Bool
    let availableLevels: [NotificationLevel]

    init(
        notificationLevel: Binding<NotificationLevel>,
        isFavorite: Binding<Bool>,
        availableLevels: [NotificationLevel] = NotificationLevel.allCases
    ) {
        self._notificationLevel = notificationLevel
        self._isFavorite = isFavorite
        self.availableLevels = availableLevels
    }

    var body: some View {
        Section {
            VStack(spacing: 16) {
                NotificationLevelPicker(selection: $notificationLevel, availableLevels: availableLevels)

                FavoriteToggleRow(isFavorite: $isFavorite)
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }
}
