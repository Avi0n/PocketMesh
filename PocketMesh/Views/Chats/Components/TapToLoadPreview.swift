import SwiftUI

/// Placeholder shown when auto-resolve is disabled but previews are enabled
struct TapToLoadPreview: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)

                Text("Tap to load preview")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TapToLoadPreview(onTap: {})
        .padding()
}
