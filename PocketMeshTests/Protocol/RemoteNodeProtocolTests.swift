import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Remote Node Protocol Tests")
struct RemoteNodeProtocolTests {

    // MARK: - RemoteNodeRole Tests

    @Test("RemoteNodeRole maps correctly from ContactType.repeater")
    func remoteNodeRoleMapsFromRepeater() {
        let role = RemoteNodeRole(contactType: .repeater)
        #expect(role == .repeater)
        #expect(role?.rawValue == 0x02)
    }

    @Test("RemoteNodeRole maps correctly from ContactType.room")
    func remoteNodeRoleMapsFromRoom() {
        let role = RemoteNodeRole(contactType: .room)
        #expect(role == .roomServer)
        #expect(role?.rawValue == 0x03)
    }

    @Test("RemoteNodeRole returns nil for ContactType.chat")
    func remoteNodeRoleReturnsNilForChat() {
        let role = RemoteNodeRole(contactType: .chat)
        #expect(role == nil)
    }

    // MARK: - RoomPermissionLevel Tests

    @Test("RoomPermissionLevel comparison works correctly")
    func roomPermissionLevelComparison() {
        #expect(RoomPermissionLevel.guest < .readWrite)
        #expect(RoomPermissionLevel.readWrite < .admin)
        #expect(RoomPermissionLevel.guest < .admin)
        #expect(!(RoomPermissionLevel.admin < .readWrite))
    }

    @Test("RoomPermissionLevel canPost returns correct value")
    func roomPermissionLevelCanPost() {
        #expect(RoomPermissionLevel.guest.canPost == false)
        #expect(RoomPermissionLevel.readWrite.canPost == true)
        #expect(RoomPermissionLevel.admin.canPost == true)
    }

    @Test("RoomPermissionLevel isAdmin returns correct value")
    func roomPermissionLevelIsAdmin() {
        #expect(RoomPermissionLevel.guest.isAdmin == false)
        #expect(RoomPermissionLevel.readWrite.isAdmin == false)
        #expect(RoomPermissionLevel.admin.isAdmin == true)
    }

    @Test("RoomPermissionLevel displayName is correct")
    func roomPermissionLevelDisplayName() {
        #expect(RoomPermissionLevel.guest.displayName == "Guest")
        #expect(RoomPermissionLevel.readWrite.displayName == "Member")
        #expect(RoomPermissionLevel.admin.displayName == "Admin")
    }

    // MARK: - RemoteNodeStatus Role-Specific Interpretation Tests

    @Test("RemoteNodeStatus roomPostsCount extracts bytes 48-49 correctly")
    func remoteNodeStatusRoomPostsCount() {
        // rxAirtimeSeconds is stored as little-endian UInt32
        // For room servers: low 16 bits = posts count, high 16 bits = push count
        // Example: rxAirtimeSeconds = 0x00150064 → posts = 100 (0x0064), pushes = 21 (0x0015)
        let status = createTestRemoteNodeStatus(rxAirtimeSeconds: 0x00150064)
        #expect(status.roomPostsCount == 100)
    }

    @Test("RemoteNodeStatus roomPostPushCount extracts bytes 50-51 correctly")
    func remoteNodeStatusRoomPostPushCount() {
        // High 16 bits of rxAirtimeSeconds
        let status = createTestRemoteNodeStatus(rxAirtimeSeconds: 0x00150064)
        #expect(status.roomPostPushCount == 21)
    }

    @Test("RemoteNodeStatus repeaterRxAirtimeSeconds returns full UInt32")
    func remoteNodeStatusRepeaterRxAirtimeSeconds() {
        let status = createTestRemoteNodeStatus(rxAirtimeSeconds: 0x12345678)
        #expect(status.repeaterRxAirtimeSeconds == 0x12345678)
    }

    @Test("RemoteNodeStatus roomPostsCount with maximum values")
    func remoteNodeStatusRoomPostsCountMax() {
        // Max UInt16 for both fields
        let status = createTestRemoteNodeStatus(rxAirtimeSeconds: 0xFFFFFFFF)
        #expect(status.roomPostsCount == 0xFFFF)
        #expect(status.roomPostPushCount == 0xFFFF)
    }

    @Test("RemoteNodeStatus roomPostsCount with zero")
    func remoteNodeStatusRoomPostsCountZero() {
        let status = createTestRemoteNodeStatus(rxAirtimeSeconds: 0)
        #expect(status.roomPostsCount == 0)
        #expect(status.roomPostPushCount == 0)
    }

    // MARK: - decodeMessageV3 Tests

    @Test("decodeMessageV3 extracts author prefix for signedPlain messages")
    func decodeMessageV3ExtractsAuthorPrefix() throws {
        // Build a signedPlain message frame
        let authorPrefix = Data([0x01, 0x02, 0x03, 0x04])
        let messageText = "Hello room!"
        let data = buildMessageV3Frame(
            textType: .signedPlain,
            authorPrefix: authorPrefix,
            text: messageText
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.textType == .signedPlain)
        #expect(frame.extraData == authorPrefix)
        #expect(frame.text == messageText)
    }

    @Test("decodeMessageV3 returns nil extraData for plain messages")
    func decodeMessageV3ReturnsNilExtraDataForPlain() throws {
        let messageText = "Hello world!"
        let data = buildMessageV3Frame(
            textType: .plain,
            authorPrefix: nil,
            text: messageText
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.textType == .plain)
        #expect(frame.extraData == nil)
        #expect(frame.text == messageText)
    }

    @Test("decodeMessageV3 trims control characters from text")
    func decodeMessageV3TrimsControlCharacters() throws {
        let messageText = "Hello\0\0\0"
        let data = buildMessageV3Frame(
            textType: .plain,
            authorPrefix: nil,
            text: messageText
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.text == "Hello")
    }

    @Test("decodeMessageV3 extracts sender public key prefix")
    func decodeMessageV3ExtractsSenderPrefix() throws {
        let senderPrefix = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let data = buildMessageV3Frame(
            textType: .plain,
            senderPrefix: senderPrefix,
            authorPrefix: nil,
            text: "Test"
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.senderPublicKeyPrefix == senderPrefix)
    }

    @Test("decodeMessageV3 extracts path length")
    func decodeMessageV3ExtractsPathLength() throws {
        let data = buildMessageV3Frame(
            textType: .plain,
            authorPrefix: nil,
            text: "Test",
            pathLength: 3
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.pathLength == 3)
    }

    @Test("decodeMessageV3 extracts timestamp")
    func decodeMessageV3ExtractsTimestamp() throws {
        let timestamp: UInt32 = 1702500000
        let data = buildMessageV3Frame(
            textType: .plain,
            authorPrefix: nil,
            text: "Test",
            timestamp: timestamp
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.timestamp == timestamp)
    }

    @Test("decodeMessageV3 extracts SNR")
    func decodeMessageV3ExtractsSNR() throws {
        let data = buildMessageV3Frame(
            textType: .plain,
            authorPrefix: nil,
            text: "Test",
            snr: -10
        )

        let frame = try FrameCodec.decodeMessageV3(from: data)
        #expect(frame.snr == -10)
    }

    @Test("decodeMessageV3 throws for invalid data")
    func decodeMessageV3ThrowsForInvalidData() {
        // Too short
        let shortData = Data([ResponseCode.contactMessageReceivedV3.rawValue, 0x00])
        #expect(throws: ProtocolError.self) {
            try FrameCodec.decodeMessageV3(from: shortData)
        }

        // Wrong response code
        let wrongCode = Data(repeating: 0xFF, count: 20)
        #expect(throws: ProtocolError.self) {
            try FrameCodec.decodeMessageV3(from: wrongCode)
        }
    }

    // MARK: - LoginTimeoutConfig Tests

    @Test("LoginTimeoutConfig.timeout for path length 0 returns 5 seconds")
    func loginTimeoutConfigPathLength0() {
        let timeout = LoginTimeoutConfig.timeout(forPathLength: 0)
        #expect(timeout == .seconds(5))
    }

    @Test("LoginTimeoutConfig.timeout for path length 3 returns 35 seconds")
    func loginTimeoutConfigPathLength3() {
        let timeout = LoginTimeoutConfig.timeout(forPathLength: 3)
        #expect(timeout == .seconds(35))
    }

    @Test("LoginTimeoutConfig.timeout for path length 10 returns max 60 seconds")
    func loginTimeoutConfigPathLength10() {
        let timeout = LoginTimeoutConfig.timeout(forPathLength: 10)
        #expect(timeout == .seconds(60))
    }

    @Test("LoginTimeoutConfig.timeout for very large path length caps at max")
    func loginTimeoutConfigPathLengthLarge() {
        let timeout = LoginTimeoutConfig.timeout(forPathLength: 100)
        #expect(timeout == .seconds(60))
    }

    // MARK: - Test Helpers

    private func createTestRemoteNodeStatus(rxAirtimeSeconds: UInt32) -> RemoteNodeStatus {
        RemoteNodeStatus(
            publicKeyPrefix: Data(repeating: 0x00, count: 6),
            batteryMillivolts: 4200,
            txQueueLength: 0,
            noiseFloor: -110,
            lastRssi: -80,
            packetsReceived: 100,
            packetsSent: 50,
            airtimeSeconds: 1000,
            uptimeSeconds: 3600,
            sentFlood: 10,
            sentDirect: 40,
            receivedFlood: 60,
            receivedDirect: 40,
            fullEvents: 0,
            lastSnr: 10.5,
            directDuplicates: 5,
            floodDuplicates: 3,
            rxAirtimeSeconds: rxAirtimeSeconds
        )
    }

    private func buildMessageV3Frame(
        textType: TextType,
        senderPrefix: Data = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]),
        authorPrefix: Data?,
        text: String,
        pathLength: UInt8 = 0,
        timestamp: UInt32 = 1702500000,
        snr: Int8 = 0
    ) -> Data {
        var data = Data()
        // [0] Response code
        data.append(ResponseCode.contactMessageReceivedV3.rawValue)
        // [1] SNR
        data.append(UInt8(bitPattern: snr))
        // [2-3] Reserved
        data.append(contentsOf: [0x00, 0x00])
        // [4-9] Sender public key prefix
        data.append(senderPrefix)
        // [10] Path length
        data.append(pathLength)
        // [11] Text type
        data.append(textType.rawValue)
        // [12-15] Timestamp (little-endian)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })

        if textType == .signedPlain, let authorPrefix {
            // [16-19] Author key prefix
            data.append(authorPrefix)
            // [20+] Text
            data.append(contentsOf: text.utf8)
        } else {
            // [16+] Text
            data.append(contentsOf: text.utf8)
        }

        return data
    }
}
