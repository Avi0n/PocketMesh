import XCTest
@testable import PocketMesh
@testable import PocketMeshServices

final class ConversationFilteringTests: XCTestCase {

    // MARK: - Test Data

    private func makeContact(
        name: String,
        isFavorite: Bool = false,
        unreadCount: Int = 0,
        isMuted: Bool = false
    ) -> ContactDTO {
        ContactDTO(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data(repeating: 0, count: 32),
            name: name,
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: isMuted,
            isFavorite: isFavorite,
            isDiscovered: false,
            lastMessageDate: Date(),
            unreadCount: unreadCount
        )
    }

    private func makeChannel(
        name: String,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        isFavorite: Bool = false
    ) -> ChannelDTO {
        ChannelDTO(
            id: UUID(),
            deviceID: UUID(),
            index: 1,
            name: name,
            secret: Data(repeating: 0, count: 16),
            isEnabled: true,
            lastMessageDate: Date(),
            unreadCount: unreadCount,
            isMuted: isMuted,
            isFavorite: isFavorite
        )
    }

    private func makeRoom(
        name: String,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        isFavorite: Bool = false
    ) -> RemoteNodeSessionDTO {
        RemoteNodeSessionDTO(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data(repeating: 0, count: 32),
            name: name,
            role: .roomServer,
            isConnected: true,
            lastConnectedDate: Date(),
            unreadCount: unreadCount,
            isMuted: isMuted,
            isFavorite: isFavorite
        )
    }

    // MARK: - Filter Tests

    func testNilFilterShowsAll() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice")),
            .channel(makeChannel(name: "General")),
            .room(makeRoom(name: "Room1"))
        ]

        let result = conversations.filtered(by: nil, searchText: "")

        XCTAssertEqual(result.count, 3)
    }

    func testFilterByUnread() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice", unreadCount: 5)),
            .direct(makeContact(name: "Bob", unreadCount: 0)),
            .channel(makeChannel(name: "General", unreadCount: 2))
        ]

        let result = conversations.filtered(by: .unread, searchText: "")

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.unreadCount > 0 })
    }

    func testFilterByDirectMessages() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice")),
            .direct(makeContact(name: "Bob")),
            .channel(makeChannel(name: "General")),
            .room(makeRoom(name: "Room1"))
        ]

        let result = conversations.filtered(by: .directMessages, searchText: "")

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy {
            if case .direct = $0 { return true }
            return false
        })
    }

    func testFilterByChannelsIncludesRooms() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice")),
            .channel(makeChannel(name: "General")),
            .room(makeRoom(name: "Room1"))
        ]

        let result = conversations.filtered(by: .channels, searchText: "")

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy {
            if case .channel = $0 { return true }
            if case .room = $0 { return true }
            return false
        })
    }

    func testFilterByFavorites() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice", isFavorite: true)),
            .direct(makeContact(name: "Bob", isFavorite: false)),
            .channel(makeChannel(name: "General", isFavorite: true)),
            .channel(makeChannel(name: "Random", isFavorite: false)),
            .room(makeRoom(name: "FavRoom", isFavorite: true)),
            .room(makeRoom(name: "OtherRoom", isFavorite: false))
        ]

        let result = conversations.filtered(by: .favorites, searchText: "")

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.isFavorite })
    }

    func testSearchWithinFilter() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice", unreadCount: 1)),
            .direct(makeContact(name: "Bob", unreadCount: 1)),
            .direct(makeContact(name: "Charlie", unreadCount: 0))
        ]

        let result = conversations.filtered(by: .unread, searchText: "Ali")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Alice")
    }

    func testSearchOnlyWithoutFilter() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice")),
            .direct(makeContact(name: "Bob")),
            .channel(makeChannel(name: "Alpha"))
        ]

        let result = conversations.filtered(by: nil, searchText: "Al")

        XCTAssertEqual(result.count, 2)
    }

    func testEmptyResultsWhenNoMatch() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice")),
            .direct(makeContact(name: "Bob"))
        ]

        let result = conversations.filtered(by: nil, searchText: "Zzzz")

        XCTAssertTrue(result.isEmpty)
    }

    func testUnreadFilterExcludesMuted() {
        let conversations: [Conversation] = [
            .direct(makeContact(name: "Alice", unreadCount: 5, isMuted: false)),
            .direct(makeContact(name: "Bob", unreadCount: 3, isMuted: true)),
            .channel(makeChannel(name: "General", unreadCount: 2, isMuted: false))
        ]

        let result = conversations.filtered(by: .unread, searchText: "")

        // Bob is muted, so should be excluded even with unreads
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.displayName == "Bob" })
    }
}
