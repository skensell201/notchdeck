import NotchCore
import Support

/// Owns the live-activity sources and forwards what they announce to one sink.
///
/// Deliberately thin: it starts and stops the sources together and does nothing
/// to what passes through. Coalescing is not its job — two activities with the
/// same `id` already replace each other in the reducer, which is what makes a
/// held volume key show one moving bar instead of a queue of announcements.
@MainActor
public final class LiveActivityCenter {
    /// Where announcements go. Set it before `start`; the app sends each payload
    /// on to the notch as a `.liveActivity` event.
    public var onActivity: ((PeekPayload) -> Void)?

    private let sources: [any LiveActivitySource]
    private var isRunning = false
    private let logger = Log.make("live-activities")

    /// - Parameter sources: defaults to the three real ones. Pass fakes in tests;
    ///   pass a subset to run with, say, power announcements only.
    public init(sources: [any LiveActivitySource] = LiveActivityCenter.systemSources()) {
        self.sources = sources
    }

    /// The sources that watch the actual machine.
    ///
    /// A function rather than a stored default so that constructing a centre with
    /// fakes never touches IOKit or CoreAudio.
    public static func systemSources() -> [any LiveActivitySource] {
        [PowerActivitySource(), VolumeActivitySource(), OutputDeviceActivitySource()]
    }

    /// Idempotent: starting twice would otherwise leave every source with two
    /// listeners and the notch announcing everything twice.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        for source in sources {
            source.start { [weak self] payload in
                self?.onActivity?(payload)
            }
        }
        logger.notice("live activities started with \(self.sources.count, privacy: .public) sources")
    }

    /// Must be called before the app goes away: the sources hold run-loop sources
    /// and CoreAudio listeners that the system will otherwise keep calling.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        for source in sources {
            source.stop()
        }
    }
}
