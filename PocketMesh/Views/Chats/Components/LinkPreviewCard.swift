import SwiftUI
import TipKit
import PocketMeshServices

/// Displays a link preview with image, title, and domain
struct LinkPreviewCard: View {
    let url: URL
    let title: String?
    let imageData: Data?
    let iconData: Data?
    let onTap: () -> Void

    private var domain: String {
        url.host ?? url.absoluteString
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image (if available)
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 150)
                        .clipped()
                }

                // Title and domain
                HStack(spacing: 8) {
                    // Icon or globe fallback
                    if let iconData, let uiImage = UIImage(data: iconData) {
                        Image(uiImage: uiImage)
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
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }

                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(10)
            }
            .background(Color(.systemGray6))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task {
            await LinkPreviewPrivacyTip.previewLoaded.donate()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title ?? domain), from \(domain), link")
        .accessibilityHint("Opens in browser")
    }
}

#Preview("With Image") {
    LinkPreviewCard(
        url: URL(string: "https://apple.com/iphone")!,
        title: "iPhone 16 Pro - Apple",
        imageData: nil,
        iconData: nil,
        onTap: {}
    )
    .padding()
}

#Preview("Without Image") {
    LinkPreviewCard(
        url: URL(string: "https://example.com/article")!,
        title: "An Interesting Article About Technology",
        imageData: nil,
        iconData: nil,
        onTap: {}
    )
    .padding()
}
