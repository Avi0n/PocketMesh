import Testing
@testable import PocketMesh

@Suite("AppState Lifecycle Transition Tests")
@MainActor
struct LifecycleTransitionTests {

    @Test("BLE foreground waits for queued background transition")
    func foregroundWaitsForBackgroundTransition() async {
        let appState = AppState()
        let recorder = TransitionRecorder()

        appState.setBLELifecycleOverridesForTesting(
            enterBackground: {
                await recorder.record("background-start")
                try? await Task.sleep(for: .milliseconds(150))
                await recorder.record("background-end")
            },
            becomeActive: {
                await recorder.record("foreground-start")
                await recorder.record("foreground-end")
            }
        )

        appState.handleEnterBackground()
        await appState.handleReturnToForeground()

        let events = await recorder.events
        #expect(events == [
            "background-start",
            "background-end",
            "foreground-start",
            "foreground-end"
        ])
    }

    @Test("rapid background-active bounces keep BLE transitions ordered")
    func rapidBouncesKeepTransitionsOrdered() async {
        let appState = AppState()
        let recorder = TransitionRecorder()

        appState.setBLELifecycleOverridesForTesting(
            enterBackground: {
                try? await Task.sleep(for: .milliseconds(20))
                await recorder.record("background")
            },
            becomeActive: {
                await recorder.record("foreground")
            }
        )

        for _ in 0..<5 {
            appState.handleEnterBackground()
            await appState.handleReturnToForeground()
        }

        let events = await recorder.events
        #expect(events.count == 10)

        for index in stride(from: 0, to: events.count, by: 2) {
            #expect(events[index] == "background")
            #expect(events[index + 1] == "foreground")
        }
    }
}

private actor TransitionRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}
