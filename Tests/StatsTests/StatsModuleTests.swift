import Testing
@testable import Stats

@Suite("Stats module")
struct StatsModuleTests {
    /// Hands out a scripted series of samples and counts how often it was asked.
    /// A class, not a struct, because the module holds it by protocol and the
    /// test needs to see the calls it made.
    private final class ScriptedSampler: MetricsSampling, @unchecked Sendable {
        private let samples: [MetricsSample]
        private(set) var calls = 0

        init(_ samples: [MetricsSample]) {
            self.samples = samples
        }

        func sample() -> MetricsSample {
            defer { calls += 1 }
            return samples[min(calls, samples.count - 1)]
        }
    }

    private static func sample(uptime: Double, bytesIn: UInt64) -> MetricsSample {
        MetricsSample(
            uptime: uptime,
            battery: BatteryReading(percentage: 50, isCharging: false, secondsRemaining: 3_600),
            cpu: CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            memory: MemoryReading(
                pageSize: 16384,
                internalPages: 100,
                purgeablePages: 0,
                wiredPages: 100,
                compressedPages: 0,
                totalBytes: 16 * 1024 * 1024 * 1024
            ),
            network: NetworkCounters(bytesIn: bytesIn, bytesOut: 0)
        )
    }

    @Test("the module identifies itself as stats")
    @MainActor
    func moduleID() {
        #expect(StatsModule.id.rawValue == "stats")
    }

    @Test("stats never widen the collapsed notch")
    @MainActor
    func noPeek() {
        let module = StatsModule(sampler: ScriptedSampler([Self.sample(uptime: 0, bytesIn: 0)]))

        #expect(module.hasLiveContent == false)
        #expect(module.peekView() == nil)
    }

    @Test("nothing is sampled until the module is activated")
    @MainActor
    func idleUntilActivated() {
        let sampler = ScriptedSampler([Self.sample(uptime: 0, bytesIn: 0)])

        let module = StatsModule(sampler: sampler)

        #expect(sampler.calls == 0)
        #expect(module.metrics == nil)
    }

    @Test("activation samples immediately, so the panel is never blank")
    @MainActor
    func activationSamplesAtOnce() {
        let sampler = ScriptedSampler([Self.sample(uptime: 100, bytesIn: 1_000)])
        let module = StatsModule(sampler: sampler)

        module.activate()
        defer { module.deactivate() }

        #expect(sampler.calls == 1)
        // Levels are there straight away; rates need the second sample.
        #expect(module.metrics?.battery?.charge == 0.5)
        #expect(module.metrics?.throughput == nil)
    }

    @Test("deactivation stops sampling")
    @MainActor
    func deactivationStopsSampling() async throws {
        let sampler = ScriptedSampler([Self.sample(uptime: 100, bytesIn: 1_000)])
        let module = StatsModule(sampler: sampler, interval: .milliseconds(1))

        module.activate()
        module.deactivate()
        let afterStopping = sampler.calls
        try await Task.sleep(for: .milliseconds(30))

        #expect(sampler.calls == afterStopping)
    }

    @Test("reactivating starts a fresh session rather than differencing across the gap")
    @MainActor
    func reactivationForgetsTheOldSample() {
        // The sample before deactivation and the one after can be minutes apart
        // with a large byte delta between them; reporting that as a rate would
        // invent a burst of traffic that never happened.
        let sampler = ScriptedSampler([
            Self.sample(uptime: 100, bytesIn: 1_000),
            Self.sample(uptime: 400, bytesIn: 900_000_000)
        ])
        let module = StatsModule(sampler: sampler)

        module.activate()
        module.deactivate()
        module.activate()
        defer { module.deactivate() }

        #expect(module.metrics?.throughput == nil)
    }
}
