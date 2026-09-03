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

        let drift = Double(now - timestamp) * state.playbackRate
        var position = elapsed + Int64(drift)

        if let duration = state.durationMicros {
            position = min(position, duration)
        }
        return max(position, 0)
    }

    public static func progress(of state: NowPlaying, atEpochMicros now: Int64) -> Double? {
        guard let duration = state.durationMicros, duration > 0,
              let position = micros(of: state, atEpochMicros: now) else {
            return nil
        }
        return Double(position) / Double(duration)
    }
}
