import UIKit
import SwiftUI

/// UIKit table view controller with flipped orientation for chat-style scrolling
/// Newest messages appear at visual bottom, keyboard handling via native UIKit
@MainActor
final class ChatTableViewController<Item: Identifiable & Hashable & Sendable>: UITableViewController where Item.ID: Sendable {

    // MARK: - Types

    private enum Section: Hashable {
        case main
    }

    // MARK: - Properties

    private var items: [Item] = []
    private var cellContentProvider: ((Item) -> AnyView)?
    private var dataSource: UITableViewDiffableDataSource<Section, Item.ID>?

    /// Tracks scroll position relative to bottom
    private(set) var isAtBottom: Bool = true

    /// Count of unread messages (messages added while scrolled up)
    private(set) var unreadCount: Int = 0

    /// ID of last message user has seen (for unread tracking)
    private var lastSeenItemID: Item.ID?

    /// Callback when scroll state changes
    var onScrollStateChanged: ((Bool, Int) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Flip the table view for chat-style bottom anchoring
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)

        // UIKit keyboard handling - bypasses SwiftUI bugs
        tableView.keyboardDismissMode = .onDrag

        // Visual setup
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.allowsSelection = false

        // Register cell
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        // Configure data source
        configureDataSource()
    }

    // MARK: - Configuration

    func configure(cellContent: @escaping (Item) -> AnyView) {
        self.cellContentProvider = cellContent
    }

    // MARK: - Data Source

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item.ID>(tableView: tableView) { [weak self] tableView, indexPath, itemID in
            guard let self,
                  let item = self.items.first(where: { $0.id == itemID }) else {
                return UITableViewCell()
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

            // Flip cell content back to normal orientation
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none

            // Embed SwiftUI content
            if let contentProvider = self.cellContentProvider {
                cell.contentConfiguration = UIHostingConfiguration {
                    contentProvider(item)
                }
                .margins(.all, 0)
            }

            return cell
        }
    }

    // MARK: - Update Items

    func updateItems(_ newItems: [Item], animated: Bool = true) {
        let previousCount = items.count
        let wasAtBottom = isAtBottom
        items = newItems

        // Apply snapshot
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(newItems.map(\.id))
        dataSource?.apply(snapshot, animatingDifferences: animated && previousCount > 0)

        // Handle unread tracking
        if !wasAtBottom && previousCount > 0 && newItems.count > previousCount {
            // New messages arrived while scrolled up
            let newMessageCount = newItems.count - previousCount
            unreadCount += newMessageCount
            onScrollStateChanged?(isAtBottom, unreadCount)
        } else if wasAtBottom && !newItems.isEmpty {
            // At bottom, auto-scroll to newest
            lastSeenItemID = newItems.last?.id
            scrollToBottom(animated: animated && previousCount > 0)
        }
    }

    // MARK: - Scroll Control

    func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }

        // In flipped table: last item at .bottom anchor = visual bottom
        let lastIndex = items.count - 1
        let indexPath = IndexPath(row: lastIndex, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)

        // Clear unread when scrolling to bottom
        unreadCount = 0
        lastSeenItemID = items.last?.id
        isAtBottom = true
        onScrollStateChanged?(isAtBottom, unreadCount)
    }

    // MARK: - Scroll Tracking

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateIsAtBottom()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finalizeScrollPosition()
        }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finalizeScrollPosition()
    }

    private func updateIsAtBottom() {
        // In flipped table: visual bottom = contentOffset near top edge
        let offset = tableView.contentOffset.y
        let inset = tableView.adjustedContentInset.top
        let newIsAtBottom = offset <= inset + 10 // 10pt threshold

        if newIsAtBottom != isAtBottom {
            isAtBottom = newIsAtBottom
            onScrollStateChanged?(isAtBottom, unreadCount)
        }
    }

    private func finalizeScrollPosition() {
        if isAtBottom {
            // User scrolled to bottom, clear unread
            unreadCount = 0
            lastSeenItemID = items.last?.id
            onScrollStateChanged?(isAtBottom, unreadCount)
        }
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper for ChatTableViewController
struct ChatTableView<Item: Identifiable & Hashable & Sendable, Content: View>: UIViewControllerRepresentable where Item.ID: Sendable {

    let items: [Item]
    let cellContent: (Item) -> Content
    @Binding var isAtBottom: Bool
    @Binding var unreadCount: Int
    @Binding var scrollToBottomRequest: Int

    func makeUIViewController(context: Context) -> ChatTableViewController<Item> {
        let controller = ChatTableViewController<Item>()
        controller.configure { item in
            AnyView(cellContent(item))
        }
        controller.onScrollStateChanged = { atBottom, unread in
            Task { @MainActor in
                isAtBottom = atBottom
                unreadCount = unread
            }
        }
        context.coordinator.lastScrollRequest = scrollToBottomRequest
        return controller
    }

    func updateUIViewController(_ controller: ChatTableViewController<Item>, context: Context) {
        // Update items
        controller.updateItems(items)

        // Handle scroll-to-bottom requests
        if scrollToBottomRequest != context.coordinator.lastScrollRequest {
            context.coordinator.lastScrollRequest = scrollToBottomRequest
            controller.scrollToBottom(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastScrollRequest: Int = 0
    }
}
