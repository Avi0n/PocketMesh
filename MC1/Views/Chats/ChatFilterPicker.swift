import SwiftUI

struct ChatFilterPicker: View {
    @Binding var selection: ChatFilter
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        Picker(L10n.Chats.Chats.Filter.title, selection: $selection) {
            ForEach(ChatFilter.allCases, id: \.self) { filter in
                Text(filter.localizedName).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .opacity(isSearching ? 0.5 : 1.0)
        .disabled(isSearching)
    }
}
