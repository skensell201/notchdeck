import Foundation
import Observation
import Support

/// Which shortcuts are pinned, and the ordering rule that puts them first.
///
/// Pins are stored by name, independent of whatever `shortcuts list` currently
/// returns. That is deliberate: a pin outlives the shortcut it names. If the
/// user deletes a pinned shortcut, its pin is not removed — it simply stops
/// appearing in `ordered(_:)`, because that name is no longer in the list
/// being ordered. If they later recreate a shortcut with the same name, it
/// comes back pinned without the user having to pin it again. Unpinning a
/// deleted shortcut is therefore never required to keep the pin set tidy.
@MainActor
@Observable
public final class ShortcutsFavoritesStore {
    public private(set) var pinnedNames: Set<String> = []

    private let persistence: any ShortcutsFavoritesPersisting
    private let logger = Log.make("shortcuts.favorites")

    public init(persistence: any ShortcutsFavoritesPersisting) {
        self.persistence = persistence
    }

    public func load() {
        do {
            pinnedNames = try persistence.load()
        } catch {
            logger.error("could not load pinned shortcuts: \(error.localizedDescription, privacy: .public)")
            pinnedNames = []
        }
    }

    public func isPinned(_ name: String) -> Bool {
        pinnedNames.contains(name)
    }

    public func togglePin(_ name: String) {
        if pinnedNames.contains(name) {
            pinnedNames.remove(name)
        } else {
            pinnedNames.insert(name)
        }
        save()
    }

    /// `names` ordered with pinned ones first, each group sorted alphabetically
    /// (case-insensitive) within itself. A pinned name absent from `names` —
    /// its shortcut was deleted — is simply not shown; see the type comment.
    public func ordered(_ names: [String]) -> [String] {
        let (pinned, rest) = names.reduce(into: ([String](), [String]())) { partial, name in
            if pinnedNames.contains(name) {
                partial.0.append(name)
            } else {
                partial.1.append(name)
            }
        }
        return alphabetical(pinned) + alphabetical(rest)
    }

    private func alphabetical(_ names: [String]) -> [String] {
        names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func save() {
        do {
            try persistence.save(pinnedNames)
        } catch {
            logger.error("could not save pinned shortcuts: \(error.localizedDescription, privacy: .public)")
        }
    }
}
