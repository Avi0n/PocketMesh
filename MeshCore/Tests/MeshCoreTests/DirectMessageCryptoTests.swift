import XCTest
import CommonCrypto
import CryptoKit
@testable import MeshCore

final class DirectMessageCryptoTests: XCTestCase {

    // Test key pair (generated for testing)
    // In real use, keys come from device and contacts
    private var senderPrivateKey: Curve25519.KeyAgreement.PrivateKey!
    private var senderPublicKey: Curve25519.KeyAgreement.PublicKey!
    private var recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey!
    private var recipientPublicKey: Curve25519.KeyAgreement.PublicKey!

    override func setUp() {
        super.setUp()
        // Generate test key pairs
        senderPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        senderPublicKey = senderPrivateKey.publicKey
        recipientPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        recipientPublicKey = recipientPrivateKey.publicKey
    }

    // MARK: - Helpers

    /// Compute shared secret (same as DirectMessageCrypto should do)
    private func computeSharedSecret(
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        theirPublicKey: Curve25519.KeyAgreement.PublicKey
    ) -> Data {
        // swiftlint:disable:next force_try
        let sharedSecret = try! myPrivateKey.sharedSecretFromKeyAgreement(with: theirPublicKey)
        return sharedSecret.withUnsafeBytes { Data($0) }
    }

    /// Encrypt AES-128-ECB (for creating test vectors)
    private func encryptAES128ECB(plaintext: Data, key: Data) -> Data? {
        guard key.count >= 16 else { return nil }
        let keyBytes = key.prefix(16)

        let paddedLength = ((plaintext.count + 15) / 16) * 16
        var padded = plaintext
        while padded.count < paddedLength {
            padded.append(0)
        }

        var encrypted = Data(count: paddedLength)
        var numBytesEncrypted: size_t = 0

        let status = encrypted.withUnsafeMutableBytes { encryptedPtr in
            padded.withUnsafeBytes { plaintextPtr in
                keyBytes.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, 16,
                        nil,
                        plaintextPtr.baseAddress, paddedLength,
                        encryptedPtr.baseAddress, paddedLength,
                        &numBytesEncrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(encrypted.prefix(numBytesEncrypted))
    }

    /// Compute truncated HMAC-SHA256 (2 bytes)
    private func computeMAC(data: Data, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac.prefix(2))
    }

    /// Create encrypted direct message payload for testing
    /// Format: [destHash:1][srcHash:1][MAC:2][ciphertext:N]
    /// Plaintext: [timestamp:4][typeAttempt:1][text:N]
    private func createEncryptedPayload(
        destHash: UInt8,
        srcHash: UInt8,
        timestamp: UInt32,
        typeAttempt: UInt8,
        message: String,
        sharedSecret: Data
    ) -> Data? {
        // Build plaintext
        var plaintext = Data()
        var ts = timestamp.littleEndian
        plaintext.append(Data(bytes: &ts, count: 4))
        plaintext.append(typeAttempt)
        plaintext.append(Data(message.utf8))

        // Encrypt
        guard let ciphertext = encryptAES128ECB(plaintext: plaintext, key: sharedSecret) else {
            return nil
        }

        // Build packet: [destHash][srcHash][MAC][ciphertext]
        // MAC is computed over ciphertext only (per MeshCore spec and ChannelCrypto)
        let mac = computeMAC(data: ciphertext, key: sharedSecret)

        var packet = Data()
        packet.append(destHash)
        packet.append(srcHash)
        packet.append(mac)
        packet.append(ciphertext)

        return packet
    }

    // MARK: - Tests

    func testDecryptSuccess() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        let timestamp: UInt32 = 1703123456
        let typeAttempt: UInt8 = 0
        let message = "Hello from sender!"
        let destHash = recipientPublicKey.rawRepresentation.first!
        let srcHash = senderPublicKey.rawRepresentation.first!

        guard let payload = createEncryptedPayload(
            destHash: destHash,
            srcHash: srcHash,
            timestamp: timestamp,
            typeAttempt: typeAttempt,
            message: message,
            sharedSecret: sharedSecret
        ) else {
            XCTFail("Failed to create test payload")
            return
        }

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .success(let ts, let ta, let text):
            XCTAssertEqual(ts, timestamp)
            XCTAssertEqual(ta, typeAttempt)
            XCTAssertEqual(text, message)
        case .macMismatch:
            XCTFail("MAC verification failed")
        case .decryptionFailed:
            XCTFail("Decryption failed")
        case .invalidPayload:
            XCTFail("Invalid payload")
        case .keyError:
            XCTFail("Key error")
        }
    }

    func testDecryptWrongKey() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        let payload = createEncryptedPayload(
            destHash: 0xAA,
            srcHash: 0xBB,
            timestamp: 1703123456,
            typeAttempt: 0,
            message: "Secret message",
            sharedSecret: sharedSecret
        )!

        // Use wrong key pair
        let wrongPrivateKey = Curve25519.KeyAgreement.PrivateKey()

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data(wrongPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .success:
            XCTFail("Should have failed with wrong key")
        case .macMismatch:
            // Expected
            break
        default:
            XCTFail("Expected macMismatch")
        }
    }

    func testDecryptCorruptedMAC() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        var payload = createEncryptedPayload(
            destHash: 0xAA,
            srcHash: 0xBB,
            timestamp: 1703123456,
            typeAttempt: 0,
            message: "Test",
            sharedSecret: sharedSecret
        )!

        // Corrupt MAC (bytes 2 and 3)
        payload[2] ^= 0xFF
        payload[3] ^= 0xFF

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .macMismatch:
            // Expected
            break
        default:
            XCTFail("Expected macMismatch")
        }
    }

    func testDecryptPayloadTooShort() {
        // Less than minimum: 1 + 1 + 2 + 16 = 20 bytes
        let shortPayload = Data([0x00, 0x01, 0x02, 0x03])

        let result = DirectMessageCrypto.decrypt(
            payload: shortPayload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .invalidPayload:
            // Expected
            break
        default:
            XCTFail("Expected invalidPayload")
        }
    }

    func testDecryptEmptyMessage() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        guard let payload = createEncryptedPayload(
            destHash: 0xAA,
            srcHash: 0xBB,
            timestamp: 0,
            typeAttempt: 0,
            message: "",
            sharedSecret: sharedSecret
        ) else {
            XCTFail("Failed to create test payload")
            return
        }

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .success(let ts, let ta, let text):
            XCTAssertEqual(ts, 0)
            XCTAssertEqual(ta, 0)
            XCTAssertEqual(text, "")
        default:
            XCTFail("Expected success")
        }
    }

    func testDecryptUnicodeMessage() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        let message = "Hello! \u{4F60}\u{597D}! \u{1F30D}"

        guard let payload = createEncryptedPayload(
            destHash: 0xAA,
            srcHash: 0xBB,
            timestamp: 1703123456,
            typeAttempt: 0,
            message: message,
            sharedSecret: sharedSecret
        ) else {
            XCTFail("Failed to create test payload")
            return
        }

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        switch result {
        case .success(_, _, let text):
            XCTAssertEqual(text, message)
        default:
            XCTFail("Expected success")
        }
    }

    func testExtractTimestamp() {
        let sharedSecret = computeSharedSecret(
            myPrivateKey: recipientPrivateKey,
            theirPublicKey: senderPublicKey
        )

        let expectedTimestamp: UInt32 = 1703123456

        guard let payload = createEncryptedPayload(
            destHash: 0xAA,
            srcHash: 0xBB,
            timestamp: expectedTimestamp,
            typeAttempt: 0,
            message: "Test",
            sharedSecret: sharedSecret
        ) else {
            XCTFail("Failed to create test payload")
            return
        }

        let timestamp = DirectMessageCrypto.extractTimestamp(
            payload: payload,
            myPrivateKey: Data(recipientPrivateKey.rawRepresentation),
            senderPublicKey: Data(senderPublicKey.rawRepresentation)
        )

        XCTAssertEqual(timestamp, expectedTimestamp)
    }

    func testConstants() {
        XCTAssertEqual(DirectMessageCrypto.macSize, 2)
        XCTAssertEqual(DirectMessageCrypto.headerSize, 2)
        XCTAssertEqual(DirectMessageCrypto.timestampSize, 4)
        XCTAssertEqual(DirectMessageCrypto.typeAttemptSize, 1)
        XCTAssertEqual(DirectMessageCrypto.minCiphertextSize, 16)
        XCTAssertEqual(DirectMessageCrypto.minPacketSize, 20)
    }

    func testInvalidKeyLength() {
        let payload = Data(repeating: 0, count: 24)

        let result = DirectMessageCrypto.decrypt(
            payload: payload,
            myPrivateKey: Data([0x01, 0x02]),  // Too short
            senderPublicKey: Data(repeating: 0, count: 32)
        )

        switch result {
        case .keyError:
            // Expected
            break
        default:
            XCTFail("Expected keyError")
        }
    }
}
