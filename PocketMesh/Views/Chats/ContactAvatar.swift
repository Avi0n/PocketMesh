import SwiftUI
import PocketMeshServices

struct ContactAvatar: View {
    let contact: ContactDTO
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: .circle)
    }

    private var initials: String {
        let name = contact.displayName
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        // Synthetic contacts (channel senders not in contacts) have empty publicKey.
        // Use name-based coloring for consistency with message thread sender colors.
        if contact.publicKey.isEmpty {
            return AppColors.SenderName.color(for: contact.name)
        }
        return AppColors.ContactAvatar.color(for: contact.publicKey)
    }
}
