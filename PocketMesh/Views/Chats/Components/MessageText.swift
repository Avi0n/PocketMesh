import SwiftUI
import PocketMeshServices

/// A Text view that formats message content with tappable links and styled mentions
struct MessageText: View {
    let text: String
    let baseColor: Color
    let currentUserName: String?

    init(_ text: String, baseColor: Color = .primary, currentUserName: String? = nil) {
        self.text = text
        self.baseColor = baseColor
        self.currentUserName = currentUserName
    }

    var body: some View {
        Text(formattedText)
    }

    private var formattedText: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = baseColor

        // Apply mention formatting (@[name] -> bold @name)
        applyMentionFormatting(&result)

        // Apply URL formatting (make links tappable)
        applyURLFormatting(&result)

        // Apply hashtag formatting (make #channels tappable)
        applyHashtagFormatting(&result)

        return result
    }

    // MARK: - Mention Formatting

    private func applyMentionFormatting(_ attributedString: inout AttributedString) {
        let pattern = MentionUtilities.mentionPattern

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text),
                  let attrMatchRange = Range(matchRange, in: attributedString) else { continue }

            // Get the name without brackets
            let name = String(text[nameRange])

            // Check if this is a self-mention
            let isSelfMention = currentUserName.map {
                name.localizedCaseInsensitiveCompare($0) == .orderedSame
            } ?? false

            // Determine if we're on a dark bubble (outgoing messages use white text)
            let isOnDarkBubble = baseColor == .white

            // Replace @[name] with @name, styled appropriately for bubble color
            var replacement = AttributedString("@\(name)")
            replacement.inlinePresentationIntent = .stronglyEmphasized

            if isOnDarkBubble {
                // On dark bubbles: use white text, with background only for self-mentions
                replacement.foregroundColor = .white
                if isSelfMention {
                    replacement.backgroundColor = Color.white.opacity(0.3)
                }
            } else {
                // On light bubbles: use accent color
                replacement.foregroundColor = Color.accentColor
                if isSelfMention {
                    replacement.backgroundColor = Color.accentColor.opacity(0.15)
                }
            }

            attributedString.replaceSubrange(attrMatchRange, with: replacement)
        }
    }

    // MARK: - URL Formatting

    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private func applyURLFormatting(_ attributedString: inout AttributedString) {
        guard let detector = Self.urlDetector else { return }

        // Get the current string content (may have been modified by mention formatting)
        let currentString = String(attributedString.characters)
        let nsRange = NSRange(currentString.startIndex..., in: currentString)
        let matches = detector.matches(in: currentString, options: [], range: nsRange)

        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let matchRange = Range(match.range, in: currentString),
                  let attrRange = Range(matchRange, in: attributedString) else { continue }

            attributedString[attrRange].link = url
            attributedString[attrRange].foregroundColor = baseColor
            attributedString[attrRange].underlineStyle = .single
        }
    }

    // MARK: - Hashtag Formatting

    private func applyHashtagFormatting(_ attributedString: inout AttributedString) {
        let currentString = String(attributedString.characters)
        let hashtags = HashtagUtilities.extractHashtags(from: currentString)

        // Process in reverse to preserve indices
        for hashtag in hashtags.reversed() {
            guard let attrRange = Range(hashtag.range, in: attributedString) else { continue }

            // Create a custom URL scheme for hashtag taps
            // Format: pocketmesh-hashtag://channelname
            let channelName = HashtagUtilities.normalizeHashtagName(hashtag.name)
            if let url = URL(string: "pocketmesh-hashtag://\(channelName)") {
                attributedString[attrRange].link = url
                // Hashtags: bold + cyan (or white on dark bubbles), no underline
                // This distinguishes them from URLs which remain underlined
                let isOnDarkBubble = baseColor == .white
                attributedString[attrRange].foregroundColor = isOnDarkBubble ? .white : .cyan
                attributedString[attrRange].inlinePresentationIntent = .stronglyEmphasized
            }
        }
    }
}

#Preview("Plain text") {
    MessageText("Hello, world!")
        .padding()
}

#Preview("With mention") {
    MessageText("Hey @[Alice], check this out!")
        .padding()
}

#Preview("With self-mention") {
    MessageText("Hey @[Me], you were mentioned!", currentUserName: "Me")
        .padding()
}

#Preview("With link") {
    MessageText("Check out https://apple.com for more info")
        .padding()
}

#Preview("With mention and link") {
    MessageText("@[Bob] look at https://example.com/article")
        .padding()
}

#Preview("Outgoing message") {
    MessageText("Visit https://github.com", baseColor: .white)
        .padding()
        .background(.blue)
}

#Preview("Outgoing with mention") {
    MessageText("Hey @[Alice], check this out!", baseColor: .white)
        .padding()
        .background(.blue)
}

#Preview("Outgoing with self-mention") {
    MessageText("@[MyDevice] check this!", baseColor: .white, currentUserName: "MyDevice")
        .padding()
        .background(.blue)
}

#Preview("With hashtag") {
    MessageText("Join #general for updates")
        .padding()
}

#Preview("With hashtag and URL") {
    MessageText("Check https://example.com#anchor and #general")
        .padding()
}
