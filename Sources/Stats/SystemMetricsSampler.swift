import Darwin
import Foundation
import IOKit.ps
import Support

/// Reads the machine. Four independent system calls, no arithmetic beyond
/// widening — everything that could be wrong about the numbers is in
/// `MetricsDeriver`, where it can be tested.
public struct SystemMetricsSampler: MetricsSampling {
    /// Taken once. `mach_host_self()` hands out a send right on every call, so
    /// calling it every two seconds would leak a port right every two seconds.
    private let host: mach_port_t

    public init() {
        host = mach_host_self()
    }

    public func sample() -> MetricsSample {
        MetricsSample(
            // Monotonic: this is `mach_absolute_time` underneath, so it cannot be
            // dragged backwards by a clock correction the way wall time can.
            uptime: ProcessInfo.processInfo.systemUptime,
            battery: Self.battery(),
            cpu: cpuTicks(),
            memory: memoryReading(),
            network: Self.networkCounters()
        )
    }

    // MARK: Battery

    private static func battery() -> BatteryReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            // Both are reported in whole minutes, and both are -1 while the system
            // has no estimate — which is most of the time on mains power, and for
            // the first minutes after a wake.
            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = description[key] as? Int
            let seconds = minutes.flatMap { $0 >= 0 ? $0 * 60 : nil }

            return BatteryReading(
                percentage: Double(current) / Double(maximum) * 100,
                isCharging: isCharging,
                secondsRemaining: seconds
            )
        }
        // A Mac with no internal battery. Not an error.
        return nil
    }

    // MARK: CPU

    /// `HOST_CPU_LOAD_INFO` is a `host_statistics` flavour, not a
    /// `host_statistics64` one — the 64-bit call only knows the VM flavours — so
    /// the ticks arrive as 32-bit `natural_t` and are widened here.
    private func cpuTicks() -> CPUTicks {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logger.error("host_statistics(HOST_CPU_LOAD_INFO) failed: \(result, privacy: .public)")
            return CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    // MARK: Memory

    private func memoryReading() -> MemoryReading {
        // Asked of the kernel rather than read from `vm_kernel_page_size`, which
        // is a mutable global and so off limits under strict concurrency.
        var machPageSize: vm_size_t = 0
        let pageSize = host_page_size(host, &machPageSize) == KERN_SUCCESS
            ? UInt64(machPageSize)
            : 4096
        let total = ProcessInfo.processInfo.physicalMemory

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logger.error("host_statistics64(HOST_VM_INFO64) failed: \(result, privacy: .public)")
            return MemoryReading(
                pageSize: pageSize,
                internalPages: 0,
                purgeablePages: 0,
                wiredPages: 0,
                compressedPages: 0,
                totalBytes: total
            )
        }
        return MemoryReading(
            pageSize: pageSize,
            internalPages: UInt64(info.internal_page_count),
            purgeablePages: UInt64(info.purgeable_count),
            wiredPages: UInt64(info.wire_count),
            compressedPages: UInt64(info.compressor_page_count),
            totalBytes: total
        )
    }

    // MARK: Network

    private static func networkCounters() -> NetworkCounters {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else {
            logger.error("getifaddrs failed: \(errno, privacy: .public)")
            return NetworkCounters(bytesIn: 0, bytesOut: 0)
        }
        defer { freeifaddrs(list) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            // Loopback traffic never leaves the machine, and an interface that is
            // down or not running carries counters frozen at whatever they were.
            guard flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else {
                continue
            }
            // Each interface appears once per address family; only the link-layer
            // entry carries `if_data`, so this is also what stops double counting.
            guard interface.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }

            bytesIn &+= UInt64(data.pointee.ifi_ibytes)
            bytesOut &+= UInt64(data.pointee.ifi_obytes)
        }
        return NetworkCounters(bytesIn: bytesIn, bytesOut: bytesOut)
    }
}

private let logger = Log.make("stats")
