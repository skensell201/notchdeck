import Foundation

/// The `shortcuts` CLI, behind a seam. Nothing above this protocol may know
/// about `Process` — see `ShortcutsProcessRunner` for the one place that does.
///
/// Both operations need no permission: unlike Calendar or the camera, macOS
/// never prompts for `shortcuts list` or `shortcuts run`.
public protocol ShortcutsRunning: Sendable {
    /// The user's shortcuts, in whatever order the CLI prints them — callers
    /// that care about order (favourites first, alphabetical) apply it
    /// themselves.
    func list() async throws -> [String]

    /// Runs a shortcut by name. Returns whether it exited cleanly: `shortcuts
    /// run` exits non-zero when the shortcut itself fails, and that is a real
    /// signal, not noise to swallow.
    func run(name: String) async -> Bool
}

/// What can go wrong launching or running the `shortcuts` binary itself, as
/// opposed to a shortcut failing (which `run(name:)` reports as `false`, not
/// as a thrown error).
public enum ShortcutsProcessError: Error, Sendable {
    /// The process could not be started at all.
    case launchFailed
    /// `shortcuts list` exited non-zero.
    case nonZeroExit(Int32)
}
