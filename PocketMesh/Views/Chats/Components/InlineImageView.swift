import SwiftUI
import UIKit

/// Displays an inline image preview in the chat timeline
struct InlineImageView: View {
    let image: UIImage
    let isGIF: Bool
    let autoPlayGIFs: Bool
    let isEmbedded: Bool
    let onTap: () -> Void

    private static let maxWidth: CGFloat = 280
    private static let maxHeight: CGFloat = 300

    private var displaySize: CGSize {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else {
            return CGSize(width: Self.maxWidth, height: Self.maxHeight)
        }
        let aspect = w / h
        var width = min(Self.maxWidth, w)
        var height = width / aspect
        if height > Self.maxHeight {
            height = Self.maxHeight
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        if isGIF {
            GIFContentView(
                image: image,
                autoPlayGIFs: autoPlayGIFs,
                isEmbedded: isEmbedded,
                displaySize: displaySize
            )
        } else {
            StaticImageContentView(
                image: image,
                isEmbedded: isEmbedded,
                displaySize: displaySize,
                onTap: onTap
            )
        }
    }
}

// MARK: - GIF Content

private struct GIFContentView: View {
    let image: UIImage
    let autoPlayGIFs: Bool
    let isEmbedded: Bool
    let displaySize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaying = false

    private var staticFrame: UIImage {
        image.images?.first ?? image
    }

    var body: some View {
        Group {
            if isPlaying {
                AnimatedGIFView(image: image)
            } else {
                Image(uiImage: staticFrame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .overlay {
            if !isPlaying {
                ZStack {
                    Color.black.opacity(0.3)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .background {
            if !isEmbedded {
                Color.clear.background(.regularMaterial)
            }
        }
        .clipShape(.rect(cornerRadius: isEmbedded ? 0 : 12))
        .onTapGesture {
            isPlaying.toggle()
        }
        .onAppear {
            isPlaying = autoPlayGIFs && !reduceMotion
        }
        .onChange(of: autoPlayGIFs) { _, newValue in
            isPlaying = newValue && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue { isPlaying = false }
        }
        .accessibilityLabel(L10n.Chats.Chats.InlineImage.animatedAccessibility)
        .accessibilityHint(L10n.Chats.Chats.InlineImage.tapHint)
    }
}

// MARK: - Static Image Content

private struct StaticImageContentView: View {
    let image: UIImage
    let isEmbedded: Bool
    let displaySize: CGSize
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: displaySize.width, height: displaySize.height)
                .background {
                    if !isEmbedded {
                        Color.clear.background(.regularMaterial)
                    }
                }
                .clipShape(.rect(cornerRadius: isEmbedded ? 0 : 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Chats.Chats.InlineImage.imageAccessibility)
        .accessibilityHint(L10n.Chats.Chats.InlineImage.tapHint)
    }
}
