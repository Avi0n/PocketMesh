import XCTest
import CryptoKit
@testable import PocketMeshKit

final class ChannelTests: XCTestCase {

    func testSecretHashGeneration() {
        let channelName = "test-channel"
        let nameData = channelName.data(using: .utf8)!

        let hash = SHA256.hash(data: nameData)
        let secret = Data(hash.prefix(16))

        XCTAssertEqual(secret.count, 16)

        // Verify deterministic
        let hash2 = SHA256.hash(data: nameData)
        let secret2 = Data(hash2.prefix(16))

        XCTAssertEqual(secret, secret2)
    }

    func testDifferentNamesProduceDifferentHashes() {
        let name1 = "channel-a"
        let name2 = "channel-b"

        let hash1 = SHA256.hash(data: name1.data(using: .utf8)!)
        let hash2 = SHA256.hash(data: name2.data(using: .utf8)!)

        XCTAssertNotEqual(Data(hash1.prefix(16)), Data(hash2.prefix(16)))
    }

    func testCaseSensitivity() {
        let name1 = "TestChannel"
        let name2 = "testchannel"

        let hash1 = SHA256.hash(data: name1.data(using: .utf8)!)
        let hash2 = SHA256.hash(data: name2.data(using: .utf8)!)

        // Different cases should produce different hashes
        XCTAssertNotEqual(Data(hash1.prefix(16)), Data(hash2.prefix(16)))
    }

    func testEmptyChannelName() {
        let emptyName = ""
        let nameData = emptyName.data(using: .utf8)!

        let hash = SHA256.hash(data: nameData)
        let secret = Data(hash.prefix(16))

        // Even empty string should produce a valid 16-byte secret
        XCTAssertEqual(secret.count, 16)
    }

    func testHashPrefix() {
        let channelName = "test"
        let nameData = channelName.data(using: .utf8)!

        let fullHash = SHA256.hash(data: nameData)
        let prefix = Data(fullHash.prefix(16))

        // Verify we're only taking first 16 bytes
        XCTAssertEqual(prefix.count, 16)
        XCTAssertLessThan(prefix.count, Data(fullHash).count)
    }
}
