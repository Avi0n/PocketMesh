import Foundation
import SwiftUI

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func forSenderName(_ name: String) -> Color {
        let colors: [Color] = [
            Color(hex: 0xcc7a5c), // coral
            Color(hex: 0x5c8a99), // slate teal
            Color(hex: 0x8c7a99), // dusty violet
            Color(hex: 0x7a9988), // sage
            Color(hex: 0x997a8c), // dusty rose
            Color(hex: 0x99885c), // ochre
            Color(hex: 0x5c7a99), // slate blue
            Color(hex: 0xb5856b), // terracotta
            Color(hex: 0x8a9966), // olive
            Color(hex: 0x8c5c7a)  // dusty plum
        ]
        let hash = name.utf8.reduce(0) { $0 ^ Int($1) }
        return colors[abs(hash) % colors.count]
    }
}
