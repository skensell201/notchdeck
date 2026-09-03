import AppKit
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class MediaModule: NotchModule {
    public static let id = ModuleID("media")
    public let title = "Media"
    public let symbolName = "play.circle"

    /// The current track, or nil when nothing is known.
    public private(set) var state: NowPlaying?
    /// The current track's artwork, decoded once per distinct image rather than
    /// on every redraw. Keyed by the bytes, not `contentItemIdentifier`: the spike
    /// showed the identifier changing on every pause and resume while the artwork
    /// stayed the same, and artwork only ever arrives in full snapshots anyway.
    public private(set) var artworkImage: NSImage?
    /// True once the adapter probe has failed; the UI explains itself instead of
    /// pretending nothing is playing.
    public private(set) var isDegraded = false
    /// Ticks once a second while a track is playing so the scrubber advances.
    public private(set) var positionTick: Int64 = 0
    /// Set while the user drags the scrubber, so incoming updates do not fight them.
    public var scrubbingProgress: Double?
    private var awaitingSeekEcho = false
    private var seekEchoTimeout: Task<Void, Never>?
    /// True once a paused track has sat untouched for `peekStaleness`. Observable
    /// so the shell can react to it: the flag flips from a scheduled task rather
    /// than being recomputed from timestamps, which nothing would re-read.
    public private(set) var isStale = false

    private let logger = Log.make("media")
    private let paths: AdapterPaths?
    private let commands: MediaCommands
    private var decoder = NowPlayingDecoder()
    private var artworkData: Data?
    private var streamTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var stalenessTask: Task<Void, Never>?
    /// The adapter stream currently being consumed, kept so `shutdown()` can stop
    /// its subprocess synchronously.
    private var currentSource: PerlAdapterStream?

    /// A paused track older than this stops appearing in the collapsed notch. The
    /// adapter never says "stopped", so this is our own policy.
    private let peekStaleness: Duration = .seconds(90)

    public init(paths: AdapterPaths? = AdapterPaths.inMainBundle()) {
        self.paths = paths
        let runner = paths.map(PerlAdapterCommandRunner.init(paths:))
        self.commands = MediaCommands(adapter: runner, keys: SystemMediaKeyPoster())
    }

    // MARK: NotchModule

    public func activate() {
        // Both halves are independently idempotent: the stream starts once and
        // outlives the panel, while the tick is panel-scoped and restarts every
        // time the notch opens.
        startStreaming()
        if tickTask == nil {
            startTicking()
        }
    }

    /// Starts only the now-playing stream, without the panel-scoped redraw tick.
    /// The app calls this at launch so the collapsed peek works before the panel
    /// is ever opened; `activate()` is what the registry calls when it is.
    public func startStreaming() {
        if streamTask == nil {
            startStream()
        }
    }

    public func deactivate() {
        // The stream is the module's live state, not the panel's: it must keep
        // running while the notch is closed, or the peek would have nothing to
        // show. Only the once-a-second UI tick is panel-scoped.
        tickTask?.cancel()
        tickTask = nil
    }

    public func expandedView() -> AnyView {
        AnyView(MediaPlayerView(module: self))
    }

    public func peekView() -> AnyView? {
        guard hasLiveContent, let state else { return nil }
        return AnyView(MediaPeekView(state: state, artwork: artworkImage))
    }

    public var hasLiveContent: Bool {
        state != nil && !isStale
    }

    /// Stops the adapter subprocess and every timer, synchronously. Called from
    /// `applicationWillTerminate`, which is the last chance to do it: cancelling the
    /// stream task alone would only take effect on a later main-actor turn that
    /// never comes.
    public func shutdown() {
        streamTask?.cancel()
        tickTask?.cancel()
        stalenessTask?.cancel()
        seekEchoTimeout?.cancel()
        currentSource?.stop()
        streamTask = nil
        tickTask = nil
        stalenessTask = nil
        currentSource = nil
    }

    // MARK: Playback

    public func perform(_ action: TransportAction) {
        Task { await commands.perform(action) }
    }

    public func seek(toProgress progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard let duration = state?.durationMicros else {
            // Nothing to seek in; drop the drag rather than leaving the bar
            // frozen at the drag position for every later track.
            scrubbingProgress = nil
            return
        }
        let target = Int64(Double(duration) * clamped)

        // Hold the bar at the target until the adapter reports the new position,
        // otherwise it snaps back to the pre-seek position for the round trip.
        scrubbingProgress = clamped
        awaitingSeekEcho = true
        seekEchoTimeout?.cancel()

        Task {
            let succeeded = await commands.seek(toMicros: target)
            if !succeeded {
                logger.notice("seek failed; the adapter is unavailable")
                releaseScrubber()
            }
        }
        seekEchoTimeout = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            releaseScrubber()
        }
    }

    private func releaseScrubber() {
        awaitingSeekEcho = false
        seekEchoTimeout?.cancel()
        seekEchoTimeout = nil
        scrubbingProgress = nil
    }

    public var progress: Double? {
        if let scrubbingProgress { return scrubbingProgress }
        guard let state else { return nil }
        return PlaybackPosition.progress(of: state, atEpochMicros: Self.nowMicros())
    }

    public var positionMicros: Int64? {
        guard let state else { return nil }
        return PlaybackPosition.micros(of: state, atEpochMicros: Self.nowMicros())
    }

    // MARK: Internals

    static func nowMicros() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    private func startStream() {
        guard let paths else {
            isDegraded = true
            logger.error("the media adapter is missing from the bundle")
            return
        }

        streamTask = Task { [weak self] in
            // A previous instance that died ungracefully leaves its idle adapter
            // behind; clear it before starting our own so exactly one runs.
            await AdapterReaper.reapOrphans(of: paths)
            let runner = PerlAdapterCommandRunner(paths: paths)
            let works = await runner.probe()
            guard let self else { return }
            if !works {
                self.isDegraded = true
                self.logger.error("the media adapter probe failed; transport only")
                return
            }

            // A crash-looping adapter always prints its priming `{}` line first,
            // so "did this attempt see any line" resets the backoff on every
            // single crash — the loop never actually backs off. What matters is
            // whether the stream *stayed up*: only a connection that survived for
            // a while indicates the adapter is genuinely healthy again.
            let minimumHealthyUptime: Duration = .seconds(5)
            let clock = ContinuousClock()
            var attempt = 0
            while !Task.isCancelled {
                let delay = AdapterBackoff.delay(forAttempt: attempt)
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { break }
                }
                let source = PerlAdapterStream(paths: paths)
                self.currentSource = source
                let started = clock.now
                for await line in source.lines() {
                    self.consume(line)
                }
                self.currentSource = nil
                attempt = clock.now - started >= minimumHealthyUptime ? 0 : attempt + 1
            }
        }
    }

    private func consume(_ line: String) {
        let previous = state
        if let updated = decoder.consume(line: line) {
            state = updated
        } else if decoder.snapshot == nil {
            // An empty full payload is the adapter's "nothing playing" signal.
            state = nil
        }
        if awaitingSeekEcho, positionChanged(from: previous, to: state) {
            releaseScrubber()
        }
        refreshArtwork()
        rescheduleStaleness()
    }

    private func positionChanged(from previous: NowPlaying?, to current: NowPlaying?) -> Bool {
        previous?.elapsedTimeMicros != current?.elapsedTimeMicros
            || previous?.timestampEpochMicros != current?.timestampEpochMicros
    }

    /// Drives `isStale` without polling: a playing track is never stale, and a
    /// paused one becomes stale `peekStaleness` after its last update. The
    /// snapshot's own timestamp counts towards that, so a track that was paused
    /// long before launch is stale straight away rather than 90 s later.
    private func rescheduleStaleness() {
        stalenessTask?.cancel()
        stalenessTask = nil
        guard let state, state.playbackRate == 0, !state.isPlaying else {
            isStale = false
            return
        }
        let age: Duration = state.timestampEpochMicros
            .map { .microseconds(max(Self.nowMicros() - $0, 0)) } ?? .zero
        let remaining = peekStaleness - age
        guard remaining > .zero else {
            isStale = true
            return
        }
        isStale = false
        stalenessTask = Task { [weak self] in
            try? await Task.sleep(for: remaining)
            guard !Task.isCancelled else { return }
            self?.isStale = true
        }
    }

    private func refreshArtwork() {
        let data = state?.artwork?.data
        guard data != artworkData else { return }
        artworkData = data
        artworkImage = data.flatMap(NSImage.init(data:))
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.positionTick &+= 1
            }
        }
    }
}
