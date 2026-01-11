// NotificationServiceTests.swift
import Testing
@testable import PocketMeshServices

@Suite("NotificationService Tests")
struct NotificationServiceTests {

    @Test("Suppression flag defaults to false")
    @MainActor
    func suppressionFlagDefaultsToFalse() async {
        let service = NotificationService()
        #expect(service.isSuppressingNotifications == false)
    }

    @Test("Suppression flag can be set and cleared")
    @MainActor
    func suppressionFlagCanBeSetAndCleared() async {
        let service = NotificationService()

        service.isSuppressingNotifications = true
        #expect(service.isSuppressingNotifications == true)

        service.isSuppressingNotifications = false
        #expect(service.isSuppressingNotifications == false)
    }

    @Test("Suppression flag can be toggled multiple times")
    @MainActor
    func suppressionFlagCanBeToggledMultipleTimes() async {
        let service = NotificationService()

        // Toggle several times
        service.isSuppressingNotifications = true
        service.isSuppressingNotifications = false
        service.isSuppressingNotifications = true
        service.isSuppressingNotifications = true  // Setting same value
        service.isSuppressingNotifications = false

        #expect(service.isSuppressingNotifications == false)
    }
}
