import Testing
@testable import MC1

@Suite("RegionNameValidator")
struct RegionNameValidatorTests {

    // MARK: - Valid Names

    @Test("accepts standard region names", arguments: [
        "Europe", "UK", "France", "sample-city", "region-1"
    ])
    func validNames(name: String) {
        #expect(RegionNameValidator.isValid(name, existingRegions: []))
    }

    // MARK: - Invalid Names

    @Test("rejects empty name")
    func emptyNameIsInvalid() {
        #expect(RegionNameValidator.validate("", existingRegions: []) == .empty)
    }

    @Test("rejects whitespace-only name")
    func whitespaceOnlyIsInvalid() {
        #expect(RegionNameValidator.validate("   ", existingRegions: []) == .empty)
    }

    @Test("rejects name with spaces")
    func spacesInNameAreInvalid() {
        #expect(RegionNameValidator.validate("my region", existingRegions: []) == .invalidCharacters)
    }

    @Test("rejects unicode characters")
    func unicodeIsInvalid() {
        #expect(RegionNameValidator.validate("Île-de-France", existingRegions: []) == .invalidCharacters)
    }

    @Test("rejects special characters", arguments: ["hello!", "foo@bar", "a&b", "test.region", "#Europe", "$secret"])
    func specialCharsAreInvalid(name: String) {
        #expect(RegionNameValidator.validate(name, existingRegions: []) == .invalidCharacters)
    }

    // MARK: - Duplicates

    @Test("rejects duplicate region name")
    func duplicateIsInvalid() {
        #expect(RegionNameValidator.validate("Europe", existingRegions: ["Europe"]) == .duplicate)
    }

    @Test("duplicate check is case-sensitive")
    func caseSensitiveDuplicateCheck() {
        #expect(RegionNameValidator.isValid("europe", existingRegions: ["Europe"]))
    }

    // MARK: - isValid convenience

    @Test("isValid returns true for valid name")
    func isValidReturnsTrue() {
        #expect(RegionNameValidator.isValid("Europe", existingRegions: []))
    }

    @Test("isValid returns false for invalid name")
    func isValidReturnsFalse() {
        #expect(!RegionNameValidator.isValid("", existingRegions: []))
    }
}
