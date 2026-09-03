import Testing
@testable import Media

@Suite("Playback position")
struct PlaybackPositionTests {
    private let start: Int64 = 1_788_357_423_000_000

    private func track(
        rate: Double,
        elapsed: Int64?,
        timestamp: Int64?,
        duration: Int64? = 125_000_000
    ) -> NowPlaying {
        NowPlaying(
            bundleIdentifier: "com.example",
            title: "Track",
            isPlaying: rate > 0,
            playbackRate: rate,
            elapsedTimeMicros: elapsed,
            durationMicros: duration,
            timestampEpochMicros: timestamp
        )
    }

    @Test("a playing track advances in real time")
    func playingAdvances() {
        let state = track(rate: 1, elapsed: 10_000_000, timestamp: start)

        let position = PlaybackPosition.micros(of: state, atEpochMicros: start + 5_000_000)

        #expect(position == 15_000_000)
    }

    @Test("a paused track does not advance, however long ago it was measured")
    func pausedIsFrozen() {
        let state = track(rate: 0, elapsed: 10_000_000, timestamp: start)

        let position = PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000)

        #expect(position == 10_000_000)
    }

    @Test("a restamped timestamp with no new elapsed value does not rewind the track")
    func restampedTimestampDoesNotRewind() {
        // On resume the adapter sends a fresh timestamp and playbackRate but keeps
        // the elapsed value from the pause. Interpolating from the new timestamp is
        // correct; interpolating from the old one would jump forward by the pause.
        let paused = track(rate: 0, elapsed: 28_000_000, timestamp: start)
        let resumed = track(rate: 1, elapsed: 28_000_000, timestamp: start + 6_000_000)

        #expect(PlaybackPosition.micros(of: paused, atEpochMicros: start + 6_000_000) == 28_000_000)
        #expect(PlaybackPosition.micros(of: resumed, atEpochMicros: start + 6_000_000) == 28_000_000)
        #expect(PlaybackPosition.micros(of: resumed, atEpochMicros: start + 8_000_000) == 30_000_000)
    }

    @Test("a double-speed track advances twice as fast")
    func rateIsHonoured() {
        let state = track(rate: 2, elapsed: 0, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 5_000_000) == 10_000_000)
    }

    @Test("position is clamped to the duration")
    func clampedToDuration() {
        let state = track(rate: 1, elapsed: 124_000_000, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000) == 125_000_000)
    }

    @Test("position never goes negative when the clock runs backwards")
    func neverNegative() {
        let state = track(rate: 1, elapsed: 1_000_000, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start - 60_000_000) == 0)
    }

    @Test("an unknown duration leaves the position unclamped")
    func unknownDuration() {
        let state = track(rate: 1, elapsed: 0, timestamp: start, duration: nil)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 900_000_000) == 900_000_000)
    }

    @Test("a track with no elapsed value has no position")
    func missingElapsed() {
        #expect(PlaybackPosition.micros(of: track(rate: 1, elapsed: nil, timestamp: start), atEpochMicros: start) == nil)
    }

    @Test("a track with no timestamp reports its elapsed value unchanged")
    func missingTimestamp() {
        let state = track(rate: 1, elapsed: 7_000_000, timestamp: nil)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000) == 7_000_000)
    }

    @Test("an extreme clock/rate combination clamps instead of trapping")
    func extremeDriftDoesNotTrap() {
        // A clock reset to 1970 combined with a large playbackRate used to produce
        // a drift around -1.8e25, which overflowed `Int64(drift)` and crashed.
        let state = track(rate: 1e10, elapsed: 0, timestamp: 1_788_357_423_000_000)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: 0) == 0)
    }

    @Test("progress is the fraction of the duration, and nil without one")
    func progress() {
        let state = track(rate: 0, elapsed: 25_000_000, timestamp: start)

        #expect(PlaybackPosition.progress(of: state, atEpochMicros: start) == 0.2)
        #expect(PlaybackPosition.progress(of: track(rate: 0, elapsed: 1, timestamp: start, duration: nil), atEpochMicros: start) == nil)
    }
}
