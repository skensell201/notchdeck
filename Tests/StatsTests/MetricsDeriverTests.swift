import Testing
@testable import Stats

@Suite("Metrics derivation")
struct MetricsDeriverTests {
    // MARK: Fixtures

    /// 16 GiB of 16 KiB pages, which is what an Apple silicon Mac reports.
    private static let pageSize: UInt64 = 16384
    private static let totalBytes: UInt64 = 16 * 1024 * 1024 * 1024

    private func sample(
        uptime: Double = 1000,
        battery: BatteryReading? = nil,
        cpu: CPUTicks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
        memory: MemoryReading? = nil,
        network: NetworkCounters = NetworkCounters(bytesIn: 0, bytesOut: 0)
    ) -> MetricsSample {
        MetricsSample(
            uptime: uptime,
            battery: battery,
            cpu: cpu,
            memory: memory ?? self.memory(),
            network: network
        )
    }

    private func memory(
        internalPages: UInt64 = 0,
        purgeablePages: UInt64 = 0,
        wiredPages: UInt64 = 0,
        compressedPages: UInt64 = 0
    ) -> MemoryReading {
        MemoryReading(
            pageSize: Self.pageSize,
            internalPages: internalPages,
            purgeablePages: purgeablePages,
            wiredPages: wiredPages,
            compressedPages: compressedPages,
            totalBytes: Self.totalBytes
        )
    }

    // MARK: The first sample

    @Test("the first sample after activation reports no CPU load and no throughput")
    func firstSampleHasNoRates() {
        let first = sample(
            cpu: CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            network: NetworkCounters(bytesIn: 9_000, bytesOut: 4_000)
        )

        let derived = MetricsDeriver.derive(previous: nil, current: first)

        // Not zero: a rate with one sample behind it is not a small rate, it is
        // no rate at all.
        #expect(derived.cpuUsage == nil)
        #expect(derived.throughput == nil)
    }

    @Test("the first sample still reports memory, which is a level and not a rate")
    func firstSampleStillHasMemory() {
        let first = sample(memory: memory(internalPages: 100, wiredPages: 100))

        let derived = MetricsDeriver.derive(previous: nil, current: first)

        #expect(derived.memory.usedBytes == 200 * Self.pageSize)
        #expect(derived.memory.totalBytes == Self.totalBytes)
    }

    // MARK: CPU

    @Test("CPU load is busy ticks over total ticks across the interval")
    func cpuLoadFromTickDeltas() {
        let previous = sample(cpu: CPUTicks(user: 1_000, system: 500, idle: 8_500, nice: 0))
        // 150 busy of 600 total.
        let current = sample(cpu: CPUTicks(user: 1_100, system: 550, idle: 8_950, nice: 0))

        let derived = MetricsDeriver.derive(previous: previous, current: current)

        #expect(derived.cpuUsage == 0.25)
    }

    @Test("nice time counts as busy")
    func niceCountsAsBusy() {
        let previous = sample(cpu: CPUTicks(user: 0, system: 0, idle: 0, nice: 0))
        let current = sample(cpu: CPUTicks(user: 0, system: 0, idle: 300, nice: 100))

        #expect(MetricsDeriver.derive(previous: previous, current: current).cpuUsage == 0.25)
    }

    @Test("an interval with no ticks in it reports unknown rather than dividing by zero")
    func cpuWithNoTicksIsUnknown() {
        let ticks = CPUTicks(user: 1_000, system: 500, idle: 8_500, nice: 0)

        let derived = MetricsDeriver.derive(previous: sample(cpu: ticks), current: sample(cpu: ticks))

        #expect(derived.cpuUsage == nil)
    }

    @Test("tick counters that reset report unknown rather than a wrapped delta")
    func cpuCounterResetIsUnknown() {
        // 32-bit tick counters wrap, and a fresh boot restarts them; either way
        // the arithmetic would produce an enormous busy delta.
        let previous = sample(cpu: CPUTicks(user: 4_000_000_000, system: 0, idle: 0, nice: 0))
        let current = sample(cpu: CPUTicks(user: 12, system: 0, idle: 400, nice: 0))

        #expect(MetricsDeriver.derive(previous: previous, current: current).cpuUsage == nil)
    }

    @Test("a fully busy interval reports 100% and never more")
    func cpuSaturates() {
        let previous = sample(cpu: CPUTicks(user: 0, system: 0, idle: 0, nice: 0))
        let current = sample(cpu: CPUTicks(user: 500, system: 500, idle: 0, nice: 0))

        #expect(MetricsDeriver.derive(previous: previous, current: current).cpuUsage == 1)
    }

    // MARK: Network

    @Test("throughput is the byte delta spread over the elapsed time")
    func throughputFromByteDeltas() {
        let previous = sample(uptime: 100, network: NetworkCounters(bytesIn: 1_000, bytesOut: 500))
        let current = sample(uptime: 102, network: NetworkCounters(bytesIn: 5_000, bytesOut: 700))

        let throughput = MetricsDeriver.derive(previous: previous, current: current).throughput

        #expect(throughput == Throughput(bytesInPerSecond: 2_000, bytesOutPerSecond: 100))
    }

    @Test("a zero-length interval reports unknown rather than dividing by zero")
    func zeroElapsedIsUnknown() {
        let previous = sample(uptime: 100, network: NetworkCounters(bytesIn: 1_000, bytesOut: 0))
        let current = sample(uptime: 100, network: NetworkCounters(bytesIn: 5_000, bytesOut: 0))

        #expect(MetricsDeriver.derive(previous: previous, current: current).throughput == nil)
    }

    @Test("a clock that goes backwards reports unknown rather than a negative rate")
    func backwardsClockIsUnknown() {
        let previous = sample(uptime: 200, network: NetworkCounters(bytesIn: 1_000, bytesOut: 0))
        let current = sample(uptime: 100, network: NetworkCounters(bytesIn: 5_000, bytesOut: 0))

        #expect(MetricsDeriver.derive(previous: previous, current: current).throughput == nil)
    }

    @Test("byte counters that wrap report unknown rather than a negative rate")
    func wrappedByteCounterIsUnknown() {
        // `if_data` counts in 32 bits, so this happens after every 4 GiB.
        let previous = sample(uptime: 100, network: NetworkCounters(bytesIn: 4_294_967_000, bytesOut: 0))
        let current = sample(uptime: 102, network: NetworkCounters(bytesIn: 1_200, bytesOut: 0))

        #expect(MetricsDeriver.derive(previous: previous, current: current).throughput == nil)
    }

    @Test("an interface disappearing between samples reports unknown, not a negative rate")
    func shrinkingInterfaceSumIsUnknown() {
        // The sum drops when Wi-Fi is turned off or a dock is unplugged: the
        // outbound counter falls even though nothing was un-sent.
        let previous = sample(uptime: 100, network: NetworkCounters(bytesIn: 1_000, bytesOut: 9_000))
        let current = sample(uptime: 102, network: NetworkCounters(bytesIn: 2_000, bytesOut: 3_000))

        #expect(MetricsDeriver.derive(previous: previous, current: current).throughput == nil)
    }

    @Test("a gap far longer than the sampling interval reports unknown")
    func longGapIsUnknown() {
        // A sleep, a wake, or a blocked main actor. The bytes did accumulate, but
        // spreading them evenly over the gap would describe an interval nobody
        // was watching.
        let previous = sample(uptime: 100, network: NetworkCounters(bytesIn: 0, bytesOut: 0))
        let current = sample(
            uptime: 100 + MetricsDeriver.maximumInterval + 1,
            network: NetworkCounters(bytesIn: 900_000_000, bytesOut: 0)
        )

        #expect(MetricsDeriver.derive(previous: previous, current: current).throughput == nil)
    }

    @Test("an idle interval reports a rate of zero, which is not the same as unknown")
    func idleIsZeroNotUnknown() {
        let counters = NetworkCounters(bytesIn: 1_000, bytesOut: 500)
        let previous = sample(uptime: 100, network: counters)
        let current = sample(uptime: 102, network: counters)

        #expect(
            MetricsDeriver.derive(previous: previous, current: current).throughput
                == Throughput(bytesInPerSecond: 0, bytesOutPerSecond: 0)
        )
    }

    // MARK: Memory

    @Test("used memory is app memory plus wired plus compressed")
    func usedMemory() {
        let reading = memory(
            internalPages: 1_000,
            purgeablePages: 200,
            wiredPages: 300,
            compressedPages: 100
        )

        let usage = MetricsDeriver.derive(previous: nil, current: sample(memory: reading)).memory

        // (1000 - 200) + 300 + 100 pages.
        #expect(usage.usedBytes == 1_200 * Self.pageSize)
    }

    @Test("more purgeable pages than internal ones clamps to zero instead of underflowing")
    func purgeableUnderflowIsClamped() {
        // The two counts are read a moment apart, so the kernel can report a
        // subset larger than its superset.
        let reading = memory(internalPages: 10, purgeablePages: 40, wiredPages: 5)

        let usage = MetricsDeriver.derive(previous: nil, current: sample(memory: reading)).memory

        #expect(usage.usedBytes == 5 * Self.pageSize)
    }

    @Test("pressure is the share of memory the kernel cannot reclaim on demand")
    func pressureFromWiredAndCompressed() {
        let totalPages = Self.totalBytes / Self.pageSize
        let reading = memory(
            internalPages: totalPages / 2,
            wiredPages: totalPages / 8,
            compressedPages: totalPages / 8
        )

        let usage = MetricsDeriver.derive(previous: nil, current: sample(memory: reading)).memory

        #expect(usage.pressure == 0.25)
    }

    @Test("used memory never exceeds the memory installed")
    func usedIsCappedAtInstalled() {
        let totalPages = Self.totalBytes / Self.pageSize
        let reading = memory(internalPages: totalPages, wiredPages: totalPages)

        let usage = MetricsDeriver.derive(previous: nil, current: sample(memory: reading)).memory

        #expect(usage.usedBytes == Self.totalBytes)
        #expect(usage.pressure == 1)
    }

    // MARK: Battery

    @Test("IOKit's 0-100 scale becomes the same 0-1 fraction everything else uses")
    func batteryChargeIsAFraction() {
        let reading = BatteryReading(percentage: 87, isCharging: false, secondsRemaining: 5_400)

        let status = MetricsDeriver.derive(previous: nil, current: sample(battery: reading)).battery

        #expect(status?.charge == 0.87)
        #expect(status?.secondsRemaining == 5_400)
        #expect(status?.isCharging == false)
    }

    @Test("a missing time estimate stays missing rather than becoming zero")
    func missingBatteryEstimateStaysMissing() {
        // The usual state while charging, and for the first minutes after a wake.
        let reading = BatteryReading(percentage: 42, isCharging: true, secondsRemaining: nil)

        let status = MetricsDeriver.derive(previous: nil, current: sample(battery: reading)).battery

        #expect(status?.secondsRemaining == nil)
        #expect(status?.isCharging == true)
    }

    @Test("a machine with no battery reports no battery")
    func noBattery() {
        let derived = MetricsDeriver.derive(previous: nil, current: sample(battery: nil))

        #expect(derived.battery == nil)
    }

    @Test("a charge outside 0-100 is clamped rather than shown as 104%")
    func batteryChargeIsClamped() {
        let over = BatteryReading(percentage: 104, isCharging: true, secondsRemaining: nil)
        let under = BatteryReading(percentage: -1, isCharging: false, secondsRemaining: nil)

        #expect(MetricsDeriver.derive(previous: nil, current: sample(battery: over)).battery?.charge == 1)
        #expect(MetricsDeriver.derive(previous: nil, current: sample(battery: under)).battery?.charge == 0)
    }
}
