import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class ShortcutsModule: NotchModule {
    public static let id = ModuleID("shortcuts")
    public let title = "Shortcuts"
    public let symbolName = "wand.and.stars"

    public private(set) var names: [String] = []
    public var query: String = ""

    /// True while a `list` is in flight, so the view can show a spinner on the
    /// first load instead of an empty state that looks like "no shortcuts".
    public private(set) var isListing = false

    /// The shortcut currently running, if any. Only one run is tracked at a
    /// time — the view uses this to show a spinner or dim the row.
    public private(set) var runningName: String?

    public let favorites: ShortcutsFavoritesStore

    private let runner: any ShortcutsRunning
    private let logger = Log.make("shortcuts")
    private var listTask: Task<Void, Never>?

    public init(
        runner: any ShortcutsRunning = ShortcutsProcessRunner(),
        favorites: ShortcutsFavoritesStore? = nil
    ) {
        self.runner = runner
        self.favorites = favorites ?? ShortcutsFavoritesStore(
            persistence: DiskShortcutsFavoritesPersistence.inApplicationSupport()
        )
        self.favorites.load()
    }

    // MARK: NotchModule

    public func activate() {
        refresh()
    }

    /// A shortcut that is mid-run is deliberately left alone here: it is
    /// fire-and-forget, and closing the panel should not abort work the user
    /// asked for. Only the listing, which exists purely to populate this
    /// panel, is worth cancelling.
    public func deactivate() {
        listTask?.cancel()
        listTask = nil
    }

    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }
    public func expandedView() -> AnyView { AnyView(ShortcutsView(module: self)) }

    // MARK: Listing

    public func refresh() {
        listTask?.cancel()
        isListing = true
        listTask = Task { [weak self] in
            guard let self else { return }
            // `defer`, not a trailing assignment: a cancelled listing still
            // returns early below (it must not overwrite `names` with a stale
            // result), and without this `isListing` would be left stuck true.
            defer { self.isListing = false }
            do {
                let listed = try await runner.list()
                guard !Task.isCancelled else { return }
                names = listed
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("could not list shortcuts: \(error.localizedDescription, privacy: .public)")
                names = []
            }
        }
    }

    // MARK: Ordering and search

    /// The names to draw: search-filtered, then pinned-first.
    public var visibleNames: [String] {
        favorites.ordered(ShortcutsSearch.filter(names, matching: query))
    }

    public func isPinned(_ name: String) -> Bool {
        favorites.isPinned(name)
    }

    public func togglePin(_ name: String) {
        favorites.togglePin(name)
    }

    // MARK: Running

    /// Fire-and-forget: the click returns immediately, `runningName` gives the
    /// view something to show while the shortcut is mid-flight, and a
    /// non-zero exit is logged rather than swallowed — `shortcuts run` fails
    /// non-zero when the shortcut itself fails, and that is exactly the case
    /// where staying silent would be worse than useless.
    public func run(_ name: String) {
        guard runningName == nil else { return }
        runningName = name
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await runner.run(name: name)
            if !succeeded {
                logger.error("shortcut \"\(name, privacy: .public)\" exited with a failure")
            }
            runningName = nil
        }
    }
}
