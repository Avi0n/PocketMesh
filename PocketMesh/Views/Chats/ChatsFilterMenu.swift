import SwiftUI

struct ChatsFilterMenu: View {
    @Binding var selectedFilter: ChatFilter?

    var body: some View {
        let filterIcon = selectedFilter == nil
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
        let accessibilityLabel = selectedFilter.map { L10n.Chats.Chats.Filter.accessibilityLabelActive($0.localizedName) }
            ?? L10n.Chats.Chats.Filter.accessibilityLabel

        Menu {
            Picker(L10n.Chats.Chats.Filter.title, selection: $selectedFilter) {
                Text(L10n.Chats.Chats.Filter.all).tag(nil as ChatFilter?)
                ForEach(ChatFilter.allCases) { filter in
                    Label(filter.localizedName, systemImage: filter.systemImage)
                        .tag(filter as ChatFilter?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            if selectedFilter == nil {
                Label(L10n.Chats.Chats.Filter.title, systemImage: filterIcon)
                    .accessibilityLabel(accessibilityLabel)
            } else {
                Label(L10n.Chats.Chats.Filter.title, systemImage: filterIcon)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
    }
}
