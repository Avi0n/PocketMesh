// PocketMeshServices/Tests/PocketMeshServicesTests/Services/HeardRepeatsServiceTests.swift
import Testing
import Foundation
@testable import PocketMeshServices

@Suite("HeardRepeatsService Tests")
struct HeardRepeatsServiceTests {

    // MARK: - ChannelMessageFormat.parse Tests

    @Test("parse with valid format returns sender and message")
    func parseValidFormatReturnsSenderAndMessage() {
        let result = ChannelMessageFormat.parse("NodeName: Hello world")

        #expect(result != nil)
        #expect(result?.senderName == "NodeName")
        #expect(result?.messageText == "Hello world")
    }

    @Test("parse with no colon returns nil")
    func parseNoColonReturnsNil() {
        let result = ChannelMessageFormat.parse("No colon here")

        #expect(result == nil)
    }

    @Test("parse with colon at start returns nil")
    func parseColonAtStartReturnsNil() {
        let result = ChannelMessageFormat.parse(": Message without sender")

        #expect(result == nil)
    }

    @Test("parse with empty message returns empty text")
    func parseEmptyMessageReturnsEmptyText() {
        let result = ChannelMessageFormat.parse("Sender:")

        #expect(result != nil)
        #expect(result?.senderName == "Sender")
        #expect(result?.messageText == "")
    }

    @Test("parse with message containing colons only splits on first")
    func parseMessageWithColonsOnlySplitsOnFirst() {
        let result = ChannelMessageFormat.parse("Sender: Time is 10:30:00")

        #expect(result != nil)
        #expect(result?.senderName == "Sender")
        #expect(result?.messageText == "Time is 10:30:00")
    }

    @Test("parse trims whitespace from message")
    func parseTrimsWhitespaceFromMessage() {
        let result = ChannelMessageFormat.parse("Node:   Padded message   ")

        #expect(result != nil)
        #expect(result?.messageText == "Padded message")
    }

    @Test("parse preserves spaces in sender name")
    func parseSenderWithSpacesPreservesSpaces() {
        let result = ChannelMessageFormat.parse("Node With Spaces: Message")

        #expect(result != nil)
        #expect(result?.senderName == "Node With Spaces")
    }
}
