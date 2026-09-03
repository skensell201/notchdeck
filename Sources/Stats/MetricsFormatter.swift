import Foundation

/// Display strings for derived metrics.
///
/// Hand-rolled rather than `ByteCountFormatter`/`MeasurementFormatter`: the
/// panel needs a fixed, narrow, predictable width per figure — three significant
/// digits at most, always the same shape — and the system formatters localise
/// the unit, vary the digit count, and are far harder to pin down in a test than
/// they are to replace.
public enum MetricsFormatter {
    /// Shown wherever a figure is genuinely unknown. An em dash, not a zero.
    public static let unavailable = "—"

    /// Binary units, so "GB" here means 2^30 bytes. Chosen to match the page and
    /// buffer sizes every number in this module actually comes from.
    private static let units = ["B", "KB", "MB", "GB", "TB"]
    private static let step: Double = 1024

    /// e.g. `1.5 MB/s`. Nil is the first sample of a session, or an interval the
    /// deriver refused.
    public static func byteRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else {
            return unavailable
        }
        return scaled(bytesPerSecond, suffix: "/s")
    }

    /// e.g. `9.4 GB`.
    public static func bytes(_ bytes: UInt64) -> String {
        scaled(Double(bytes), suffix: "")
    }

    /// e.g. `47%`. Takes a fraction, because every fraction in `DerivedMetrics`
    /// is 0...1 and they must all round the same way.
    public static func percentage(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return unavailable }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// e.g. `1h 30m`, `45m`. Nil when the system has no estimate, which the
    /// caller must render as something other than a duration.
    public static func batteryTime(_ seconds: Int?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    /// One decimal below ten, none above, so the string never grows past four
    /// characters and the row does not shuffle sideways as values change.
    private static func scaled(_ value: Double, suffix: String) -> String {
        var value = max(value, 0)
        var unit = 0
        while value >= step, unit < units.count - 1 {
            value /= step
            unit += 1
        }
        // Bytes are whole things; a fractional byte per second reads as noise.
        var decimals = unit > 0 && value < 10 ? 1 : 0
        // Rounding can push a value back up over the unit boundary — 1023.7 KB
        // would print as "1024 KB". Carry it, once, which is all that is possible.
        let scale = pow(10.0, Double(decimals))
        if unit < units.count - 1, (value * scale).rounded() / scale >= step {
            value /= step
            unit += 1
            decimals = value < 10 ? 1 : 0
        }
        return "\(String(format: "%.\(decimals)f", value)) \(units[unit])\(suffix)"
    }
}
