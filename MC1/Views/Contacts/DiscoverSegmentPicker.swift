import SwiftUI

struct DiscoverSegmentPicker: View {
    @Binding var selection: DiscoverSegment
    let isSearching: Bool

    var body: some View {
        Picker(L10n.Contacts.Contacts.Discovery.Segment.all, selection: $selection) {
            ForEach(DiscoverSegment.allCases, id: \.self) { segment in
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
