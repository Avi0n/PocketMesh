import Testing
@testable import PocketMesh

@Suite("CLICompletionEngine Tests")
@MainActor
struct CLICompletionEngineTests {

    // MARK: - Helper

    private func createEngine() -> CLICompletionEngine {
        CLICompletionEngine()
    }

    // MARK: - Command Completion Tests

    @Test("Empty input returns all commands")
    func emptyInputReturnsAllCommands() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "", isLocal: true)

        #expect(suggestions.contains("help"))
        #expect(suggestions.contains("clear"))
        #expect(suggestions.contains("login"))
        #expect(suggestions.contains("session"))
    }

    @Test("Partial command returns matching commands")
    func partialCommandReturnsMatchingCommands() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "hel", isLocal: true)

        #expect(suggestions == ["help"])
    }

    @Test("Session subcommands complete after 'session '")
    func sessionSubcommandsComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "session ", isLocal: true)

        #expect(suggestions.contains("list"))
        #expect(suggestions.contains("local"))
    }

    @Test("Repeater commands available in remote session")
    func repeaterCommandsInRemoteSession() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "v", isLocal: false)

        #expect(suggestions.contains("ver"))
    }

    @Test("Login not available in remote session")
    func loginNotAvailableInRemoteSession() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "log", isLocal: false)

        #expect(!suggestions.contains("login"))
        #expect(suggestions.contains("logout"))
        #expect(suggestions.contains("log"))
    }

    @Test("Region subcommands complete after 'region '")
    func regionSubcommandsComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "region ", isLocal: false)

        #expect(suggestions.contains("load"))
        #expect(suggestions.contains("get"))
        #expect(suggestions.contains("put"))
        #expect(suggestions.contains("save"))
    }

    @Test("GPS subcommands complete after 'gps '")
    func gpsSubcommandsComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "gps ", isLocal: false)

        #expect(suggestions.contains("on"))
        #expect(suggestions.contains("off"))
        #expect(suggestions.contains("sync"))
        #expect(suggestions.contains("advert"))
    }

    @Test("Get/set completes all parameters")
    func getSetCompletesParameters() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "get ", isLocal: false)

        #expect(suggestions.contains("name"))
        #expect(suggestions.contains("radio"))
        #expect(suggestions.contains("flood.max"))
        #expect(suggestions.contains("bridge.enabled"))
    }

    @Test("Clear subcommands complete")
    func clearSubcommandsComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "clear ", isLocal: false)

        #expect(suggestions.contains("stats"))
    }

    // MARK: - Log Subcommands Tests

    @Test("Log subcommands complete after 'log '")
    func logSubcommandsComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "log ", isLocal: false)

        #expect(suggestions.contains("start"))
        #expect(suggestions.contains("stop"))
        #expect(suggestions.contains("erase"))
    }

    @Test("Log subcommand filters by prefix")
    func logSubcommandFiltersPrefix() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "log st", isLocal: false)

        #expect(suggestions.contains("start"))
        #expect(suggestions.contains("stop"))
        #expect(!suggestions.contains("erase"))
    }

    // MARK: - Powersaving Tests

    @Test("Powersaving values complete after 'powersaving '")
    func powersavingValuesComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "powersaving ", isLocal: false)

        #expect(suggestions.contains("on"))
        #expect(suggestions.contains("off"))
    }

    @Test("Powersaving filters by prefix")
    func powersavingFiltersPrefix() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "powersaving o", isLocal: false)

        #expect(suggestions.contains("on"))
        #expect(suggestions.contains("off"))
    }

    // MARK: - GPS Advert Third Argument Tests

    @Test("GPS advert values complete for third argument")
    func gpsAdvertValuesComplete() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "gps advert ", isLocal: false)

        #expect(suggestions.contains("none"))
        #expect(suggestions.contains("share"))
        #expect(suggestions.contains("prefs"))
    }

    @Test("GPS advert filters third argument by prefix")
    func gpsAdvertFiltersPrefix() {
        let engine = createEngine()
        let suggestions = engine.completions(for: "gps advert s", isLocal: false)

        #expect(suggestions.contains("share"))
        #expect(!suggestions.contains("none"))
        #expect(!suggestions.contains("prefs"))
    }

    // MARK: - Node Names Tests

    @Test("updateNodeNames stores node names")
    func updateNodeNamesStoresNames() {
        let engine = createEngine()

        #expect(engine.nodeNames.isEmpty)

        engine.updateNodeNames(["Alpha", "Bravo", "Charlie"])

        #expect(engine.nodeNames == ["Alpha", "Bravo", "Charlie"])
    }

    @Test("updateNodeNames replaces previous names")
    func updateNodeNamesReplacesPrevious() {
        let engine = createEngine()
        engine.updateNodeNames(["Alpha", "Bravo"])
        engine.updateNodeNames(["Delta", "Echo"])

        #expect(engine.nodeNames == ["Delta", "Echo"])
    }

    // MARK: - Login with Node Names Tests

    @Test("Login completes with node names")
    func loginCompletesWithNodeNames() {
        let engine = createEngine()
        engine.updateNodeNames(["Alpha", "Bravo", "Charlie"])

        let suggestions = engine.completions(for: "login ", isLocal: true)

        #expect(suggestions.contains("Alpha"))
        #expect(suggestions.contains("Bravo"))
        #expect(suggestions.contains("Charlie"))
    }

    @Test("Login filters node names by prefix")
    func loginFiltersNodeNamesByPrefix() {
        let engine = createEngine()
        engine.updateNodeNames(["Alpha", "Bravo", "Charlie"])

        let suggestions = engine.completions(for: "login a", isLocal: true)

        #expect(suggestions.contains("Alpha"))
        #expect(!suggestions.contains("Bravo"))
        #expect(!suggestions.contains("Charlie"))
    }

    @Test("Session includes node names in suggestions")
    func sessionIncludesNodeNames() {
        let engine = createEngine()
        engine.updateNodeNames(["TestNode"])

        let suggestions = engine.completions(for: "session ", isLocal: true)

        #expect(suggestions.contains("list"))
        #expect(suggestions.contains("local"))
        #expect(suggestions.contains("TestNode"))
    }

    @Test("Node name completion is case-insensitive")
    func nodeNameCompletionCaseInsensitive() {
        let engine = createEngine()
        engine.updateNodeNames(["MyRepeater"])

        let suggestions = engine.completions(for: "login my", isLocal: true)

        #expect(suggestions.contains("MyRepeater"))
    }

    @Test("Empty node names returns empty for login")
    func emptyNodeNamesReturnsEmptyForLogin() {
        let engine = createEngine()
        // No updateNodeNames called

        let suggestions = engine.completions(for: "login ", isLocal: true)

        #expect(suggestions.isEmpty)
    }
}
