import SwiftUI

struct NodeSegmentPicker: View {
    @Binding var selection: NodeSegment
    let isSearching: Bool

    var body: some View {
        Picker(L10n.Contacts.Contacts.Segment.contacts, selection: $selection) {
            ForEach(NodeSegment.allCases, id: \.self) { segment in
                Text(segment.localizedTitle).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .opacity(isSearching ? 0.5 : 1.0)
        .disabled(isSearching)
    }
}
