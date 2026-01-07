import SwiftUI

/// Placeholder shown when auto-resolve is disabled but previews are enabled
struct TapToLoadPreview: View {
    let url: URL
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                }

                Text(isLoading ? "Loading preview..." : "Tap to load preview")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading preview for \(url.host ?? "link")" : "Load preview for \(url.host ?? "link")")
        .accessibilityHint(isLoading ? "Please wait" : "Fetches title and image from the website")
    }
}

#Preview("Idle") {
    TapToLoadPreview(url: URL(string: "https://example.com")!, isLoading: false, onTap: {})
        .padding()
}

#Preview("Loading") {
    TapToLoadPreview(url: URL(string: "https://example.com")!, isLoading: true, onTap: {})
        .padding()
}
