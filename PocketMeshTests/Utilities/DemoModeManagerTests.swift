import Testing
import Foundation
@testable import PocketMesh

@Suite("DemoModeManager Tests")
@MainActor
struct DemoModeManagerTests {

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    // MARK: - Singleton Pattern Tests

    @Test("shared returns the same instance", .serialized)
    func testSingletonPattern() {
        let instance1 = DemoModeManager.shared
        let instance2 = DemoModeManager.shared
        #expect(instance1 === instance2)
    }

    // MARK: - Default Values Tests

    @Test("properties default to false for new instances")
    func testDefaultValues() {
        let manager = DemoModeManager(defaults: defaults)
        #expect(manager.isUnlocked == false)
        #expect(manager.isEnabled == false)
    }

    // MARK: - unlock() Method Tests

    @Test("unlock sets both isUnlocked and isEnabled to true")
    func testUnlockSetsBothFlags() {
        let manager = DemoModeManager(defaults: defaults)

        #expect(manager.isUnlocked == false)
        #expect(manager.isEnabled == false)

        manager.unlock()

        #expect(manager.isUnlocked == true)
        #expect(manager.isEnabled == true)
    }

    // MARK: - UserDefaults Persistence Tests

    @Test("UserDefaults persistence works for isUnlocked")
    func testUserDefaultsPersistenceForIsUnlocked() {
        let manager = DemoModeManager(defaults: defaults)

        manager.isUnlocked = true

        let persistedValue = defaults.bool(forKey: "isDemoModeUnlocked")
        #expect(persistedValue == true)
    }

    @Test("UserDefaults persistence works for isEnabled")
    func testUserDefaultsPersistenceForIsEnabled() {
        let manager = DemoModeManager(defaults: defaults)

        manager.isEnabled = true

        let persistedValue = defaults.bool(forKey: "isDemoModeEnabled")
        #expect(persistedValue == true)
    }

    @Test("unlock persists both values to UserDefaults")
    func testUnlockPersistsToUserDefaults() {
        let manager = DemoModeManager(defaults: defaults)

        manager.unlock()

        let unlockedValue = defaults.bool(forKey: "isDemoModeUnlocked")
        let enabledValue = defaults.bool(forKey: "isDemoModeEnabled")

        #expect(unlockedValue == true)
        #expect(enabledValue == true)
    }

    @Test("values persist and can be read back")
    func testPersistenceReadBack() {
        defaults.set(true, forKey: "isDemoModeUnlocked")
        defaults.set(true, forKey: "isDemoModeEnabled")

        let manager = DemoModeManager(defaults: defaults)
        #expect(manager.isUnlocked == true)
        #expect(manager.isEnabled == true)
    }
}
