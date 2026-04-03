import Foundation

extension String {
    /// Whether this region name represents a private region (prefixed with "$")
    var isPrivateRegion: Bool { hasPrefix("$") }
}

/// Validates region names before adding them to the device's known regions list
enum RegionNameValidator {
    enum ValidationError {
        case empty
        case invalidCharacters
        case duplicate
    }

    static func validate(_ name: String, existingRegions: [String]) -> ValidationError? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        if !trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
            return .invalidCharacters
        }
        if existingRegions.contains(trimmed) { return .duplicate }
        return nil
    }

    static func isValid(_ name: String, existingRegions: [String]) -> Bool {
        validate(name, existingRegions: existingRegions) == nil
    }
}
