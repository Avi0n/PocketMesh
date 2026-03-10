import Foundation
import PocketMeshServices

/// Unified node type for the repeater picker list
enum PickerNode: Identifiable {
    case contact(ContactDTO)
    case discovered(DiscoveredNodeDTO)

    var id: UUID {
        switch self {
        case .contact(let c): c.id
        case .discovered(let d): d.id
        }
    }

    var displayName: String {
        switch self {
        case .contact(let c): c.displayName
        case .discovered(let d): d.name
        }
    }

    var publicKeyHex: String {
        switch self {
        case .contact(let c): c.publicKey.hexString()
        case .discovered(let d): d.publicKey.hexString()
        }
    }

    var isRoom: Bool {
        switch self {
        case .contact(let c): c.type == .room
        case .discovered: false
        }
    }

    var isDiscovered: Bool {
        switch self {
        case .contact: false
        case .discovered: true
        }
    }

    /// The underlying DTO for passing to ViewModel methods
    var underlying: any RepeaterResolvable {
        switch self {
        case .contact(let c): c
        case .discovered(let d): d
        }
    }
}
