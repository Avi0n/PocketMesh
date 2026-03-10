import SwiftUI

/// Loading placeholder shown while link preview is being fetched
struct LinkPreviewLoadingCard: View {
    private typealias Strings = L10n.Chats.Chats.Preview
    let url: URL

    private var domain: String {
        url.host ?? url.absoluteString
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.loading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(domain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

#Preview {
    LinkPreviewLoadingCard(url: URL(string: "https://example.com/article")!)
        .padding()
}
