import Testing
@testable import Media

@Suite("Adapter restart backoff")
struct AdapterBackoffTests {
    @Test("the first restart is immediate so a one-off crash is invisible")
    func firstRestartIsImmediate() {
        #expect(AdapterBackoff.delay(forAttempt: 0) == .zero)
    }

    @Test("the delay grows with consecutive failures")
    func delayGrows() {
        let first = AdapterBackoff.delay(forAttempt: 1)
        let second = AdapterBackoff.delay(forAttempt: 2)
        let third = AdapterBackoff.delay(forAttempt: 3)

        #expect(first < second)
        #expect(second < third)
    }

    @Test("the delay is capped so the module always recovers eventually")
    func delayIsCapped() {
        #expect(AdapterBackoff.delay(forAttempt: 50) == AdapterBackoff.maximumDelay)
        #expect(AdapterBackoff.delay(forAttempt: 5000) == AdapterBackoff.maximumDelay)
    }

    @Test("a negative attempt count is treated as the first attempt")
    func negativeAttemptIsSafe() {
        #expect(AdapterBackoff.delay(forAttempt: -3) == .zero)
    }
}
