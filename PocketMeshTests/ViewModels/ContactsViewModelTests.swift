import Testing
import Foundation
@testable import PocketMesh

// MARK: - ContactsViewModel Tests

@Suite("ContactsViewModel Tests")
@MainActor
struct ContactsViewModelTests {

    // MARK: - Loading State Tests

    @Test("hasLoadedOnce starts false")
    func hasLoadedOnceStartsFalse() {
        let viewModel = ContactsViewModel()
        #expect(viewModel.hasLoadedOnce == false)
    }

    @Test("isLoading starts false")
    func isLoadingStartsFalse() {
        let viewModel = ContactsViewModel()
        #expect(viewModel.isLoading == false)
    }

    @Test("contacts starts empty")
    func contactsStartsEmpty() {
        let viewModel = ContactsViewModel()
        #expect(viewModel.contacts.isEmpty)
    }

}
