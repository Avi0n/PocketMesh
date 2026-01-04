import Foundation

// MARK: - Array Enumerated Extension

extension Array {
    /// Returns enumerated elements as an array of tuples for use with ForEach.
    /// This is needed because `enumerated()` returns a lazy sequence that isn't
    /// directly compatible with SwiftUI's ForEach.
    func enumeratedElements() -> [(offset: Int, element: Element)] {
        Array<(offset: Int, element: Element)>(enumerated())
    }
}
