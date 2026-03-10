import Testing
import SwiftUI
import UIKit
@testable import PocketMesh

@Suite("ChatTableView Snapshot Regression Tests")
@MainActor
struct ChatTableViewSnapshotRegressionTests {

    private struct TestMessageItem: Identifiable, Hashable, Sendable {
        let id: UUID
        let text: String
        let revision: Int
    }

    private func waitForRowCount(
        _ expectedCount: Int,
        in controller: ChatTableViewController<TestMessageItem, Text>,
        context: String
    ) async throws {
        try await waitUntil(
            timeout: .seconds(30),
            pollingInterval: .milliseconds(20),
            "table rows should match expected count for \(context)"
        ) {
            controller.tableView.numberOfRows(inSection: 0) == expectedCount
        }
    }

    @Test("Scroll completion reload does not re-enter diffable apply during animated updates")
    func scrollCompletionReloadIsSafeDuringAnimatedUpdates() async throws {
        let controller = ChatTableViewController<TestMessageItem, Text>()
        controller.configure { item in
            Text(item.text)
        }
        controller.loadViewIfNeeded()

        var items = (0..<120).map { index in
            TestMessageItem(id: UUID(), text: "Message \(index)", revision: 0)
        }
        let targetIndex = 60
        let targetID = items[targetIndex].id

        controller.updateItems(items, animated: false)
        try await waitForRowCount(items.count, in: controller, context: "initial seed")

        for iteration in 1...5 {
            controller.scrollToItem(id: targetID, animated: true)

            var updatedItems = items
            updatedItems[targetIndex] = TestMessageItem(
                id: targetID,
                text: "Message \(targetIndex) iteration \(iteration)",
                revision: iteration
            )
            updatedItems.append(
                TestMessageItem(
                    id: UUID(),
                    text: "Appended \(iteration)",
                    revision: 0
                )
            )

            controller.updateItems(updatedItems, animated: true)
            controller.scrollViewDidEndScrollingAnimation(controller.tableView)
            items = updatedItems
        }

        try await waitForRowCount(items.count, in: controller, context: "final snapshot")

        #expect(controller.tableView.numberOfRows(inSection: 0) == items.count)
    }
}
