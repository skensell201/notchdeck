import Testing
@testable import Timer

@Suite("Pomodoro machine")
struct PomodoroMachineTests {
    /// Every test measures from one arbitrary instant. `ContinuousClock` arithmetic
    /// is exact, so nothing here depends on where that instant actually is.
    private let t0 = ContinuousClock.now

    private let minute: Duration = .seconds(60)

    /// Short, distinct durations so a wrong phase's length is obvious in a failure.
    private func makeMachine(phasesPerCycle: Int = 4) -> PomodoroMachine {
        PomodoroMachine(
            configuration: PomodoroConfiguration(
                work: .seconds(25),
                shortBreak: .seconds(5),
                longBreak: .seconds(15),
                workPhasesPerCycle: phasesPerCycle
            )
        )
    }

    // MARK: Starting state

    @Test("a new machine is idle at the start of the first work phase")
    func newMachineIsIdle() {
        let machine = makeMachine()

        #expect(machine.phase == .work)
        #expect(machine.isIdle)
        #expect(machine.completedWorkPhases == 0)
    }

    @Test("an idle machine has the whole phase left, however long it sits there")
    func idleRemainingIsWholePhase() {
        let machine = makeMachine()

        #expect(machine.remaining(at: t0) == .seconds(25))
        #expect(machine.remaining(at: t0 + .seconds(600)) == .seconds(25))
        #expect(machine.progress(at: t0 + .seconds(600)) == 0)
    }

    // MARK: Start, pause, resume

    @Test("starting counts the phase down in real time")
    func startCountsDown() {
        var machine = makeMachine()

        machine.start(at: t0)

        #expect(machine.isRunning)
        #expect(machine.remaining(at: t0) == .seconds(25))
        #expect(machine.remaining(at: t0 + .seconds(10)) == .seconds(15))
    }

    @Test("remaining clamps at zero rather than going negative")
    func remainingClampsAtZero() {
        var machine = makeMachine()

        machine.start(at: t0)

        #expect(machine.remaining(at: t0 + .seconds(25)) == .zero)
        #expect(machine.remaining(at: t0 + .seconds(90)) == .zero)
        #expect(machine.progress(at: t0 + .seconds(90)) == 1)
    }

    @Test("starting an already running phase does not restart it")
    func startIsIgnoredWhileRunning() {
        var machine = makeMachine()
        machine.start(at: t0)

        machine.start(at: t0 + .seconds(10))

        #expect(machine.remaining(at: t0 + .seconds(10)) == .seconds(15))
    }

    @Test("pausing holds what is left of the phase")
    func pauseHoldsRemaining() {
        var machine = makeMachine()
        machine.start(at: t0)

        machine.pause(at: t0 + .seconds(10))

        #expect(machine.isPaused)
        #expect(machine.remaining(at: t0 + .seconds(10)) == .seconds(15))
    }

    @Test("paused time is not spent, however long the pause lasts")
    func pauseDoesNotConsumeThePhase() {
        var machine = makeMachine(phasesPerCycle: 4)
        machine.start(at: t0)
        machine.pause(at: t0 + .seconds(5))

        // Five minutes go by with the timer held.
        #expect(machine.remaining(at: t0 + minute * 5) == .seconds(20))
        machine.resume(at: t0 + minute * 5)

        #expect(machine.isRunning)
        #expect(machine.remaining(at: t0 + minute * 5) == .seconds(20))
        #expect(machine.remaining(at: t0 + minute * 5 + .seconds(8)) == .seconds(12))
    }

    @Test("pausing and resuming an idle machine changes nothing")
    func pauseAndResumeIgnoreIdle() {
        var machine = makeMachine()

        machine.pause(at: t0)
        machine.resume(at: t0)

        #expect(machine.isIdle)
        #expect(machine.remaining(at: t0) == .seconds(25))
    }

    @Test("resuming a running machine does not extend its deadline")
    func resumeIsIgnoredWhileRunning() {
        var machine = makeMachine()
        machine.start(at: t0)

        machine.resume(at: t0 + .seconds(10))

        #expect(machine.remaining(at: t0 + .seconds(10)) == .seconds(15))
    }

    // MARK: Phase progression

    @Test("nothing advances while the phase still has time left")
    func noAdvanceBeforeTheDeadline() {
        var machine = makeMachine()
        machine.start(at: t0)

        #expect(machine.advanceIfElapsed(at: t0 + .seconds(24)) == nil)
        #expect(machine.phase == .work)
    }

    @Test("a paused phase never elapses on its own")
    func pausedPhaseNeverElapses() {
        var machine = makeMachine()
        machine.start(at: t0)
        machine.pause(at: t0 + .seconds(1))

        #expect(machine.advanceIfElapsed(at: t0 + minute) == nil)
        #expect(machine.phase == .work)
    }

    @Test("a completed work phase runs straight into a short break")
    func workCompletesIntoShortBreak() {
        var machine = makeMachine()
        machine.start(at: t0)

        let ended = machine.advanceIfElapsed(at: t0 + .seconds(25))

        #expect(ended == .work)
        #expect(machine.phase == .shortBreak)
        #expect(machine.isRunning)
        #expect(machine.completedWorkPhases == 1)
        #expect(machine.remaining(at: t0 + .seconds(25)) == .seconds(5))
    }

    @Test("a completed short break runs straight into the next work phase")
    func shortBreakCompletesIntoWork() {
        var machine = makeMachine()
        machine.start(at: t0)
        machine.advanceIfElapsed(at: t0 + .seconds(25))

        let ended = machine.advanceIfElapsed(at: t0 + .seconds(30))

        #expect(ended == .shortBreak)
        #expect(machine.phase == .work)
        #expect(machine.completedWorkPhases == 1)
    }

    @Test("the fourth work phase earns the long break")
    func fourWorkPhasesEarnALongBreak() {
        var machine = makeMachine(phasesPerCycle: 4)
        machine.start(at: t0)
        var now = t0

        for expected in 1...3 {
            now += .seconds(25)
            #expect(machine.advanceIfElapsed(at: now) == .work)
            #expect(machine.phase == .shortBreak)
            #expect(machine.completedWorkPhases == expected)
            now += .seconds(5)
            #expect(machine.advanceIfElapsed(at: now) == .shortBreak)
            #expect(machine.phase == .work)
        }

        now += .seconds(25)
        #expect(machine.advanceIfElapsed(at: now) == .work)
        #expect(machine.phase == .longBreak)
        #expect(machine.completedWorkPhases == 4)
        #expect(machine.remaining(at: now) == .seconds(15))
    }

    @Test("a two-phase cycle reaches the long break after two work phases")
    func cycleLengthIsConfigurable() {
        var machine = makeMachine(phasesPerCycle: 2)
        machine.start(at: t0)
        machine.advanceIfElapsed(at: t0 + .seconds(25))
        #expect(machine.phase == .shortBreak)
        machine.advanceIfElapsed(at: t0 + .seconds(30))
        machine.advanceIfElapsed(at: t0 + .seconds(55))

        #expect(machine.phase == .longBreak)
        #expect(machine.completedWorkPhases == 2)
    }

    @Test("the long break closes the cycle and the count starts over")
    func longBreakRestartsTheCycle() {
        var machine = makeMachine(phasesPerCycle: 1)
        machine.start(at: t0)
        machine.advanceIfElapsed(at: t0 + .seconds(25))
        #expect(machine.phase == .longBreak)

        let ended = machine.advanceIfElapsed(at: t0 + .seconds(40))

        #expect(ended == .longBreak)
        #expect(machine.phase == .work)
        #expect(machine.completedWorkPhases == 0)
    }

    @Test("a phase missed by a long gap still gets its full length")
    func advancingAfterALongGapDoesNotCascade() {
        var machine = makeMachine()
        machine.start(at: t0)

        // The lid was shut for an hour; one phase ends, and the next is measured
        // from now rather than from the deadline that passed.
        #expect(machine.advanceIfElapsed(at: t0 + minute * 60) == .work)
        #expect(machine.phase == .shortBreak)
        #expect(machine.remaining(at: t0 + minute * 60) == .seconds(5))
    }

    // MARK: Skip

    @Test("skipping work counts it towards the long break and keeps running")
    func skipFromWork() {
        var machine = makeMachine()
        machine.start(at: t0)

        machine.skip(at: t0 + .seconds(3))

        #expect(machine.phase == .shortBreak)
        #expect(machine.completedWorkPhases == 1)
        #expect(machine.isRunning)
        #expect(machine.remaining(at: t0 + .seconds(3)) == .seconds(5))
    }

    @Test("skipping a short break returns to work")
    func skipFromShortBreak() {
        var machine = makeMachine()
        machine.start(at: t0)
        machine.skip(at: t0)

        machine.skip(at: t0 + .seconds(1))

        #expect(machine.phase == .work)
        #expect(machine.completedWorkPhases == 1)
        #expect(machine.remaining(at: t0 + .seconds(1)) == .seconds(25))
    }

    @Test("skipping the long break starts a fresh cycle")
    func skipFromLongBreak() {
        var machine = makeMachine(phasesPerCycle: 1)
        machine.start(at: t0)
        machine.skip(at: t0)
        #expect(machine.phase == .longBreak)

        machine.skip(at: t0 + .seconds(1))

        #expect(machine.phase == .work)
        #expect(machine.completedWorkPhases == 0)
    }

    @Test("skipping an idle phase leaves the next one idle too")
    func skipFromIdleStaysIdle() {
        var machine = makeMachine()

        machine.skip(at: t0)

        #expect(machine.phase == .shortBreak)
        #expect(machine.isIdle)
        #expect(machine.remaining(at: t0 + minute) == .seconds(5))
    }

    @Test("skipping a paused phase does not start the timer again")
    func skipFromPausedStaysPaused() {
        var machine = makeMachine()
        machine.start(at: t0)
        machine.pause(at: t0 + .seconds(5))

        machine.skip(at: t0 + .seconds(5))

        #expect(machine.phase == .shortBreak)
        #expect(machine.isIdle)
    }

    // MARK: Reset

    @Test("resetting a running phase stops it at the start of the cycle")
    func resetFromRunning() {
        var machine = makeMachine()
        machine.start(at: t0)

        machine.reset()

        #expect(machine.phase == .work)
        #expect(machine.isIdle)
        #expect(machine.remaining(at: t0 + minute) == .seconds(25))
    }

    @Test("resetting a paused phase drops the time it was holding")
    func resetFromPaused() {
        var machine = makeMachine()
        machine.start(at: t0)
        machine.pause(at: t0 + .seconds(20))

        machine.reset()

        #expect(machine.isIdle)
        #expect(machine.remaining(at: t0) == .seconds(25))
    }

    @Test("resetting an idle machine is a no-op")
    func resetFromIdle() {
        var machine = makeMachine()
        let before = machine

        machine.reset()

        #expect(machine == before)
    }

    @Test("resetting mid-cycle clears the earned work phases")
    func resetFromLongBreakClearsTheCycle() {
        var machine = makeMachine(phasesPerCycle: 1)
        machine.start(at: t0)
        machine.skip(at: t0)
        #expect(machine.phase == .longBreak)

        machine.reset()

        #expect(machine.phase == .work)
        #expect(machine.completedWorkPhases == 0)
        #expect(machine.isIdle)
    }

    // MARK: Derived values

    @Test("progress runs from nothing to all of the phase")
    func progressSpansThePhase() {
        var machine = makeMachine()
        machine.start(at: t0)

        #expect(machine.progress(at: t0) == 0)
        #expect(abs(machine.progress(at: t0 + .seconds(5)) - 0.2) < 0.000_001)
        #expect(machine.progress(at: t0 + .seconds(25)) == 1)
    }

    @Test("the work phase number counts the cycle for the label")
    func workPhaseNumberCountsTheCycle() {
        var machine = makeMachine(phasesPerCycle: 4)
        #expect(machine.workPhaseNumber == 1)

        machine.start(at: t0)
        machine.skip(at: t0)
        #expect(machine.workPhaseNumber == 1)  // the break belongs to the first phase
        machine.skip(at: t0)

        #expect(machine.phase == .work)
        #expect(machine.workPhaseNumber == 2)
    }

    @Test("a zero-length cycle is treated as one work phase, not none")
    func cycleLengthIsAtLeastOne() {
        let configuration = PomodoroConfiguration(workPhasesPerCycle: 0)

        #expect(configuration.workPhasesPerCycle == 1)
    }

    @Test("the default configuration is 25 / 5 / 15 minutes, four to a cycle")
    func defaultConfiguration() {
        let configuration = PomodoroConfiguration()

        #expect(configuration.duration(of: .work) == .seconds(25 * 60))
        #expect(configuration.duration(of: .shortBreak) == .seconds(5 * 60))
        #expect(configuration.duration(of: .longBreak) == .seconds(15 * 60))
        #expect(configuration.workPhasesPerCycle == 4)
    }
}

@Suite("Pomodoro clock text")
struct PomodoroClockTests {
    @Test("a whole phase reads as minutes and no seconds")
    func wholeMinutes() {
        #expect(PomodoroClock.text(.seconds(25 * 60)) == "25:00")
        #expect(PomodoroClock.text(.seconds(5 * 60)) == "05:00")
    }

    @Test("seconds are padded")
    func paddedSeconds() {
        #expect(PomodoroClock.text(.seconds(61)) == "01:01")
        #expect(PomodoroClock.text(.seconds(9)) == "00:09")
    }

    @Test("a fraction of a second rounds up, so the last second is still shown")
    func fractionsRoundUp() {
        #expect(PomodoroClock.text(.milliseconds(1)) == "00:01")
        #expect(PomodoroClock.text(.milliseconds(59_500)) == "01:00")
    }

    @Test("zero and anything past it read as zero")
    func zeroAndBelow() {
        #expect(PomodoroClock.text(.zero) == "00:00")
        #expect(PomodoroClock.text(.seconds(-30)) == "00:00")
    }
}
