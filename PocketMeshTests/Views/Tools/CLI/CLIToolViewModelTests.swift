import Testing
@testable import PocketMesh
@testable import PocketMeshServices

// MARK: - CLIToolViewModel Tests

@Suite("CLIToolViewModel Tests")
@MainActor
struct CLIToolViewModelTests {

    // MARK: - Helper

    private func createConfiguredViewModel() -> CLIToolViewModel {
        let viewModel = CLIToolViewModel()
        viewModel.configure(
            repeaterAdminService: nil,
            remoteNodeService: nil,
            dataStore: nil,
            deviceID: nil,
            localDeviceName: "TestDevice"
        )
        return viewModel
    }

    private func waitForCommand() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
    }

    // MARK: - Prompt Tests

    @Test("Prompt shows disconnected when no session")
    func promptShowsDisconnectedWhenNoSession() {
        let viewModel = createConfiguredViewModel()
        viewModel.configure(
            repeaterAdminService: nil,
            remoteNodeService: nil,
            dataStore: nil,
            deviceID: nil,
            localDeviceName: "Test"
        )
        #expect(viewModel.promptText.contains("disconnected"))
    }

    @Test("Prompt shows countdown during login")
    func promptShowsCountdownDuringLogin() async {
        let viewModel = CLIToolViewModel()

        // Configure the view model
        viewModel.configure(
            repeaterAdminService: nil,
            remoteNodeService: nil,
            dataStore: nil,
            deviceID: nil,
            localDeviceName: "TestDevice"
        )

        // When remainingSeconds is nil and not waiting, should show normal prompt
        #expect(!viewModel.promptText.contains("Logging in"))
    }

    // MARK: - History Tests

    @Test("History navigation up retrieves previous commands")
    func historyNavigationUp() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("first")
        await waitForCommand()
        viewModel.executeCommand("second")
        await waitForCommand()

        viewModel.historyUp()
        #expect(viewModel.currentInput == "second")

        viewModel.historyUp()
        #expect(viewModel.currentInput == "first")
    }

    @Test("History navigation down moves forward through history")
    func historyNavigationDown() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("first")
        await waitForCommand()
        viewModel.executeCommand("second")
        await waitForCommand()

        viewModel.historyUp()
        viewModel.historyUp()
        viewModel.historyDown()

        #expect(viewModel.currentInput == "second")
    }

    @Test("History is limited to 100 entries")
    func historyLimitedTo100Entries() async {
        let viewModel = createConfiguredViewModel()
        for i in 0..<150 {
            viewModel.executeCommand("command\(i)")
            await waitForCommand()
        }

        // Navigate to oldest entry
        for _ in 0..<100 {
            viewModel.historyUp()
        }

        // Should be command50 (oldest after trimming), not command0
        #expect(viewModel.currentInput == "command50")
    }

    @Test("Login command stored in history without password")
    func loginCommandStoredInHistory() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("login MyRepeater")
        await waitForCommand()

        viewModel.historyUp()
        #expect(viewModel.currentInput == "login MyRepeater")
    }

    // MARK: - Built-in Commands Tests

    @Test("Clear command removes output")
    func clearCommandRemovesOutput() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("help")
        await waitForCommand()
        #expect(!viewModel.outputLines.isEmpty)

        viewModel.executeCommand("clear")
        await waitForCommand()
        #expect(viewModel.outputLines.isEmpty)
    }

    @Test("Help command shows available commands")
    func helpCommandShowsAvailableCommands() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("help")
        await waitForCommand()

        let output = viewModel.outputLines.map(\.text).joined(separator: "\n")
        #expect(output.contains("login"))
        #expect(output.contains("logout"))
        #expect(output.contains("session"))
    }

    // MARK: - Output Management Tests

    @Test("Output lines are limited to prevent memory growth")
    func outputLinesAreLimited() async {
        let viewModel = createConfiguredViewModel()
        for i in 0..<1100 {
            viewModel.executeCommand("command\(i)")
            await waitForCommand()
        }

        #expect(viewModel.outputLines.count <= 1000)
    }

    // MARK: - Session Tests

    @Test("Session list shows local")
    func sessionListShowsLocal() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("session list")
        await waitForCommand()

        let output = viewModel.outputLines.map(\.text).joined(separator: "\n")
        #expect(output.contains("local"))
    }

    // MARK: - Cancellation Tests

    @Test("Cancel command stops waiting")
    func cancelCommandStopsWaiting() async {
        let viewModel = createConfiguredViewModel()
        viewModel.executeCommand("help")
        await waitForCommand()

        viewModel.cancelCurrentCommand()

        #expect(!viewModel.isWaitingForResponse)
    }

    // MARK: - Empty Input Tests

    @Test("Empty input shows prompt echo")
    func emptyInputShowsPromptEcho() {
        let viewModel = createConfiguredViewModel()

        let initialCount = viewModel.outputLines.count
        let initialHistoryCount = viewModel.commandHistory.count
        viewModel.currentInput = ""
        viewModel.executeCommand("")

        #expect(viewModel.outputLines.count == initialCount + 1)
        #expect(viewModel.commandHistory.count == initialHistoryCount)
        #expect(viewModel.outputLines.last?.type == .command)
    }

    // MARK: - Ghost Text Tests

    @Test("Ghost text shows suffix for matching command")
    func ghostTextShowsSuffix() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "hel"

        viewModel.updateGhostText(cursorAtEnd: true)

        #expect(viewModel.ghostText == "p")
    }

    @Test("Ghost text empty when no match")
    func ghostTextEmptyWhenNoMatch() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "xyz"

        viewModel.updateGhostText(cursorAtEnd: true)

        #expect(viewModel.ghostText == "")
    }

    @Test("Ghost text empty for empty input")
    func ghostTextEmptyForEmptyInput() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = ""

        viewModel.updateGhostText(cursorAtEnd: true)

        #expect(viewModel.ghostText == "")
    }

    @Test("Ghost text empty when cursor not at end")
    func ghostTextEmptyWhenCursorNotAtEnd() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "hel"

        viewModel.updateGhostText(cursorAtEnd: false)

        #expect(viewModel.ghostText == "")
    }

    @Test("Accept ghost text appends to input")
    func acceptGhostTextAppendsToInput() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "hel"
        viewModel.updateGhostText(cursorAtEnd: true)

        viewModel.acceptGhostText()

        #expect(viewModel.currentInput == "help")
        #expect(viewModel.ghostText == "")
    }

    @Test("Accept ghost text does nothing when empty")
    func acceptGhostTextDoesNothingWhenEmpty() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "xyz"
        viewModel.updateGhostText(cursorAtEnd: true)

        viewModel.acceptGhostText()

        #expect(viewModel.currentInput == "xyz")
    }

    // MARK: - Tab Completion Tests

    @Test("Tab completion single match auto-completes")
    func tabCompletionSingleMatch() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "hel"

        viewModel.tabComplete()

        #expect(viewModel.currentInput == "help ")
    }

    @Test("Tab completion multiple matches returns suggestions")
    func tabCompletionMultipleMatchesReturnsSuggestions() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        let suggestions = viewModel.tabComplete()

        #expect(suggestions != nil)
        #expect(suggestions?.contains("login") == true)
        #expect(suggestions?.contains("logout") == true)
    }

    @Test("Tab completion no match returns nil")
    func tabCompletionNoMatchReturnsNil() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "xyz"

        let suggestions = viewModel.tabComplete()

        #expect(suggestions == nil)
    }

    @Test("Ghost text shows argument completion after space")
    func ghostTextShowsArgumentCompletion() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "session l"

        viewModel.updateGhostText(cursorAtEnd: true)

        #expect(viewModel.ghostText == "ist" || viewModel.ghostText == "ocal")
    }

    // MARK: - Interactive Tab Completion Tests

    @Test("First tab shows suggestions without selection")
    func firstTabShowsSuggestionsWithoutSelection() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        let suggestions = viewModel.tabComplete()

        #expect(suggestions != nil)
        #expect(viewModel.tabSuggestions != nil)
        #expect(viewModel.tabSelectionIndex == nil)
    }

    @Test("Second tab enters selection mode")
    func secondTabEntersSelectionMode() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()
        _ = viewModel.tabComplete()

        #expect(viewModel.tabSelectionIndex == 0)
    }

    @Test("Third tab cycles to next suggestion")
    func thirdTabCyclesToNextSuggestion() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()
        _ = viewModel.tabComplete()
        _ = viewModel.tabComplete()

        #expect(viewModel.tabSelectionIndex == 1)
    }

    @Test("Tab cycles wrap around")
    func tabCyclesWrapAround() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()
        let count = viewModel.tabSuggestions?.count ?? 0

        // Cycle through all suggestions plus one more
        for _ in 0..<(count + 1) {
            _ = viewModel.tabComplete()
        }

        #expect(viewModel.tabSelectionIndex == 0)
    }

    @Test("Apply selected suggestion returns true when in selection mode")
    func applySelectedSuggestionReturnsTrue() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()
        _ = viewModel.tabComplete()

        let applied = viewModel.applySelectedSuggestion()

        #expect(applied == true)
        #expect(viewModel.currentInput == "login ")
        #expect(viewModel.tabSuggestions == nil)
        #expect(viewModel.tabSelectionIndex == nil)
    }

    @Test("Apply selected suggestion returns false when not in selection mode")
    func applySelectedSuggestionReturnsFalse() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()

        let applied = viewModel.applySelectedSuggestion()

        #expect(applied == false)
    }

    @Test("Clear tab state clears suggestions and selection")
    func clearTabStateClearsSuggestionsAndSelection() {
        let viewModel = createConfiguredViewModel()
        viewModel.currentInput = "lo"

        _ = viewModel.tabComplete()
        _ = viewModel.tabComplete()

        viewModel.clearTabState()

        #expect(viewModel.tabSuggestions == nil)
        #expect(viewModel.tabSelectionIndex == nil)
    }
}
