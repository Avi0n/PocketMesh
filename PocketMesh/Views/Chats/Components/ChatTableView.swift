import UIKit
import SwiftUI

enum ChatScrollToMentionPolicy {
    static func shouldScrollToBottom(mentionTargetID: AnyHashable?, newestItemID: AnyHashable?) -> Bool {
        guard let mentionTargetID, let newestItemID else { return false }
        return mentionTargetID == newestItemID
    }
}

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
    /// O(1) lookup for items by ID (replaces O(n) first(where:) in cell provider)
    private var itemsByID: [Item.ID: Item] = [:]
    /// O(1) index lookup for scroll-to-item (replaces O(n) firstIndex(where:))
    private var itemIndexByID: [Item.ID: Int] = [:]
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

    /// Callback when user scrolls near the top (oldest messages)
    var onNearTop: (() -> Void)?

    /// Whether pagination is in progress (skip auto-scroll during pagination)
    var isLoadingOlderMessages = false

    /// Callback when a mention becomes visible
    var onMentionBecameVisible: ((Item.ID) -> Void)?

    /// Closure to check if an item contains an unseen self-mention
    var isUnseenMention: ((Item) -> Bool)?

    /// Tracks mention IDs that have already been reported as visible (prevents duplicate callbacks)
    private var markedMentionIDs: Set<Item.ID> = []

    /// Current keyboard height for inset calculation
    private var keyboardHeight: CGFloat = 0

    /// Flag to prevent scroll delegate from overriding isAtBottom during programmatic scroll
    private(set) var isScrollingToBottom = false

    /// Target item ID for programmatic scroll (used to reload cell after scroll completes)
    private var scrollTargetItemID: Item.ID?

    private var pendingScrollTargetID: Item.ID?
    private var pendingScrollTask: Task<Void, Never>?
    private var isUserInteracting = false
    private var isScrollingToTarget = false

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
                  let item = self.itemsByID[itemID] else {
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
                    .minSize(width: 0, height: 0)
                    .background(.clear)
                } else {
                    cell.contentConfiguration = UIHostingConfiguration {
                        contentProvider(item)
                    }
                    .margins(.all, 0)
                    .minSize(width: 0, height: 0)
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

        // Build O(1) lookup dictionaries
        itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        itemIndexByID = Dictionary(uniqueKeysWithValues: newItems.enumerated().map { ($0.element.id, $0.offset) })

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

        // Handle unread tracking
        let hasNewItems = newItems.count > previousCount
        // Detect prepend (pagination) vs append (new messages): prepend changes first item ID
        let wasPrepend = previousCount > 0 && hasNewItems && oldItems.first?.id != newItems.first?.id

        if !wasAtBottom && previousCount > 0 && hasNewItems && !wasPrepend {
            // New messages arrived while scrolled up (not pagination)
            let newMessageCount = newItems.count - previousCount
            unreadCount += newMessageCount
            onScrollStateChanged?(isAtBottom, unreadCount)
        } else if wasAtBottom && hasNewItems && !skipAutoScroll && !isScrollingToBottom && !wasPrepend {
            // At bottom with NEW items, auto-scroll to newest
            // Only scroll if there are actually new items (not just SwiftUI re-renders)
            lastSeenItemID = newItems.last?.id
            scrollToBottom(animated: animated && previousCount > 0)
        }

        // Check for visible mentions after layout settles (handles mentions visible on load)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.checkVisibleMentions()
        }

        if let pendingID = pendingScrollTargetID {
            schedulePendingScroll(for: pendingID, delay: .milliseconds(120))
        }
    }

    // MARK: - Scroll Control

    /// Called before updateItems when user sends a message.
    /// Sets isAtBottom = true so updateItems won't increment unread.
    func prepareForUserSend() {
        isAtBottom = true
        unreadCount = 0
        skipAutoScroll = true  // Prevent updateItems from calling scrollToBottom (we'll do it explicitly)
    }

    func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }

        let alreadyAtBottom = tableView.contentOffset.y <= 1

        // Set state before scroll to prevent scroll delegate from overriding
        isAtBottom = true
        unreadCount = 0
        lastSeenItemID = items.last?.id

        // If already at bottom, just update state - no scroll needed.
        // In a flipped table view with short content, scrollToRow miscalculates
        // the target position and over-scrolls, pushing messages off screen.
        if alreadyAtBottom {
            isScrollingToBottom = false
            onScrollStateChanged?(isAtBottom, unreadCount)
            skipAutoScroll = false
            return
        }

        // Only update isScrollingToBottom if not already set (keyboardWillShow may have set it)
        if !isScrollingToBottom {
            isScrollingToBottom = animated
        }

        // In flipped table with reversed data: row 0 = newest message
        // Scroll row 0 to .top anchor (which is visual BOTTOM in flipped table)
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)

        if !animated {
            isScrollingToBottom = false
        }

        onScrollStateChanged?(isAtBottom, unreadCount)

        // Clear skipAutoScroll after explicit scroll (it was set by prepareForUserSend)
        skipAutoScroll = false
    }

    func scrollToItem(id: Item.ID, animated: Bool) {
        // Use O(1) dictionary lookup instead of O(n) firstIndex
        guard itemIndexByID[id] != nil else { return }

        // Track target for post-scroll reload (fixes UIHostingConfiguration layout timing)
        scrollTargetItemID = id
        pendingScrollTargetID = id

        pendingScrollTask?.cancel()
        pendingScrollTask = nil

        if animated {
            schedulePendingScroll(for: id, delay: .milliseconds(180))
        } else {
            pendingScrollTargetID = nil
            centerItem(id: id, animated: false)
            reloadTargetCell()
        }
    }

    /// Reloads the scroll target cell to fix UIHostingConfiguration layout timing issues
    private func reloadTargetCell() {
        guard let targetID = scrollTargetItemID else { return }
        scrollTargetItemID = nil

        // Force cell reconfiguration via snapshot reload
        var snapshot = dataSource?.snapshot() ?? NSDiffableDataSourceSnapshot<Section, Item.ID>()
        if snapshot.itemIdentifiers.contains(targetID) {
            snapshot.reloadItems([targetID])
            dataSource?.apply(snapshot, animatingDifferences: false)
        }
    }

    private func centerItem(id: Item.ID, animated: Bool) {
        guard let itemIndex = itemIndexByID[id] else { return }
        let rowIndex = items.count - 1 - itemIndex
        let indexPath = IndexPath(row: rowIndex, section: 0)
        tableView.layoutIfNeeded()
        isScrollingToTarget = true
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)

        if !animated {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.isScrollingToTarget = false
            }
        }
    }

    private func schedulePendingScroll(for id: Item.ID, delay: Duration) {
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard self.pendingScrollTargetID == id, !self.isUserInteracting else { return }
            self.pendingScrollTargetID = nil
            self.centerItem(id: id, animated: true)
            self.pendingScrollTask = nil
        }
    }

    // MARK: - Scroll Tracking

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateIsAtBottom()
        checkVisibleMentions()
        checkNearTop()
    }

    private func checkVisibleMentions() {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              let isUnseenMention,
              let onMentionBecameVisible else { return }

        for indexPath in visibleIndexPaths {
            guard indexPath.row < items.count else { continue }
            // Items are reversed in table: row 0 = newest (items.last)
            let reversedIndex = items.count - 1 - indexPath.row
            guard reversedIndex >= 0 else { continue }
            let item = items[reversedIndex]
            // Only report each mention once per session
            if !markedMentionIDs.contains(item.id) && isUnseenMention(item) {
                markedMentionIDs.insert(item.id)
                onMentionBecameVisible(item.id)
            }
        }
    }

    /// Resets the debouncing state (call when conversation changes)
    func resetMarkedMentions() {
        markedMentionIDs.removeAll()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isUserInteracting = false
        }
        if !decelerate {
            finalizeScrollPosition()
        }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserInteracting = false
        finalizeScrollPosition()
    }

    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // Clear flag when programmatic scroll animation completes
        let wasScrollingToBottom = isScrollingToBottom
        isScrollingToBottom = false
        isScrollingToTarget = false

        // Reload target cell after scroll completes to fix UIHostingConfiguration layout timing
        reloadTargetCell()

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

    /// Check if user has scrolled near the top (oldest messages) and trigger callback
    private func checkNearTop() {
        if isScrollingToBottom || isScrollingToTarget || scrollTargetItemID != nil {
            return
        }
        guard let visibleRows = tableView.indexPathsForVisibleRows,
              let highestRow = visibleRows.map(\.row).max() else { return }

        let totalRows = items.count
        let distanceFromTop = totalRows - highestRow

        // Trigger when within 10 messages of the oldest
        if distanceFromTop <= 10 {
            onNearTop?()
        }
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserInteracting = true
        pendingScrollTargetID = nil
        pendingScrollTask?.cancel()
        pendingScrollTask = nil
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
    @Binding var scrollToMentionRequest: Int
    var isUnseenMention: ((Item) -> Bool)?
    var onMentionBecameVisible: ((Item.ID) -> Void)?
    var mentionTargetID: Item.ID?
    var onNearTop: (() -> Void)?
    var isLoadingOlderMessages: Bool = false

    func makeUIViewController(context: Context) -> ChatTableViewController<Item> {
        let controller = ChatTableViewController<Item>()
        controller.configure { item in
            AnyView(cellContent(item))
        }
        // Callback set up in updateUIViewController
        context.coordinator.lastScrollRequest = scrollToBottomRequest
        controller.isUnseenMention = isUnseenMention
        context.coordinator.lastMentionRequest = scrollToMentionRequest
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

        // Update mention detection closures
        controller.isUnseenMention = isUnseenMention
        controller.onMentionBecameVisible = onMentionBecameVisible

        // Update pagination state
        controller.onNearTop = onNearTop
        controller.isLoadingOlderMessages = isLoadingOlderMessages

        // Check for scroll-to-mention request
        let shouldScrollToMention = scrollToMentionRequest != context.coordinator.lastMentionRequest
        var shouldScrollMentionToBottom = false
        var mentionScrollTargetID: Item.ID?

        if shouldScrollToMention {
            context.coordinator.lastMentionRequest = scrollToMentionRequest
            mentionScrollTargetID = mentionTargetID

            let newestItemID = items.last?.id
            shouldScrollMentionToBottom = ChatScrollToMentionPolicy.shouldScrollToBottom(
                mentionTargetID: mentionTargetID.map { AnyHashable($0) },
                newestItemID: newestItemID.map { AnyHashable($0) }
            )
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
        } else if shouldScrollToMention {
            if shouldScrollMentionToBottom {
                controller.scrollToBottom(animated: true)
            } else if let targetID = mentionScrollTargetID {
                controller.scrollToItem(id: targetID, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastScrollRequest: Int = 0
        var lastMentionRequest: Int = 0
        var setIsAtBottom: ((Bool) -> Void)?
        var setUnreadCount: ((Int) -> Void)?
    }
}
