/// What the panel draws: every figure already in display units, and `nil`
/// wherever the machine has not yet said enough for an honest answer.
public struct DerivedMetrics: Sendable, Equatable {
    public var battery: BatteryStatus?
    /// Fraction of the interval spent busy, 0...1. Nil until two samples exist,
    /// and nil again whenever the tick counters reset under us.
    public var cpuUsage: Double?
    public var memory: MemoryUsage
    /// Nil until two samples exist and the interval between them is usable.
    public var throughput: Throughput?

    public init(
        battery: BatteryStatus?,
        cpuUsage: Double?,
        memory: MemoryUsage,
        throughput: Throughput?
    ) {
        self.battery = battery
        self.cpuUsage = cpuUsage
        self.memory = memory
        self.throughput = throughput
    }
}

public struct BatteryStatus: Sendable, Equatable {
    /// 0...1, so it formats through the same percentage rule as everything else.
    public var charge: Double
    public var isCharging: Bool
    /// Nil means "the system does not know", not "no time left".
    public var secondsRemaining: Int?

    public init(charge: Double, isCharging: Bool, secondsRemaining: Int?) {
        self.charge = charge
        self.isCharging = isCharging
        self.secondsRemaining = secondsRemaining
    }
}

public struct MemoryUsage: Sendable, Equatable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    /// 0...1, the share of memory the kernel cannot hand back on demand.
    public var pressure: Double

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: Double) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }
}

public struct Throughput: Sendable, Equatable {
    public var bytesInPerSecond: Double
    public var bytesOutPerSecond: Double

    public init(bytesInPerSecond: Double, bytesOutPerSecond: Double) {
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
    }
}
