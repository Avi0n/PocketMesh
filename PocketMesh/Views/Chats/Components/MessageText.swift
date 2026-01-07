import SwiftUI
import PocketMeshServices

/// A Text view that formats message content with tappable links and bold mentions
struct MessageText: View {
    let text: String
    let baseColor: Color

    init(_ text: String, baseColor: Color = .primary) {
        self.text = text
        self.baseColor = baseColor
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

            // Replace @[name] with @name and make it bold
            var replacement = AttributedString("@\(name)")
            replacement.foregroundColor = baseColor
            replacement.inlinePresentationIntent = .stronglyEmphasized

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
}

#Preview("Plain text") {
    MessageText("Hello, world!")
        .padding()
}

#Preview("With mention") {
    MessageText("Hey @[Alice], check this out!")
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
