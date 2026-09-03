import LiveActivities

/// A machine that says whatever the test tells it to.
///
/// A class rather than a struct because a source holds it by protocol and the
/// test drives it afterwards — and because the counts of `start` and `stop` are
/// half of what these tests are checking.
@MainActor
final class FakeObserver<Reading: Sendable & Equatable>: MachineObserving {
    /// What the next `read` returns. Nil stands for a machine with nothing to
    /// report: no battery, no volume control.
    var reading: Reading?
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var reads = 0

    private var onChange: (@MainActor @Sendable () -> Void)?

    init(reading: Reading? = nil) {
        self.reading = reading
    }

    func read() -> Reading? {
        reads += 1
        return reading
    }

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        starts += 1
        self.onChange = onChange
    }

    func stop() {
        stops += 1
        onChange = nil
    }

    /// Pretend the machine changed, the way the real notification would.
    func change(to reading: Reading) {
        self.reading = reading
        onChange?()
    }

    /// Pretend the system fired a notification with nothing behind it, which is
    /// most of what CoreAudio and IOKit actually do.
    func notifyWithoutChanging() {
        onChange?()
    }
}
