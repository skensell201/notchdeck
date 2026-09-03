import Foundation

public enum PomodoroClock {
    /// A countdown as `MM:SS`.
    ///
    /// Rounded up, not down: a phase that has just started has a hair under its
    /// full duration left and must still read 25:00, and the final second must
    /// read 00:01 for its whole length rather than sitting on 00:00 while the
    /// timer is still going. Zero and anything past the deadline read 00:00.
    public static func text(_ remaining: Duration) -> String {
        let parts = remaining.components
        guard parts.seconds > 0 || parts.attoseconds > 0 else { return "00:00" }
        let seconds = parts.seconds + (parts.attoseconds > 0 ? 1 : 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
