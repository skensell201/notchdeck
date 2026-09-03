import Testing
@testable import Stats

@Suite("Metrics formatting")
struct MetricsFormatterTests {
    // MARK: Byte rates

    @Test(
        "a byte rate picks the unit that keeps it to three or four characters",
        arguments: [
            (0.0, "0 B/s"),
            (12.0, "12 B/s"),
            (999.0, "999 B/s"),
            (1_024.0, "1.0 KB/s"),
            (1_536.0, "1.5 KB/s"),
            (20_480.0, "20 KB/s"),
            (2_621_440.0, "2.5 MB/s"),
            (1_073_741_824.0, "1.0 GB/s"),
            (5_497_558_138_880.0, "5.0 TB/s")
        ]
    )
    func byteRateUnits(bytesPerSecond: Double, expected: String) {
        #expect(MetricsFormatter.byteRate(bytesPerSecond) == expected)
    }

    @Test("a rate that rounds up over the unit boundary carries into the next unit")
    func byteRateCarries() {
        // Without the carry this prints "1024 KB/s", which is both wrong-looking
        // and a character wider than the column allows.
        #expect(MetricsFormatter.byteRate(1_048_570) == "1.0 MB/s")
    }

    @Test("an unknown rate is a dash, never a zero")
    func unknownByteRate() {
        #expect(MetricsFormatter.byteRate(nil) == MetricsFormatter.unavailable)
        #expect(MetricsFormatter.byteRate(.nan) == MetricsFormatter.unavailable)
        #expect(MetricsFormatter.byteRate(.infinity) == MetricsFormatter.unavailable)
    }

    @Test("byte sizes use the same scale without the per-second suffix")
    func byteSizes() {
        #expect(MetricsFormatter.bytes(0) == "0 B")
        #expect(MetricsFormatter.bytes(1_023) == "1023 B")
        #expect(MetricsFormatter.bytes(10_100_000_000) == "9.4 GB")
        #expect(MetricsFormatter.bytes(16 * 1024 * 1024 * 1024) == "16 GB")
    }

    // MARK: Battery time

    @Test(
        "battery time reads as hours and minutes",
        arguments: [
            (0, "0m"),
            (59, "0m"),
            (2_700, "45m"),
            (3_600, "1h"),
            (5_400, "1h 30m"),
            (36_000, "10h")
        ]
    )
    func batteryTimes(seconds: Int, expected: String) {
        #expect(MetricsFormatter.batteryTime(seconds) == expected)
    }

    @Test("no estimate formats as nothing at all, so the caller must say why")
    func missingBatteryTime() {
        // Returning "0m" here would tell the user the machine is about to die
        // while it is in fact charging.
        #expect(MetricsFormatter.batteryTime(nil) == nil)
        #expect(MetricsFormatter.batteryTime(-1) == nil)
    }

    // MARK: Percentages

    @Test(
        "percentages round half up and carry no decimals",
        arguments: [
            (0.0, "0%"),
            (0.004, "0%"),
            (0.125, "13%"),
            (0.454, "45%"),
            (0.456, "46%"),
            (0.999, "100%"),
            (1.0, "100%")
        ]
    )
    func percentages(fraction: Double, expected: String) {
        #expect(MetricsFormatter.percentage(fraction) == expected)
    }

    @Test("an unknown percentage is a dash")
    func unknownPercentage() {
        #expect(MetricsFormatter.percentage(nil) == MetricsFormatter.unavailable)
        #expect(MetricsFormatter.percentage(.nan) == MetricsFormatter.unavailable)
    }
}
