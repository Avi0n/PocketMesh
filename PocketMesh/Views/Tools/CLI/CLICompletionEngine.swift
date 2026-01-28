import Foundation

@MainActor
@Observable
final class CLICompletionEngine {

    // MARK: - Command Definitions

    private static let builtInCommands = [
        "help", "clear", "session", "logout"
    ]

    private static let localOnlyCommands = [
        "login", "nodes"
    ]

    // Per MeshCore CLI Reference - commands available via remote session
    private static let repeaterCommands = [
        "ver", "board", "clock",
        "neighbors", "get", "set", "password",
        "log", "reboot", "advert", "setperm", "tempradio", "neighbor.remove",
        "region", "gps", "powersaving", "clear"
    ]

    private static let sessionSubcommands = ["list", "local"]

    private static let logSubcommands = ["start", "stop", "erase"]

    private static let clearSubcommands = ["stats"]

    // Per MeshCore CLI Reference - region subcommands
    private static let regionSubcommands = [
        "load", "get", "put", "remove", "allowf", "denyf", "home", "save"
    ]

    // Per MeshCore CLI Reference - gps subcommands
    private static let gpsSubcommands = ["on", "off", "sync", "setloc", "advert"]

    private static let gpsAdvertValues = ["none", "share", "prefs"]

    private static let powersavingValues = ["on", "off"]

    // Per MeshCore CLI Reference - all get/set parameters
    private static let getSetParams = [
        "name", "radio", "tx", "repeat", "lat", "lon",
        "af", "flood.max", "int.thresh", "agc.reset.interval",
        "multi.acks", "advert.interval", "flood.advert.interval",
        "guest.password", "allow.read.only",
        "rxdelay", "txdelay", "direct.txdelay",
        "bridge.enabled", "bridge.delay", "bridge.source",
        "bridge.baud", "bridge.secret", "bridge.type",
        "adc.multiplier", "public.key", "prv.key", "role", "freq"
    ]

    // MARK: - Node Names

    private(set) var nodeNames: [String] = []

    func updateNodeNames(_ names: [String]) {
        nodeNames = names
    }

    // MARK: - Completion Logic

    func completions(for input: String, isLocal: Bool) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Empty or just spaces - return all applicable commands
        if trimmed.isEmpty {
            return availableCommands(isLocal: isLocal).sorted()
        }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let command = parts[0].lowercased()

        // Single word - complete command name
        if parts.count == 1 && !input.hasSuffix(" ") {
            return availableCommands(isLocal: isLocal)
                .filter { $0.hasPrefix(command) }
                .sorted()
        }

        // Command with space - complete arguments
        let argPrefix = parts.count > 1 ? parts[1].lowercased() : ""
        return completeArguments(for: command, parts: parts, prefix: argPrefix)
    }

    private func completeArguments(for command: String, parts: [String], prefix: String) -> [String] {
        switch command {
        case "session":
            return completeSessionArgs(prefix: prefix)
        case "login":
            return completeLoginArgs(prefix: prefix)
        case "log":
            return Self.logSubcommands.filter { $0.hasPrefix(prefix) }.sorted()
        case "get", "set":
            return Self.getSetParams.filter { $0.hasPrefix(prefix) }.sorted()
        case "region":
            return Self.regionSubcommands.filter { $0.hasPrefix(prefix) }.sorted()
        case "gps":
            return completeGpsArgs(parts: parts, prefix: prefix)
        case "powersaving":
            return Self.powersavingValues.filter { $0.hasPrefix(prefix) }.sorted()
        case "clear":
            return Self.clearSubcommands.filter { $0.hasPrefix(prefix) }.sorted()
        default:
            return []
        }
    }

    private func availableCommands(isLocal: Bool) -> [String] {
        var commands = Self.builtInCommands

        if isLocal {
            commands.append(contentsOf: Self.localOnlyCommands)
        } else {
            commands.append(contentsOf: Self.repeaterCommands)
        }

        return commands
    }

    private func completeSessionArgs(prefix: String) -> [String] {
        var suggestions = Self.sessionSubcommands.filter { $0.hasPrefix(prefix) }
        suggestions.append(contentsOf: nodeNames.filter { $0.lowercased().hasPrefix(prefix) })
        return suggestions.sorted()
    }

    private func completeLoginArgs(prefix: String) -> [String] {
        return nodeNames.filter { $0.lowercased().hasPrefix(prefix) }.sorted()
    }

    private func completeGpsArgs(parts: [String], prefix: String) -> [String] {
        // gps advert {none|share|prefs} - third argument
        if parts.count >= 2 && parts[1].lowercased() == "advert" {
            let valuePrefix = parts.count > 2 ? parts[2].lowercased() : ""
            return Self.gpsAdvertValues.filter { $0.hasPrefix(valuePrefix) }.sorted()
        }
        // First argument after gps
        return Self.gpsSubcommands.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
