import UIKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "PocketMesh", category: "ChatTableView")

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

    /// Current keyboard height for inset calculation
    private var keyboardHeight: CGFloat = 0

    /// Flag to prevent scroll delegate from overriding isAtBottom during programmatic scroll
    private(set) var isScrollingToBottom = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Flip the table view for chat-style bottom anchoring
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)

        // UIKit keyboard handling - bypasses SwiftUI bugs
        tableView.keyboardDismissMode = .onDrag

        // Visual setup
        tableView.separatorStyle = .none
        if #available(iOS 26.0, *) {
            // Clear and non-opaque allows Liquid Glass effects on nav/input bars
            tableView.backgroundColor = .clear
            tableView.isOpaque = false
            tableView.contentInsetAdjustmentBehavior = .always

            // Scroll edge effects don't work correctly with flipped table transform.
            // Hide both - the nav bar and input bar provide their own Liquid Glass blur.
            tableView.topEdgeEffect.isHidden = true
            tableView.bottomEdgeEffect.isHidden = true
        } else {
            tableView.backgroundColor = .systemBackground
        }
        tableView.allowsSelection = false

        // Register cell
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        // Configure data source
        configureDataSource()

        // Manual keyboard observation (UIKit auto-adjustment doesn't work in SwiftUI embed)
        setupKeyboardObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let wasAtBottom = isAtBottom
        keyboardHeight = keyboardFrame.height

        logger.debug("keyboardWillShow: height=\(self.keyboardHeight), wasAtBottom=\(wasAtBottom)")

        // SwiftUI handles frame changes for keyboard, so we don't add content inset.
        // Just scroll to bottom after layout settles if we were at bottom.
        if wasAtBottom {
            // Set guard flag now to prevent scroll delegate from reacting to contentOffset
            // oscillations during keyboard animation. Critical when content is shorter
            // than visible area - the bouncing would otherwise cause isAtBottom to flip.
            isScrollingToBottom = true

            // Delay to let SwiftUI complete its layout pass
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.scrollToBottom(animated: true)
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        logger.debug("keyboardWillHide")
        keyboardHeight = 0
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

            // Flip cell back to normal orientation (must be cell, not contentView,
            // because UIHostingConfiguration replaces contentView hierarchy)
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none

            // Embed SwiftUI content
            if let contentProvider = self.cellContentProvider {
                if #available(iOS 26.0, *) {
                    cell.contentConfiguration = UIHostingConfiguration {
                        contentProvider(item)
                    }
                    .margins(.all, 0)
                    .background(.clear)
                } else {
                    cell.contentConfiguration = UIHostingConfiguration {
                        contentProvider(item)
                    }
                    .margins(.all, 0)
                }
            }

            return cell
        }
    }

    // MARK: - Update Items

    /// When true, updateItems will skip auto-scroll (caller will scroll explicitly)
    private var skipAutoScroll = false

    func updateItems(_ newItems: [Item], animated: Bool = true) {
        let previousCount = items.count
        let wasAtBottom = isAtBottom
        let oldItems = items
        items = newItems

        logger.debug("updateItems: previousCount=\(previousCount), newCount=\(newItems.count), wasAtBottom=\(wasAtBottom)")

        // Apply snapshot with REVERSED order: newest-first for flipped table
        // Row 0 = newest message → appears at visual bottom after flip
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(newItems.reversed().map(\.id))

        // Find items that changed content (same ID, different hash).
        // Without reloading these, diffable data source won't update cells for items with same ID.
        let oldItemsByID = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })
        let changedIDs = newItems.compactMap { newItem -> Item.ID? in
            guard let oldItem = oldItemsByID[newItem.id] else { return nil }
            return oldItem != newItem ? newItem.id : nil
        }

        // Two-phase apply to handle structural changes and content updates differently:
        // 1. Structural changes (new/deleted items) - animate for smooth UX
        // 2. Content updates (status changes) - no animation to prevent flash
        let hasStructuralChanges = newItems.count != oldItems.count ||
            Set(newItems.map(\.id)) != Set(oldItems.map(\.id))

        if hasStructuralChanges {
            // Apply structural changes with animation
            dataSource?.apply(snapshot, animatingDifferences: animated && previousCount > 0)

            // Then reload changed items without animation (separate apply)
            if !changedIDs.isEmpty {
                var reloadSnapshot = dataSource?.snapshot() ?? snapshot
                reloadSnapshot.reloadItems(changedIDs)
                dataSource?.apply(reloadSnapshot, animatingDifferences: false)
            }
        } else if !changedIDs.isEmpty {
            // No structural changes, just content updates - reload without animation
            snapshot.reloadItems(changedIDs)
            dataSource?.apply(snapshot, animatingDifferences: false)
        } else {
            // No changes at all, but still apply to sync state
            dataSource?.apply(snapshot, animatingDifferences: false)
        }

        logger.debug("updateItems: snapshot applied, isAtBottom now=\(self.isAtBottom)")

        // Handle unread tracking
        let hasNewItems = newItems.count > previousCount

        if !wasAtBottom && previousCount > 0 && hasNewItems {
            // New messages arrived while scrolled up
            let newMessageCount = newItems.count - previousCount
            unreadCount += newMessageCount
            logger.debug("updateItems: scrolled up, incrementing unread to \(self.unreadCount)")
            onScrollStateChanged?(isAtBottom, unreadCount)
        } else if wasAtBottom && hasNewItems && !skipAutoScroll && !isScrollingToBottom {
            // At bottom with NEW items, auto-scroll to newest
            // Only scroll if there are actually new items (not just SwiftUI re-renders)
            lastSeenItemID = newItems.last?.id
            logger.debug("updateItems: was at bottom with new items, calling scrollToBottom")
            scrollToBottom(animated: animated && previousCount > 0)
        }
    }

    // MARK: - Scroll Control

    /// Called before updateItems when user sends a message.
    /// Sets isAtBottom = true so updateItems won't increment unread.
    func prepareForUserSend() {
        isAtBottom = true
        unreadCount = 0
        skipAutoScroll = true  // Prevent updateItems from calling scrollToBottom (we'll do it explicitly)
        logger.debug("prepareForUserSend: reset isAtBottom=true, unreadCount=0")
    }

    func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }

        // If already at bottom, no animation will occur - don't set flag
        // UIKit won't fire scrollViewDidEndScrollingAnimation when there's no movement
        let alreadyAtBottom = tableView.contentOffset.y <= 1

        logger.debug("scrollToBottom: animated=\(animated), alreadyAtBottom=\(alreadyAtBottom), contentOffset.y=\(self.tableView.contentOffset.y)")

        // Set state before scroll to prevent scroll delegate from overriding
        isAtBottom = true
        unreadCount = 0
        lastSeenItemID = items.last?.id

        // Only update isScrollingToBottom if not already set (keyboardWillShow may have set it)
        if !isScrollingToBottom {
            isScrollingToBottom = animated && !alreadyAtBottom
        }

        // In flipped table with reversed data: row 0 = newest message
        // Scroll row 0 to .top anchor (which is visual BOTTOM in flipped table)
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)

        // Clear flag if no animation will run (scrollViewDidEndScrollingAnimation won't fire).
        // When already at bottom during keyboard animation, keep flag set - it will be cleared
        // after a short delay to allow layout to settle.
        if !animated {
            isScrollingToBottom = false
        } else if alreadyAtBottom && isScrollingToBottom {
            // Keyboard triggered scroll when already at bottom - clear after layout settles
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.isScrollingToBottom = false
            }
        }

        onScrollStateChanged?(isAtBottom, unreadCount)

        // Clear skipAutoScroll after explicit scroll (it was set by prepareForUserSend)
        skipAutoScroll = false
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

    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // Clear flag when programmatic scroll animation completes
        let wasScrollingToBottom = isScrollingToBottom
        isScrollingToBottom = false

        if wasScrollingToBottom {
            // We just finished a programmatic scroll-to-bottom
            // Use larger threshold since animation might not land exactly at 0
            let atBottom = scrollView.contentOffset.y <= 10
            if atBottom {
                // Confirm we're at bottom - this is authoritative
                isAtBottom = true
                unreadCount = 0
                onScrollStateChanged?(isAtBottom, unreadCount)
                return
            }
        }

        // For user-initiated scrolls or if we didn't land at bottom, use normal check
        updateIsAtBottom()
    }

    private func updateIsAtBottom() {
        // Don't override isAtBottom during programmatic scroll-to-bottom animation
        // This prevents the FAB from flickering when user sends a message
        if isScrollingToBottom {
            return
        }

        // In flipped table, visual bottom = contentOffset.y near 0
        // Use small threshold to handle float imprecision
        let newIsAtBottom = tableView.contentOffset.y <= 1

        if newIsAtBottom != isAtBottom {
            logger.debug("updateIsAtBottom: changed \(self.isAtBottom) -> \(newIsAtBottom), contentOffset.y=\(self.tableView.contentOffset.y)")
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
        // Callback set up in updateUIViewController
        context.coordinator.lastScrollRequest = scrollToBottomRequest
        return controller
    }

    func updateUIViewController(_ controller: ChatTableViewController<Item>, context: Context) {
        // Update cell content provider each render cycle so reconfigured cells
        // get fresh closures (e.g., onRetry callback when message status changes)
        controller.configure { item in
            AnyView(cellContent(item))
        }

        // Store current binding setters in coordinator (updated each render cycle)
        // This ensures deferred callbacks always use fresh bindings
        context.coordinator.setIsAtBottom = { [self] in isAtBottom = $0 }
        context.coordinator.setUnreadCount = { [self] in unreadCount = $0 }

        // Controller callback defers to next run loop via coordinator.
        // SwiftUI blocks binding updates during updateUIViewController, so we must
        // defer the update to after the current update cycle completes.
        controller.onScrollStateChanged = { [weak coordinator = context.coordinator] atBottom, unread in
            DispatchQueue.main.async {
                coordinator?.setIsAtBottom?(atBottom)
                coordinator?.setUnreadCount?(unread)
            }
        }

        // Check for scroll-to-bottom request BEFORE updating items
        // This ensures user sends don't trigger unread badge
        let shouldForceScroll = scrollToBottomRequest != context.coordinator.lastScrollRequest

        if shouldForceScroll {
            context.coordinator.lastScrollRequest = scrollToBottomRequest
            // Mark as at bottom so updateItems won't increment unread
            controller.prepareForUserSend()
        }

        controller.updateItems(items)

        // Perform the scroll after items are updated
        if shouldForceScroll {
            controller.scrollToBottom(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastScrollRequest: Int = 0
        var setIsAtBottom: ((Bool) -> Void)?
        var setUnreadCount: ((Int) -> Void)?
    }
}
