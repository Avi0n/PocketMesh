import SwiftUI
import PocketMeshServices

/// A Text view that displays @[name] mentions in bold
struct MentionText: View {
    let text: String
    let baseColor: Color

    init(_ text: String, baseColor: Color = .primary) {
        self.text = text
        self.baseColor = baseColor
    }

    var body: some View {
        formattedText
    }

    private var formattedText: Text {
        var result = Text("")
        var currentIndex = text.startIndex

        let pattern = MentionUtilities.mentionPattern

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(text).foregroundStyle(baseColor)
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text) else { continue }

            // Add text before the mention
            if currentIndex < matchRange.lowerBound {
                let beforeText = String(text[currentIndex..<matchRange.lowerBound])
                result = result + Text(beforeText).foregroundStyle(baseColor)
            }

            // Add the mention in bold without brackets: @name instead of @[name]
            let name = String(text[nameRange])
            result = result + Text("@\(name)")
                .bold()
                .foregroundStyle(baseColor)

            currentIndex = matchRange.upperBound
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex...])
            result = result + Text(remainingText).foregroundStyle(baseColor)
        }

        return result
    }
}
