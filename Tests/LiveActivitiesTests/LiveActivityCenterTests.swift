import NotchCore
import Testing
@testable import LiveActivities

@Suite("Live activity centre")
@MainActor
struct LiveActivityCenterTests {
    /// A source that announces on demand and remembers how it was handled.
    private final class ScriptedSource: LiveActivitySource {
        private(set) var starts = 0
        private(set) var stops = 0
        private var emit: ((PeekPayload) -> Void)?

        func start(emit: @escaping (PeekPayload) -> Void) {
            starts += 1
            self.emit = emit
        }

        func stop() {
            stops += 1
            emit = nil
        }

        func announce(_ payload: PeekPayload) {
            emit?(payload)
        }
    }

    private func payload(_ id: String) -> PeekPayload {
        PeekPayload(id: id, title: id)
    }

    @Test("starting starts every source")
    func startsEverySource() {
        let sources = [ScriptedSource(), ScriptedSource()]
        let center = LiveActivityCenter(sources: sources)

        center.start()

        #expect(sources.map(\.starts) == [1, 1])
    }

    @Test("what any source announces reaches the sink unchanged")
    func forwardsToTheSink() {
        let first = ScriptedSource()
        let second = ScriptedSource()
        let center = LiveActivityCenter(sources: [first, second])
        var announced: [PeekPayload] = []
        center.onActivity = { announced.append($0) }
        center.start()

        first.announce(payload("volume"))
        second.announce(payload("power"))

        // No filtering, no reordering, no coalescing: replacement by id already
        // happens in the reducer, and doing it twice would only hide bugs.
        #expect(announced.map(\.id) == ["volume", "power"])
    }

    @Test("starting twice starts each source once")
    func startIsIdempotent() {
        let source = ScriptedSource()
        let center = LiveActivityCenter(sources: [source])

        center.start()
        center.start()

        #expect(source.starts == 1)
    }

    @Test("stopping stops every source, and nothing more arrives")
    func stopsEverySource() {
        let source = ScriptedSource()
        let center = LiveActivityCenter(sources: [source])
        var announced: [PeekPayload] = []
        center.onActivity = { announced.append($0) }
        center.start()

        center.stop()
        source.announce(payload("volume"))

        #expect(source.stops == 1)
        #expect(announced.isEmpty)
    }

    @Test("stopping without starting does nothing")
    func stopWithoutStart() {
        let source = ScriptedSource()
        let center = LiveActivityCenter(sources: [source])

        center.stop()

        #expect(source.stops == 0)
    }

    @Test("a stopped centre can be started again")
    func restart() {
        let source = ScriptedSource()
        let center = LiveActivityCenter(sources: [source])
        var announced: [PeekPayload] = []
        center.onActivity = { announced.append($0) }

        center.start()
        center.stop()
        center.start()
        source.announce(payload("power"))

        #expect(source.starts == 2)
        #expect(announced.count == 1)
    }

    @Test("a centre with no sink swallows announcements rather than trapping")
    func noSink() {
        let source = ScriptedSource()
        let center = LiveActivityCenter(sources: [source])
        center.start()

        source.announce(payload("volume"))
    }

    @Test("the two real sources are the two the app wires up")
    func systemSources() {
        // Constructing them must not need hardware to exist, only to be there.
        let sources = LiveActivityCenter.systemSources()

        #expect(sources.count == 2)
        #expect(sources.contains { $0 is PowerActivitySource })
        #expect(sources.contains { $0 is AudioDeviceSource })
    }
}
