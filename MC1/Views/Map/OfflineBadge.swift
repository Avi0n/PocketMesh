import SwiftUI

// MARK: - Offline Badge

struct OfflineBadge: View {
    var body: some View {
        VStack {
            HStack {
                Text(L10n.Map.Map.OfflineBadge.label)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: .capsule)
                Spacer()
            }
            .padding(.leading)
            Spacer()
        }
    }
}
