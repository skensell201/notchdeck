import NotchCore
import NotchUI
import Observation
import SwiftUI

/// Battery, CPU, memory and network throughput, sampled only while the panel is
/// showing them.
@MainActor
@Observable
public final class StatsModule: NotchModule {
    public static let id = ModuleID("stats")
    public let title = "Stats"
    public let symbolName = "gauge.with.dots.needle.bottom.50percent"

    /// Nil until the module is first activated. It keeps the last reading after
    /// that, including across a deactivation: `activate()` replaces it
    /// synchronously, so the panel never shows a stale figure, and leaving it in
    /// place stops the closing panel from flashing its empty state.
    public private(set) var metrics: DerivedMetrics?

    private let sampler: any MetricsSampling
    private let interval: Duration
    /// The predecessor every rate is measured against. Cleared on deactivation so
    /// a reopened panel does not divide a fresh sample by however long the notch
    /// happened to be closed.
    private var previous: MetricsSample?
    private var task: Task<Void, Never>?

    public init(sampler: any MetricsSampling = SystemMetricsSampler(), interval: Duration = .seconds(2)) {
        self.sampler = sampler
        self.interval = interval
    }

    // MARK: NotchModule

    public func activate() {
        guard task == nil else { return }
        // Sampled straight away so battery and memory — levels, which need only
        // one sample — are on screen the moment the panel opens. CPU and
        // throughput show as unknown until the second sample arrives, which is
        // the honest answer for an interval that has not happened yet.
        take()
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.take()
            }
        }
    }

    public func deactivate() {
        // A closed notch costs nothing: no timer, and no sample held back to be
        // differenced against one taken minutes later.
        task?.cancel()
        task = nil
        previous = nil
    }

    public func expandedView() -> AnyView {
        AnyView(StatsView(module: self))
    }

    /// Stats never widen the collapsed notch. A number that is merely interesting
    /// does not earn the user's attention the way a playing track does.
    public func peekView() -> AnyView? { nil }
    public var hasLiveContent: Bool { false }

    // MARK: Sampling

    private func take() {
        let current = sampler.sample()
        metrics = MetricsDeriver.derive(previous: previous, current: current)
        previous = current
    }
}
