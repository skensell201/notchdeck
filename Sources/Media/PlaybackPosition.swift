import Foundation

/// Works out where a track actually is right now.
///
/// The adapter reports a position measured at a timestamp and never updates it
/// again until something changes, so the current position has to be interpolated.
/// `playbackRate` — not `isPlaying` — is what drives it: the adapter restamps the
/// timestamp on resume without resending the elapsed value, and a rate of zero is
/// what keeps a paused track from drifting.
public enum PlaybackPosition {
    public static func micros(of state: NowPlaying, atEpochMicros now: Int64) -> Int64? {
        guard let elapsed = state.elapsedTimeMicros else { return nil }
        guard let timestamp = state.timestampEpochMicros else { return elapsed }

        // Compute entirely in `Double`: `now - timestamp` can overflow `Int64` for
        // extreme inputs (an adapter-reported clock reset to 1970, say), and a
        // large `playbackRate` can blow the drift far past what `Int64` can hold —
        // `Int64(drift)` traps in that case. Everything is clamped in floating
        // point before ever converting back to `Int64`.
        let drift = (Double(now) - Double(timestamp)) * state.playbackRate
        guard drift.isFinite else {
            return drift > 0 ? (state.durationMicros ?? Int64.max) : 0
        }

        // `Double(Int64.max)` itself rounds up to 2^63, one past what `Int64` can
        // hold, so converting it back would trap; `.nextDown` is the nearest
        // representable value that safely round-trips.
        let upperBound = state.durationMicros.map(Double.init) ?? Double(Int64.max).nextDown
        let position = min(max(Double(elapsed) + drift, 0), upperBound)
        return Int64(position)
    }

    public static func progress(of state: NowPlaying, atEpochMicros now: Int64) -> Double? {
        guard let duration = state.durationMicros, duration > 0,
              let position = micros(of: state, atEpochMicros: now) else {
            return nil
        }
        return Double(position) / Double(duration)
    }
}
