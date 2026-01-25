import Testing
import Foundation
import SwiftData
@testable import PocketMesh
@testable import PocketMeshServices

@Suite("Disconnected Pill Tests")
@MainActor
struct DisconnectedPillTests {

    private let userDisconnectedKey = "com.pocketmesh.userExplicitlyDisconnected"
    private let lastDeviceIDKey = "com.pocketmesh.lastConnectedDeviceID"

    // Clean up UserDefaults after each test
    private func cleanupUserDefaults() {
        UserDefaults.standard.removeObject(forKey: userDisconnectedKey)
        UserDefaults.standard.removeObject(forKey: lastDeviceIDKey)
    }

    private func makeAppState() throws -> AppState {
        let schema = Schema([
            Device.self,
            Contact.self,
            Message.self,
            Channel.self,
            RemoteNodeSession.self,
            RoomMessage.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return AppState(modelContainer: container)
    }

    // MARK: - shouldSuppressDisconnectedPill Tests

    @Test("shouldSuppressDisconnectedPill returns true when user explicitly disconnected")
    func testShouldSuppressWhenUserDisconnected() throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        UserDefaults.standard.set(true, forKey: userDisconnectedKey)

        let appState = try makeAppState()
        #expect(appState.connectionManager.shouldSuppressDisconnectedPill == true)
    }

    @Test("shouldSuppressDisconnectedPill returns false when user did not explicitly disconnect")
    func testShouldNotSuppressWhenNoExplicitDisconnect() throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        let appState = try makeAppState()
        #expect(appState.connectionManager.shouldSuppressDisconnectedPill == false)
    }

    // MARK: - updateDisconnectedPillState Tests

    @Test("disconnected pill not shown when user explicitly disconnected")
    func testPillNotShownAfterExplicitDisconnect() async throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        // Given: last device exists + user explicitly disconnected
        UserDefaults.standard.set(UUID().uuidString, forKey: lastDeviceIDKey)
        UserDefaults.standard.set(true, forKey: userDisconnectedKey)

        let appState = try makeAppState()

        // When: update disconnected pill state (simulates app launch check)
        appState.updateDisconnectedPillState()

        // Wait for potential delay
        try await Task.sleep(for: .seconds(1.2))

        // Then: pill should not be visible
        #expect(appState.disconnectedPillVisible == false)
    }

    @Test("disconnected pill shown after unexpected disconnect")
    func testPillShownAfterUnexpectedDisconnect() async throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        // Given: last device exists + NOT explicitly disconnected
        UserDefaults.standard.set(UUID().uuidString, forKey: lastDeviceIDKey)
        // userDisconnectedKey is not set (defaults to false)

        let appState = try makeAppState()

        // When: update disconnected pill state (simulates app launch after termination)
        appState.updateDisconnectedPillState()

        // Wait for the 1-second delay plus margin
        try await Task.sleep(for: .seconds(1.2))

        // Then: pill should be visible
        #expect(appState.disconnectedPillVisible == true)
    }

    @Test("disconnected pill not shown when no last connected device")
    func testPillNotShownWhenNoLastDevice() async throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        // Given: no last device ID exists
        // lastDeviceIDKey is not set

        let appState = try makeAppState()

        // When: update disconnected pill state
        appState.updateDisconnectedPillState()

        // Wait for potential delay
        try await Task.sleep(for: .seconds(1.2))

        // Then: pill should not be visible
        #expect(appState.disconnectedPillVisible == false)
    }

    @Test("disconnected pill hidden when connection starts")
    func testPillHiddenWhenConnecting() async throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        // Given: last device exists + NOT explicitly disconnected
        UserDefaults.standard.set(UUID().uuidString, forKey: lastDeviceIDKey)

        let appState = try makeAppState()

        // Start showing the pill
        appState.updateDisconnectedPillState()
        try await Task.sleep(for: .seconds(1.2))
        #expect(appState.disconnectedPillVisible == true)

        // When: hide the pill (simulates connection starting)
        appState.hideDisconnectedPill()

        // Then: pill should be hidden immediately
        #expect(appState.disconnectedPillVisible == false)
    }

    @Test("disconnected pill delay prevents flash during brief reconnects")
    func testPillDelayPreventsFlash() async throws {
        cleanupUserDefaults()
        defer { cleanupUserDefaults() }

        // Given: conditions that would show the pill
        UserDefaults.standard.set(UUID().uuidString, forKey: lastDeviceIDKey)

        let appState = try makeAppState()

        // When: update state and immediately hide (simulates quick reconnect)
        appState.updateDisconnectedPillState()

        // Pill should NOT be visible immediately (1s delay)
        #expect(appState.disconnectedPillVisible == false)

        // Hide before delay completes (simulates connection established)
        try await Task.sleep(for: .seconds(0.5))
        appState.hideDisconnectedPill()

        // Wait past the original delay
        try await Task.sleep(for: .seconds(1.0))

        // Then: pill should still be hidden (was cancelled)
        #expect(appState.disconnectedPillVisible == false)
    }
}
