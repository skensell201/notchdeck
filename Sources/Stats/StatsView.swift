import SwiftUI

/// Four tiles across the panel: battery, CPU, memory, network.
///
/// The panel gives a module roughly 592 × 105 points, so each tile gets about
/// 140 wide — enough for a label, one headline figure and a line of detail, and
/// not enough for anything else. Every figure is `.monospacedDigit()`: these
/// numbers change twice a second at their fastest, and proportional digits make
/// the whole row twitch sideways when they do.
struct StatsView: View {
    // A plain reference is enough: the module is `@Observable`, so reads in
    // `body` are tracked.
    let module: StatsModule

    var body: some View {
        if let metrics = module.metrics {
            HStack(spacing: 10) {
                battery(metrics.battery)
                cpu(metrics.cpuUsage)
                memory(metrics.memory)
                network(metrics.throughput)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Sampling…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Tiles

    private func battery(_ status: BatteryStatus?) -> some View {
        Tile(symbol: Self.batterySymbol(status), title: "Battery") {
            if let status {
                Reading(
                    value: MetricsFormatter.percentage(status.charge),
                    meter: status.charge,
                    detail: Self.batteryDetail(status)
                )
            } else {
                // A Mac with no internal battery, which is a fact rather than a
                // failure to read one.
                Reading(value: MetricsFormatter.unavailable, meter: nil, detail: "No battery")
            }
        }
    }

    private func cpu(_ usage: Double?) -> some View {
        Tile(symbol: "cpu", title: "CPU") {
            Reading(
                value: MetricsFormatter.percentage(usage),
                meter: usage,
                detail: "across all cores"
            )
        }
    }

    private func memory(_ usage: MemoryUsage) -> some View {
        Tile(symbol: "memorychip", title: "Memory") {
            Reading(
                value: MetricsFormatter.bytes(usage.usedBytes),
                meter: usage.totalBytes > 0
                    ? Double(usage.usedBytes) / Double(usage.totalBytes)
                    : nil,
                detail: "of \(MetricsFormatter.bytes(usage.totalBytes))"
                    + " · \(MetricsFormatter.percentage(usage.pressure)) pressure"
            )
        }
    }

    /// Two rates rather than one headline figure: down and up are equally
    /// interesting, and neither is a share of anything, so there is no meter.
    private func network(_ throughput: Throughput?) -> some View {
        Tile(symbol: "arrow.up.arrow.down", title: "Network") {
            VStack(alignment: .leading, spacing: 4) {
                rate("arrow.down", MetricsFormatter.byteRate(throughput?.bytesInPerSecond))
                rate("arrow.up", MetricsFormatter.byteRate(throughput?.bytesOutPerSecond))
            }
        }
    }

    private func rate(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    // MARK: Battery presentation

    private static func batterySymbol(_ status: BatteryStatus?) -> String {
        guard let status else { return "battery.0" }
        if status.isCharging { return "battery.100.bolt" }
        return switch status.charge {
        case ..<0.15: "battery.0"
        case ..<0.40: "battery.25"
        case ..<0.65: "battery.50"
        case ..<0.90: "battery.75"
        default: "battery.100"
        }
    }

    private static func batteryDetail(_ status: BatteryStatus) -> String {
        guard let time = MetricsFormatter.batteryTime(status.secondsRemaining) else {
            // No estimate is the normal state on mains power and for the first
            // minutes after a wake, so it gets words rather than a dash.
            return status.isCharging ? "Charging" : "Estimating…"
        }
        return status.isCharging ? "\(time) to full" : "\(time) left"
    }
}

/// One panel of the row: a dim label above, the reading below, on a plate that
/// separates it from its neighbours without drawing a line.
private struct Tile<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 6)

            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.07))
        )
    }
}

/// A headline figure, a bar, and a line of detail. The bar is always drawn, even
/// where there is nothing to fill it with, so the four tiles keep the same
/// baselines while a figure is unknown.
private struct Reading: View {
    let value: String
    /// 0...1, or nil when the figure is unknown or is not a share of anything.
    let meter: Double?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * min(max(meter ?? 0, 0), 1))
                }
            }
            .frame(height: 4)

            Text(detail)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                // The memory detail is the longest string in the row and the
                // widest it can get depends on how much memory is installed.
                .minimumScaleFactor(0.85)
        }
    }
}
