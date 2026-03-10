import SwiftUI
import PocketMeshServices

/// Displays a link preview with image, title, and domain
struct LinkPreviewCard: View {
    let url: URL
    let title: String?
    let image: UIImage?
    let icon: UIImage?
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var domain: String {
        url.host ?? url.absoluteString
    }

    /// Allow more lines for larger accessibility text sizes
    private var titleLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    private var domainLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image (if available)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 150)
                        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
                }

                // Title and domain
                HStack(spacing: 8) {
                    // Icon or globe fallback
                    if let icon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(.rect(cornerRadius: 4))
                    } else {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.subheadline)
                                .bold()
                                .lineLimit(titleLineLimit)
                                .foregroundStyle(.primary)
                        }

                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(domainLineLimit)
                    }

                    Spacer()
                }
                .padding(10)
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Chats.Chats.LinkPreview.Accessibility.label(title ?? domain, domain))
        .accessibilityHint(L10n.Chats.Chats.LinkPreview.Accessibility.hint)
    }
}

#Preview("With Image") {
    LinkPreviewCard(
        url: URL(string: "https://apple.com/iphone")!,
        title: "iPhone 16 Pro - Apple",
        image: nil,
        icon: nil,
        onTap: {}
    )
    .padding()
}

#Preview("Without Image") {
    LinkPreviewCard(
        url: URL(string: "https://example.com/article")!,
        title: "An Interesting Article About Technology",
        image: nil,
        icon: nil,
        onTap: {}
    )
    .padding()
}
