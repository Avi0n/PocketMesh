import Testing
import Foundation
import SwiftData
@testable import PocketMesh
@testable import PocketMeshServices

@Suite("Disconnected Pill Tests")
@MainActor
struct DisconnectedPillTests {

    // MARK: - shouldSuppressDisconnectedPill Integration Tests

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func makeTestManager() throws -> ConnectionManager {
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
        return ConnectionManager(modelContainer: container, defaults: defaults)
    }

    @Test("shouldSuppressDisconnectedPill returns true when user explicitly disconnected")
    func testShouldSuppressWhenUserDisconnected() throws {
        ConnectionIntent.userDisconnected.persist(to: defaults)

        let manager = try makeTestManager()
        #expect(manager.shouldSuppressDisconnectedPill == true)
    }

    @Test("shouldSuppressDisconnectedPill returns false when user did not explicitly disconnect")
    func testShouldNotSuppressWhenNoExplicitDisconnect() throws {
        let manager = try makeTestManager()
        #expect(manager.shouldSuppressDisconnectedPill == false)
    }

    // MARK: - updateDisconnectedPillState Tests (pass values directly)

    @Test("disconnected pill not shown when user explicitly disconnected")
    func testPillNotShownAfterExplicitDisconnect() async throws {
        let appState = AppState()

        appState.connectionUI.updateDisconnectedPillState(
            connectionState: .disconnected,
            lastConnectedDeviceID: UUID(),
            shouldSuppressDisconnectedPill: true
        )

        try await Task.sleep(for: .seconds(1.2))
        #expect(appState.connectionUI.disconnectedPillVisible == false)
    }

    @Test("disconnected pill shown after unexpected disconnect")
    func testPillShownAfterUnexpectedDisconnect() async throws {
        let appState = AppState()

        appState.connectionUI.updateDisconnectedPillState(
            connectionState: .disconnected,
            lastConnectedDeviceID: UUID(),
            shouldSuppressDisconnectedPill: false
        )

        try await Task.sleep(for: .seconds(1.2))
        #expect(appState.connectionUI.disconnectedPillVisible == true)
    }

    @Test("disconnected pill not shown when no last connected device")
    func testPillNotShownWhenNoLastDevice() async throws {
        let appState = AppState()

        appState.connectionUI.updateDisconnectedPillState(
            connectionState: .disconnected,
            lastConnectedDeviceID: nil,
            shouldSuppressDisconnectedPill: false
        )

        try await Task.sleep(for: .seconds(1.2))
        #expect(appState.connectionUI.disconnectedPillVisible == false)
    }

    @Test("disconnected pill hidden when connection starts")
    func testPillHiddenWhenConnecting() async throws {
        let appState = AppState()

        appState.connectionUI.updateDisconnectedPillState(
            connectionState: .disconnected,
            lastConnectedDeviceID: UUID(),
            shouldSuppressDisconnectedPill: false
        )
        try await Task.sleep(for: .seconds(1.2))
        #expect(appState.connectionUI.disconnectedPillVisible == true)

        appState.connectionUI.hideDisconnectedPill()
        #expect(appState.connectionUI.disconnectedPillVisible == false)
    }

    @Test("disconnected pill delay prevents flash during brief reconnects")
    func testPillDelayPreventsFlash() async throws {
        let appState = AppState()

        appState.connectionUI.updateDisconnectedPillState(
            connectionState: .disconnected,
            lastConnectedDeviceID: UUID(),
            shouldSuppressDisconnectedPill: false
        )

        #expect(appState.connectionUI.disconnectedPillVisible == false)

        try await Task.sleep(for: .seconds(0.5))
        appState.connectionUI.hideDisconnectedPill()

        try await Task.sleep(for: .seconds(1.0))
        #expect(appState.connectionUI.disconnectedPillVisible == false)
    }
}
