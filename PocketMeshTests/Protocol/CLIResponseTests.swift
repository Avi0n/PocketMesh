import Testing
@testable import PocketMeshServices

struct CLIResponseTests {

    // MARK: - Prompt Prefix Stripping

    @Test func parse_promptPrefix_stripsPrefix() {
        let result = CLIResponse.parse("> OK")
        #expect(result == .ok)
    }

    @Test func parse_noPromptPrefix_stillWorks() {
        let result = CLIResponse.parse("OK")
        #expect(result == .ok)
    }

    @Test func parse_promptPrefix_withWhitespace() {
        let result = CLIResponse.parse("  > OK  ")
        #expect(result == .ok)
    }

    @Test func parse_okWithMessage_clockSet() {
        let result = CLIResponse.parse("OK - clock set: 16:13 - 9/1/2026 UTC")
        #expect(result == .ok)
    }

    @Test func parse_okWithMessage_withPromptPrefix() {
        let result = CLIResponse.parse("> OK - clock set: 16:13 - 9/1/2026 UTC")
        #expect(result == .ok)
    }

    // MARK: - Radio with Prompt

    @Test func parse_radio_withPromptPrefix() {
        let result = CLIResponse.parse("> 910.5250244,62.5,7,8", forQuery: "get radio")
        if case let .radio(freq, bw, sf, cr) = result {
            #expect(abs(freq - 910.5250244) < 0.0001)
            #expect(abs(bw - 62.5) < 0.01)
            #expect(sf == 7)
            #expect(cr == 8)
        } else {
            Issue.record("Expected .radio, got \(result)")
        }
    }

    @Test func parse_radio_withoutPromptPrefix() {
        let result = CLIResponse.parse("915.000,250.0,10,5", forQuery: "get radio")
        if case let .radio(freq, bw, sf, cr) = result {
            #expect(abs(freq - 915.0) < 0.0001)
            #expect(abs(bw - 250.0) < 0.01)
            #expect(sf == 10)
            #expect(cr == 5)
        } else {
            Issue.record("Expected .radio, got \(result)")
        }
    }

    // MARK: - Name with Prompt

    @Test func parse_name_withPromptPrefix() {
        let result = CLIResponse.parse("> Sunnyslope Repeater", forQuery: "get name")
        #expect(result == .name("Sunnyslope Repeater"))
    }

    @Test func parse_name_withoutPromptPrefix() {
        let result = CLIResponse.parse("My Node", forQuery: "get name")
        #expect(result == .name("My Node"))
    }

    // MARK: - Repeat Mode with Prompt

    @Test func parse_repeatMode_on_withPromptPrefix() {
        let result = CLIResponse.parse("> on", forQuery: "get repeat")
        #expect(result == .repeatMode(true))
    }

    @Test func parse_repeatMode_off_withPromptPrefix() {
        let result = CLIResponse.parse("> off", forQuery: "get repeat")
        #expect(result == .repeatMode(false))
    }

    @Test func parse_repeatMode_withoutPromptPrefix() {
        let result = CLIResponse.parse("on", forQuery: "get repeat")
        #expect(result == .repeatMode(true))
    }

    // MARK: - TX Power with Prompt

    @Test func parse_txPower_withPromptPrefix() {
        let result = CLIResponse.parse("> 22", forQuery: "get tx")
        #expect(result == .txPower(22))
    }

    @Test func parse_txPower_withoutPromptPrefix() {
        let result = CLIResponse.parse("17", forQuery: "get tx")
        #expect(result == .txPower(17))
    }

    // MARK: - Coordinates with Prompt

    @Test func parse_latitude_withPromptPrefix() {
        let result = CLIResponse.parse("> 33.4484", forQuery: "get lat")
        if case let .latitude(lat) = result {
            #expect(abs(lat - 33.4484) < 0.0001)
        } else {
            Issue.record("Expected .latitude, got \(result)")
        }
    }

    @Test func parse_latitude_withoutPromptPrefix() {
        let result = CLIResponse.parse("40.7128", forQuery: "get lat")
        if case let .latitude(lat) = result {
            #expect(abs(lat - 40.7128) < 0.0001)
        } else {
            Issue.record("Expected .latitude, got \(result)")
        }
    }

    @Test func parse_longitude_withPromptPrefix() {
        let result = CLIResponse.parse("> -112.0740", forQuery: "get lon")
        if case let .longitude(lon) = result {
            #expect(abs(lon - (-112.0740)) < 0.0001)
        } else {
            Issue.record("Expected .longitude, got \(result)")
        }
    }

    @Test func parse_longitude_withoutPromptPrefix() {
        let result = CLIResponse.parse("-74.0060", forQuery: "get lon")
        if case let .longitude(lon) = result {
            #expect(abs(lon - (-74.0060)) < 0.0001)
        } else {
            Issue.record("Expected .longitude, got \(result)")
        }
    }

    // MARK: - Intervals with Prompt

    @Test func parse_advertInterval_withPromptPrefix() {
        let result = CLIResponse.parse("> 5", forQuery: "get advert.interval")
        #expect(result == .advertInterval(5))
    }

    @Test func parse_advertInterval_withoutPromptPrefix() {
        let result = CLIResponse.parse("10", forQuery: "get advert.interval")
        #expect(result == .advertInterval(10))
    }

    @Test func parse_floodAdvertInterval_withPromptPrefix() {
        let result = CLIResponse.parse("> 12", forQuery: "get flood.advert.interval")
        #expect(result == .floodAdvertInterval(12))
    }

    @Test func parse_floodAdvertInterval_withoutPromptPrefix() {
        let result = CLIResponse.parse("6", forQuery: "get flood.advert.interval")
        #expect(result == .floodAdvertInterval(6))
    }

    @Test func parse_floodMax_withPromptPrefix() {
        let result = CLIResponse.parse("> 3", forQuery: "get flood.max")
        #expect(result == .floodMax(3))
    }

    @Test func parse_floodMax_withoutPromptPrefix() {
        let result = CLIResponse.parse("4", forQuery: "get flood.max")
        #expect(result == .floodMax(4))
    }

    // MARK: - Error with Prompt

    @Test func parse_error_withPromptPrefix() {
        let result = CLIResponse.parse("> Error: permission denied")
        if case let .error(msg) = result {
            #expect(msg == "Error: permission denied")
        } else {
            Issue.record("Expected .error, got \(result)")
        }
    }

    @Test func parse_error_withoutPromptPrefix() {
        let result = CLIResponse.parse("Error: invalid value")
        if case let .error(msg) = result {
            #expect(msg == "Error: invalid value")
        } else {
            Issue.record("Expected .error, got \(result)")
        }
    }

    @Test func parse_unknownCommand_withPromptPrefix() {
        let result = CLIResponse.parse("> Error: unknown command")
        #expect(result == .unknownCommand("Error: unknown command"))
    }

    // MARK: - Version with Prompt

    @Test func parse_version_withPromptPrefix() {
        let result = CLIResponse.parse("> MeshCore v1.10.0 (2025-04-18)")
        #expect(result == .version("MeshCore v1.10.0 (2025-04-18)"))
    }

    @Test func parse_version_withoutPromptPrefix() {
        let result = CLIResponse.parse("MeshCore v1.11.0 (2025-05-01)")
        #expect(result == .version("MeshCore v1.11.0 (2025-05-01)"))
    }

    @Test func parse_version_shortFormat_withPromptPrefix() {
        let result = CLIResponse.parse("> v1.12.0 (2025-06-15)")
        #expect(result == .version("v1.12.0 (2025-06-15)"))
    }

    // MARK: - Device Time with Prompt

    @Test func parse_deviceTime_withPromptPrefix() {
        let result = CLIResponse.parse("> 06:40 - 18/4/2025 UTC")
        #expect(result == .deviceTime("06:40 - 18/4/2025 UTC"))
    }

    @Test func parse_deviceTime_withoutPromptPrefix() {
        let result = CLIResponse.parse("14:30 - 25/12/2025 UTC")
        #expect(result == .deviceTime("14:30 - 25/12/2025 UTC"))
    }

    // MARK: - Edge Cases

    @Test func parse_greaterThanInContent_notStripped() {
        // Content that starts with ">" but not "> " should not be stripped
        let result = CLIResponse.parse(">nosuchcommand", forQuery: "get name")
        #expect(result == .name(">nosuchcommand"))
    }

    @Test func parse_multipleGreaterThan_onlyFirstStripped() {
        // Only the first "> " should be stripped
        let result = CLIResponse.parse("> > nested prompt", forQuery: "get name")
        #expect(result == .name("> nested prompt"))
    }

    @Test func parse_emptyAfterStrip() {
        // When input is "> ", trimming whitespace first gives ">" (no space),
        // which doesn't match the "> " prefix, so result is raw ">"
        let result = CLIResponse.parse("> ")
        #expect(result == .raw(">"))
    }

    @Test func parse_justPrompt() {
        // Just the prompt character without space
        let result = CLIResponse.parse(">")
        #expect(result == .raw(">"))
    }

    // MARK: - Query Hint Matching (Integration)

    /// These tests verify that query hint matching correctly identifies response types
    /// even when responses have the prompt prefix. This tests the full flow that
    /// RepeaterSettingsViewModel.handleCLIResponse() uses.

    @Test func queryHintMatching_longitude_withPromptPrefix() {
        // Simulate the query hint matching logic from handleCLIResponse
        var trimmedText = "> -120.338211".trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip prompt - this is what we're fixing
        if trimmedText.hasPrefix("> ") {
            trimmedText = String(trimmedText.dropFirst(2))
        }

        // Now the query matching pattern should work
        let isValidDouble = Double(trimmedText) != nil && !trimmedText.contains(",")
        #expect(isValidDouble == true)

        // And parsing should succeed
        let result = CLIResponse.parse("> -120.338211", forQuery: "get lon")
        if case let .longitude(lon) = result {
            #expect(abs(lon - (-120.338211)) < 0.0001)
        } else {
            Issue.record("Expected .longitude, got \(result)")
        }
    }

    @Test func queryHintMatching_repeatMode_withPromptPrefix() {
        // Simulate the query hint matching logic from handleCLIResponse
        var trimmedText = "> on".trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip prompt - this is what we're fixing
        if trimmedText.hasPrefix("> ") {
            trimmedText = String(trimmedText.dropFirst(2))
        }

        // Now the query matching pattern should work
        let isValidRepeatMode = trimmedText.lowercased() == "on" || trimmedText.lowercased() == "off"
        #expect(isValidRepeatMode == true)

        // And parsing should succeed
        let result = CLIResponse.parse("> on", forQuery: "get repeat")
        #expect(result == .repeatMode(true))
    }
}
