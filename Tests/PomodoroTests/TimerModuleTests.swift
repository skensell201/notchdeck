import Testing
@testable import Pomodoro

/// The module itself is a thin shell around `PomodoroMachine`, which is where the
/// behaviour is tested. These cover only what the shell adds: its identity and the
/// rule that decides whether the collapsed notch shows a countdown.
@MainActor
@Suite("Timer module")
struct TimerModuleTests {
    @Test("the module identifies itself as the timer")
    func moduleID() {
        #expect(TimerModule.id.rawValue == "timer")
    }

    @Test("an untouched timer has nothing for the collapsed notch")
    func idleHasNoLiveContent() {
        let module = TimerModule()

        #expect(!module.hasLiveContent)
        #expect(module.peekView() == nil)
    }

    @Test("a running timer shows its countdown in the collapsed notch")
    func runningHasLiveContent() {
        let module = TimerModule()

        module.toggle()

        #expect(module.machine.isRunning)
        #expect(module.hasLiveContent)
        #expect(module.countdownText == "25:00")

        // Stops the tick this test started, so nothing outlives it.
        module.reset()
        #expect(!module.hasLiveContent)
    }

    @Test("a paused timer keeps showing the time it is holding")
    func pausedKeepsLiveContent() {
        let module = TimerModule()

        module.toggle()
        module.toggle()

        #expect(module.machine.isPaused)
        #expect(module.hasLiveContent)
        module.reset()
    }
}
