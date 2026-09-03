/// One reading of the machine, in the units the kernel reports.
///
/// Deliberately raw and cumulative. Ticks, page counts and byte counters are
/// what IOKit, `host_statistics` and `getifaddrs` hand back, and every figure
/// the user actually sees is a difference between two of these. Converting here
/// would bury the interesting cases — the first sample of a session, a counter
/// that resets, an interval of zero length — inside the one layer that cannot be
/// unit-tested. `MetricsDeriver` does the converting instead.
public struct MetricsSample: Sendable, Equatable {
    /// Seconds on a monotonic clock. Only differences between samples mean
    /// anything, so the epoch is irrelevant — but it must never run backwards.
    public var uptime: Double
    /// Nil on a machine with no battery, which is a Mac mini rather than an error.
    public var battery: BatteryReading?
    public var cpu: CPUTicks
    public var memory: MemoryReading
    public var network: NetworkCounters

    public init(
        uptime: Double,
        battery: BatteryReading?,
        cpu: CPUTicks,
        memory: MemoryReading,
        network: NetworkCounters
    ) {
        self.uptime = uptime
        self.battery = battery
        self.cpu = cpu
        self.memory = memory
        self.network = network
    }
}

/// The power source as IOKit describes it.
public struct BatteryReading: Sendable, Equatable {
    /// 0...100, IOKit's own scale.
    public var percentage: Double
    public var isCharging: Bool
    /// Nil while the estimate is unavailable — the first minutes after a wake, and
    /// most of the time while charging. That is a state of its own, not zero.
    public var secondsRemaining: Int?

    public init(percentage: Double, isCharging: Bool, secondsRemaining: Int?) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.secondsRemaining = secondsRemaining
    }
}

/// Cumulative scheduler ticks since boot, widened to 64 bits from the kernel's
/// 32-bit counters. They still wrap, just far less often; the deriver treats any
/// decrease as a reset.
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Ticks spent on work. `nice` is user time at a lowered priority, so it
    /// counts as busy.
    public var busy: UInt64 { user &+ system &+ nice }
    public var total: UInt64 { busy &+ idle }

    /// True when no counter has gone backwards, i.e. the pair is a usable delta.
    func isSuccessor(of previous: CPUTicks) -> Bool {
        user >= previous.user
            && system >= previous.system
            && idle >= previous.idle
            && nice >= previous.nice
    }
}

/// Virtual memory page counts, plus the two constants needed to turn them into
/// bytes. `totalBytes` comes from the hardware rather than from summing pages:
/// the page counts do not add up to physical memory and never have.
public struct MemoryReading: Sendable, Equatable {
    public var pageSize: UInt64
    /// Pages backed by nothing but themselves — anonymous memory. Activity
    /// Monitor's "App Memory" is this minus `purgeable`.
    public var internalPages: UInt64
    /// Pages the kernel may discard without writing anywhere, so they are not
    /// really used.
    public var purgeablePages: UInt64
    public var wiredPages: UInt64
    public var compressedPages: UInt64
    public var totalBytes: UInt64

    public init(
        pageSize: UInt64,
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        totalBytes: UInt64
    ) {
        self.pageSize = pageSize
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
        self.totalBytes = totalBytes
    }
}

/// Bytes in and out since boot, summed over every active non-loopback interface.
public struct NetworkCounters: Sendable, Equatable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }

    func isSuccessor(of previous: NetworkCounters) -> Bool {
        bytesIn >= previous.bytesIn && bytesOut >= previous.bytesOut
    }
}

/// The seam between the module and the machine.
///
/// Sampling is synchronous because every call behind it is a syscall that
/// returns in microseconds; making it async would buy nothing and would let the
/// two halves of a delta drift apart across a suspension point.
public protocol MetricsSampling: Sendable {
    func sample() -> MetricsSample
}
