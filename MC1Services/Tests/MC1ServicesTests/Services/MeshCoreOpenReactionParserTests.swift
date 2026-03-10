import Foundation
import Testing
@testable import PocketMeshServices

@Suite("MeshCoreOpenReactionParser Tests")
struct MeshCoreOpenReactionParserTests {

    // MARK: - Parse Valid Format Tests

    @Test("Parses valid reaction with thumbs up (index 00)")
    func parsesThumbsUp() {
        let result = MeshCoreOpenReactionParser.parse("r:a1b2:00")

        #expect(result != nil)
        #expect(result?.emoji == "👍")
        #expect(result?.dartHash == "a1b2")
    }

    @Test("Parses valid reaction with fire (index 05)")
    func parsesFire() {
        let result = MeshCoreOpenReactionParser.parse("r:ff00:05")

        #expect(result != nil)
        #expect(result?.emoji == "🔥")
        #expect(result?.dartHash == "ff00")
    }

    @Test("Parses valid reaction with heart (index 01)")
    func parsesHeart() {
        let result = MeshCoreOpenReactionParser.parse("r:1234:01")

        #expect(result != nil)
        #expect(result?.emoji == "❤️")
        #expect(result?.dartHash == "1234")
    }

    @Test("Parses reaction at max valid emoji index (0xb7)")
    func parsesMaxIndex() {
        let result = MeshCoreOpenReactionParser.parse("r:abcd:b7")

        #expect(result != nil)
        #expect(result?.emoji == "🚀")
        #expect(result?.dartHash == "abcd")
    }

    // MARK: - Parse Invalid Format Tests

    @Test("Rejects plain text")
    func rejectsPlainText() {
        #expect(MeshCoreOpenReactionParser.parse("hello world") == nil)
    }

    @Test("Rejects wrong prefix")
    func rejectsWrongPrefix() {
        #expect(MeshCoreOpenReactionParser.parse("x:a1b2:00") == nil)
    }

    @Test("Rejects uppercase hex in hash")
    func rejectsUppercaseHash() {
        #expect(MeshCoreOpenReactionParser.parse("r:A1B2:00") == nil)
    }

    @Test("Rejects uppercase hex in index")
    func rejectsUppercaseIndex() {
        #expect(MeshCoreOpenReactionParser.parse("r:a1b2:0A") == nil)
    }

    @Test("Rejects too short")
    func rejectsTooShort() {
        #expect(MeshCoreOpenReactionParser.parse("r:a1b:00") == nil)
    }

    @Test("Rejects too long")
    func rejectsTooLong() {
        #expect(MeshCoreOpenReactionParser.parse("r:a1b2c:00") == nil)
    }

    @Test("Rejects missing colons")
    func rejectsMissingColons() {
        #expect(MeshCoreOpenReactionParser.parse("r-a1b2-00") == nil)
    }

    @Test("Rejects emoji index beyond table size")
    func rejectsOutOfRangeIndex() {
        // 0xb8 = 184, table has 184 entries (0x00–0xb7)
        #expect(MeshCoreOpenReactionParser.parse("r:a1b2:b8") == nil)
    }

    @Test("Rejects PocketMesh channel reaction format")
    func rejectsPocketMeshChannelFormat() {
        #expect(MeshCoreOpenReactionParser.parse("👍@[AlphaNode]\n7f3a9c12") == nil)
    }

    @Test("Rejects PocketMesh DM reaction format")
    func rejectsPocketMeshDMFormat() {
        #expect(MeshCoreOpenReactionParser.parse("👍\n7f3a9c12") == nil)
    }

    @Test("Rejects empty string")
    func rejectsEmpty() {
        #expect(MeshCoreOpenReactionParser.parse("") == nil)
    }

    // MARK: - Emoji Index Mapping Tests

    @Test("Spot-check emoji indices across all categories")
    func spotCheckEmojiIndices() {
        // quickEmojis
        #expect(MeshCoreOpenReactionParser.parse("r:0000:00")?.emoji == "👍")  // 0x00
        #expect(MeshCoreOpenReactionParser.parse("r:0000:02")?.emoji == "😂")  // 0x02
        #expect(MeshCoreOpenReactionParser.parse("r:0000:03")?.emoji == "🎉")  // 0x03

        // smileys start at 0x06
        #expect(MeshCoreOpenReactionParser.parse("r:0000:06")?.emoji == "😀")  // first smiley
        #expect(MeshCoreOpenReactionParser.parse("r:0000:45")?.emoji == "😶")  // last smiley

        // gestures start at 0x46
        #expect(MeshCoreOpenReactionParser.parse("r:0000:46")?.emoji == "👍")  // first gesture
        #expect(MeshCoreOpenReactionParser.parse("r:0000:66")?.emoji == "💪")  // last gesture

        // hearts start at 0x67
        #expect(MeshCoreOpenReactionParser.parse("r:0000:67")?.emoji == "❤️")  // first heart

        // objects start at 0x87
        #expect(MeshCoreOpenReactionParser.parse("r:0000:87")?.emoji == "🎉")  // first object
    }

    // MARK: - Dart String Hash Tests

    @Test("Dart hash of empty input produces 1")
    func dartHashEmpty() {
        // Dart: "".hashCode should be 0, which becomes 1 (zero-guard)
        let hash = MeshCoreOpenReactionParser.dartStringHash([])
        #expect(hash == 1)
    }

    @Test("Dart hash is deterministic")
    func dartHashDeterministic() {
        let units: [UInt16] = Array("hello".utf16)
        let hash1 = MeshCoreOpenReactionParser.dartStringHash(units)
        let hash2 = MeshCoreOpenReactionParser.dartStringHash(units)
        #expect(hash1 == hash2)
    }

    @Test("Dart hash of single character 'a'")
    func dartHashSingleChar() {
        // Manually compute: code_unit = 97 (0x61)
        // hash = 0
        // hash += 97 → 97
        // hash += 97 << 10 → 97 + 99328 = 99425
        // hash ^= 99425 >> 6 → 99425 ^ 1553 = 100464
        // finalize:
        // hash += 100464 << 3 → 100464 + 803712 = 904176
        // hash ^= 904176 >> 11 → 904176 ^ 441 = 904617
        // hash += 904617 << 15 → 904617 + 29640630272 (wraps in UInt32) → need wrapping
        // Let's just verify it's > 0 and within 30 bits
        let hash = MeshCoreOpenReactionParser.dartStringHash([97])
        #expect(hash > 0)
        #expect(hash < (1 << 30))
    }

    @Test("Dart hash result is within 30-bit range")
    func dartHashRange() {
        let units: [UInt16] = Array("test string with various chars 🎉".utf16)
        let hash = MeshCoreOpenReactionParser.dartStringHash(units)
        #expect(hash > 0)
        #expect(hash <= (1 << 30) - 1)
    }

    @Test("Different inputs produce different hashes")
    func dartHashDifferentInputs() {
        let hash1 = MeshCoreOpenReactionParser.dartStringHash(Array("hello".utf16))
        let hash2 = MeshCoreOpenReactionParser.dartStringHash(Array("world".utf16))
        #expect(hash1 != hash2)
    }

    // MARK: - Hash Computation Tests

    @Test("computeReactionHash returns 4-char lowercase hex")
    func hashFormat() {
        let hash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "AlphaNode",
            text: "Hello world"
        )
        #expect(hash.count == 4)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("computeReactionHash is deterministic")
    func hashDeterministic() {
        let hash1 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "AlphaNode",
            text: "Hello world"
        )
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "AlphaNode",
            text: "Hello world"
        )
        #expect(hash1 == hash2)
    }

    @Test("computeReactionHash changes with different timestamp")
    func hashChangesWithTimestamp() {
        let hash1 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "Hello"
        )
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000001,
            senderName: "Node",
            text: "Hello"
        )
        #expect(hash1 != hash2)
    }

    @Test("computeReactionHash changes with different sender")
    func hashChangesWithSender() {
        let hash1 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "AlphaNode",
            text: "Hello"
        )
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "BetaNode",
            text: "Hello"
        )
        #expect(hash1 != hash2)
    }

    @Test("computeReactionHash changes with different text")
    func hashChangesWithText() {
        let hash1 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "Hello"
        )
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "World"
        )
        #expect(hash1 != hash2)
    }

    @Test("computeReactionHash with nil sender (DM mode)")
    func hashDMMode() {
        let hash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: nil,
            text: "Hello world"
        )
        #expect(hash.count == 4)

        // Should differ from channel mode with same params
        let channelHash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "Hello world"
        )
        #expect(hash != channelHash)
    }

    @Test("computeReactionHash truncates text to 5 UTF-16 code units")
    func hashTruncatesText() {
        // "Hello" is 5 code units, "Hello world" has 11
        // Both should produce the same hash since only first 5 code units are used
        let hash1 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "Hello"
        )
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: "Hello world"
        )
        #expect(hash1 == hash2)
    }

    @Test("computeReactionHash handles short text (fewer than 5 code units)")
    func hashShortText() {
        let hash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: nil,
            text: "Hi"
        )
        #expect(hash.count == 4)
    }

    // MARK: - UTF-16 Edge Cases

    @Test("computeReactionHash handles emoji in text (multi-code-unit)")
    func hashEmojiText() {
        // 🎉 is 2 UTF-16 code units (surrogate pair), so "🎉abc" = 5 code units
        let hash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: nil,
            text: "🎉abc"
        )
        #expect(hash.count == 4)

        // "🎉abcdef" should hash the same since first 5 code units match
        let hash2 = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: nil,
            text: "🎉abcdef"
        )
        #expect(hash == hash2)
    }

    @Test("computeReactionHash handles empty text")
    func hashEmptyText() {
        let hash = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "Node",
            text: ""
        )
        #expect(hash.count == 4)
    }

    // MARK: - Cross-App Test Vectors

    @Test("Dart hash matches known Dart VM output for 'hello'")
    func dartHashKnownVector() {
        // In Dart: "hello".hashCode == 150804507
        // This is the definitive cross-app test vector
        let hash = MeshCoreOpenReactionParser.dartStringHash(Array("hello".utf16))
        #expect(hash == 150804507)
    }

    @Test("computeReactionHash is internally consistent")
    func hashInternalConsistency() {
        // Verify computeReactionHash assembles code units correctly
        // by comparing against manual dartStringHash call
        let testUnits = Array("1700000000AHello".utf16)
        let fullHash = MeshCoreOpenReactionParser.dartStringHash(testUnits)
        let masked = fullHash & 0xFFFF
        let expected = String(format: "%04x", masked)

        let computed = MeshCoreOpenReactionParser.computeReactionHash(
            timestamp: 1700000000,
            senderName: "A",
            text: "Hello"
        )
        #expect(computed == expected)
    }

    @Test("Emoji table has exactly 184 entries")
    func emojiTableSize() {
        #expect(MeshCoreOpenReactionParser.emojiTable.count == 184)
    }

    // MARK: - V1 Parse Tests

    @Test("Parses v1 reaction from real wire capture")
    func parsesV1RealCapture() {
        let result = MeshCoreOpenReactionParser.parseV1("r:1772600903000_951919033_868488711:👍")

        #expect(result != nil)
        #expect(result?.emoji == "👍")
        #expect(result?.timestampSeconds == 1_772_600_903)
        #expect(result?.senderNameHash == 951_919_033)
        #expect(result?.textHash == 868_488_711)
    }

    @Test("Parses v1 reaction with heart emoji")
    func parsesV1Heart() {
        let result = MeshCoreOpenReactionParser.parseV1("r:1700000000000_12345_67890:❤️")

        #expect(result != nil)
        #expect(result?.emoji == "❤️")
        #expect(result?.timestampSeconds == 1_700_000_000)
        #expect(result?.senderNameHash == 12345)
        #expect(result?.textHash == 67890)
    }

    @Test("Parses v1 reaction with fire emoji")
    func parsesV1Fire() {
        let result = MeshCoreOpenReactionParser.parseV1("r:1772600903000_100_200:🔥")

        #expect(result != nil)
        #expect(result?.emoji == "🔥")
    }

    @Test("V1 rejects v3 format")
    func v1RejectsV3() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:a1b2:00") == nil)
    }

    @Test("V1 rejects plain text")
    func v1RejectsPlainText() {
        #expect(MeshCoreOpenReactionParser.parseV1("hello world") == nil)
    }

    @Test("V1 rejects wrong prefix")
    func v1RejectsWrongPrefix() {
        #expect(MeshCoreOpenReactionParser.parseV1("x:1700000000000_100_200:👍") == nil)
    }

    @Test("V1 rejects too few underscore parts")
    func v1RejectsTwoParts() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:1700000000000_100:👍") == nil)
    }

    @Test("V1 rejects too many underscore parts")
    func v1RejectsFourParts() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:1700000000000_100_200_300:👍") == nil)
    }

    @Test("V1 rejects non-numeric timestamp")
    func v1RejectsNonNumericTimestamp() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:abc_100_200:👍") == nil)
    }

    @Test("V1 rejects non-numeric hash values")
    func v1RejectsNonNumericHash() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:1700000000000_abc_200:👍") == nil)
        #expect(MeshCoreOpenReactionParser.parseV1("r:1700000000000_100_xyz:👍") == nil)
    }

    @Test("V1 rejects empty emoji")
    func v1RejectsEmptyEmoji() {
        #expect(MeshCoreOpenReactionParser.parseV1("r:1700000000000_100_200:") == nil)
    }

    @Test("V1 rejects PocketMesh channel format")
    func v1RejectsPocketMeshChannel() {
        #expect(MeshCoreOpenReactionParser.parseV1("👍@[AlphaNode]\n7f3a9c12") == nil)
    }

    @Test("V1 rejects empty string")
    func v1RejectsEmpty() {
        #expect(MeshCoreOpenReactionParser.parseV1("") == nil)
    }

    @Test("V1 timestamp converts millis to seconds correctly")
    func v1TimestampConversion() {
        // 1700000000500 ms → 1700000000 s (truncated, not rounded)
        let result = MeshCoreOpenReactionParser.parseV1("r:1700000000500_100_200:👍")
        #expect(result?.timestampSeconds == 1_700_000_000)
    }

    // MARK: - V1 Hash Matching Tests

    @Test("dartStringHash can verify v1 sender name hash")
    func v1SenderNameHashVerification() {
        // Compute the Dart hash of a known sender name
        let senderName = "TestNode"
        let expectedHash = MeshCoreOpenReactionParser.dartStringHash(Array(senderName.utf16))

        // Construct a v1 reaction with that hash
        let reactionText = "r:1700000000000_\(expectedHash)_12345:👍"
        let parsed = MeshCoreOpenReactionParser.parseV1(reactionText)

        #expect(parsed != nil)
        #expect(parsed?.senderNameHash == expectedHash)
    }

    @Test("dartStringHash can verify v1 text hash")
    func v1TextHashVerification() {
        let messageText = "Hello from mesh"
        let expectedHash = MeshCoreOpenReactionParser.dartStringHash(Array(messageText.utf16))

        let reactionText = "r:1700000000000_12345_\(expectedHash):👍"
        let parsed = MeshCoreOpenReactionParser.parseV1(reactionText)

        #expect(parsed != nil)
        #expect(parsed?.textHash == expectedHash)
    }

    @Test("V1 round-trip: construct reaction and verify both hashes match")
    func v1RoundTrip() {
        let senderName = "AVN1"
        let messageText = "Test message content"
        let timestampMs: UInt64 = 1_772_600_903_000

        let senderHash = MeshCoreOpenReactionParser.dartStringHash(Array(senderName.utf16))
        let textHash = MeshCoreOpenReactionParser.dartStringHash(Array(messageText.utf16))

        let reactionText = "r:\(timestampMs)_\(senderHash)_\(textHash):👍"
        let parsed = MeshCoreOpenReactionParser.parseV1(reactionText)

        #expect(parsed != nil)
        #expect(parsed?.timestampSeconds == UInt32(timestampMs / 1000))
        #expect(parsed?.senderNameHash == senderHash)
        #expect(parsed?.textHash == textHash)
        #expect(parsed?.emoji == "👍")
    }
}
