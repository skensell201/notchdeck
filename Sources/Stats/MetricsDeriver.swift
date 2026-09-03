/// Turns two consecutive raw samples into displayable figures.
///
/// Pure, and the only place in the module where a wrong number could plausibly
/// be invented, which is why every rule here has a test. The recurring theme is
/// that "unknown" is a legitimate answer: a rate needs two samples and a
/// positive interval, and counters that go backwards say nothing about the
/// interval they appear to span.
public enum MetricsDeriver {
    /// Longer than this between samples and the byte delta no longer describes a
    /// current rate — it describes whatever happened across a sleep, a wake, or a
    /// main actor that was blocked for a while. Spreading it evenly would produce
    /// a plausible-looking figure that is simply untrue.
    static let maximumInterval: Double = 60

    public static func derive(previous: MetricsSample?, current: MetricsSample) -> DerivedMetrics {
        DerivedMetrics(
            battery: battery(current.battery),
            cpuUsage: cpuUsage(previous: previous?.cpu, current: current.cpu),
            memory: memory(current.memory),
            throughput: throughput(previous: previous, current: current)
        )
    }

    // MARK: Battery

    private static func battery(_ reading: BatteryReading?) -> BatteryStatus? {
        guard let reading else { return nil }
        return BatteryStatus(
            charge: min(max(reading.percentage / 100, 0), 1),
            isCharging: reading.isCharging,
            // Passed through untouched, nil included: a missing estimate is a
            // state the panel shows differently, not a zero to round off.
            secondsRemaining: reading.secondsRemaining.map { max($0, 0) }
        )
    }

    // MARK: CPU

    /// Busy ticks over total ticks across the interval.
    ///
    /// Needs no elapsed time at all — the tick counters carry their own clock —
    /// so the only ways this can fail are having no predecessor, having counters
    /// that wrapped or reset, and an interval short enough that no tick landed
    /// in it.
    private static func cpuUsage(previous: CPUTicks?, current: CPUTicks) -> Double? {
        guard let previous, current.isSuccessor(of: previous) else { return nil }
        let total = current.total &- previous.total
        guard total > 0 else { return nil }
        let busy = current.busy &- previous.busy
        return min(max(Double(busy) / Double(total), 0), 1)
    }

    // MARK: Memory

    /// A single sample is enough: page counts are levels, not counters.
    private static func memory(_ reading: MemoryReading) -> MemoryUsage {
        let app = reading.internalPages.subtractingReportingOverflow(reading.purgeablePages)
        // Purgeable pages are a subset of internal ones, so the kernel should
        // never report more of them — but the two counts are read at slightly
        // different moments, so clamp rather than trap.
        let appPages = app.overflow ? 0 : app.partialValue
        let usedPages = appPages &+ reading.wiredPages &+ reading.compressedPages
        let unreclaimable = reading.wiredPages &+ reading.compressedPages

        let totalPages = reading.pageSize > 0 ? reading.totalBytes / reading.pageSize : 0
        let pressure = totalPages > 0
            ? min(max(Double(unreclaimable) / Double(totalPages), 0), 1)
            : 0

        return MemoryUsage(
            usedBytes: min(usedPages &* reading.pageSize, reading.totalBytes),
            totalBytes: reading.totalBytes,
            pressure: pressure
        )
    }

    // MARK: Network

    private static func throughput(previous: MetricsSample?, current: MetricsSample) -> Throughput? {
        guard let previous else { return nil }
        let elapsed = current.uptime - previous.uptime
        guard elapsed > 0, elapsed <= maximumInterval else { return nil }
        // A 32-bit `if_data` counter wraps every 4 GiB, and the sum changes shape
        // whenever an interface comes or goes. Either shows up as a decrease, and
        // one interval of "unknown" is far better than one interval of nonsense.
        guard current.network.isSuccessor(of: previous.network) else { return nil }

        return Throughput(
            bytesInPerSecond: Double(current.network.bytesIn - previous.network.bytesIn) / elapsed,
            bytesOutPerSecond: Double(current.network.bytesOut - previous.network.bytesOut) / elapsed
        )
    }
}
