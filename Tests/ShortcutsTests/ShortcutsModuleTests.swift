import Testing
@testable import Shortcuts

/// A runner the test controls: `list()` returns whatever is queued, `run(name:)`
/// records what it was asked to run and returns the queued result.
final actor FakeShortcutsRunner: ShortcutsRunning {
    var listResult: Result<[String], Error> = .success([])
    var listDelay: Duration = .zero
    var runResult = true
    private(set) var ranNames: [String] = []

    func list() async throws -> [String] {
        if listDelay > .zero {
            try? await Task.sleep(for: listDelay)
        }
        return try listResult.get()
    }

    func run(name: String) async -> Bool {
        ranNames.append(name)
        return runResult
    }
}

private struct AnError: Error {}

@MainActor
@Suite("Shortcuts module")
struct ShortcutsModuleTests {
    private func makeModule(runner: FakeShortcutsRunner = FakeShortcutsRunner()) -> ShortcutsModule {
        let favorites = ShortcutsFavoritesStore(persistence: MemoryFavoritesPersistence())
        return ShortcutsModule(runner: runner, favorites: favorites)
    }

    @Test("the module identifies itself as shortcuts")
    func moduleID() {
        #expect(ShortcutsModule.id.rawValue == "shortcuts")
    }

    @Test("shortcuts has nothing for the collapsed notch")
    func noLiveContent() {
        let module = makeModule()
        #expect(!module.hasLiveContent)
        #expect(module.peekView() == nil)
    }

    @Test("activating lists the shortcuts")
    func activateLists() async {
        let runner = FakeShortcutsRunner()
        await runner.setListResult(.success(["Focus Mode", "Good Morning"]))
        let module = makeModule(runner: runner)

        module.activate()
        // The listing runs on a Task; give it a turn to complete.
        while module.isListing { await Task.yield() }

        #expect(module.names == ["Focus Mode", "Good Morning"])
    }

    @Test("a failed listing clears the names instead of leaving stale ones")
    func failedListingClears() async {
        let runner = FakeShortcutsRunner()
        await runner.setListResult(.failure(AnError()))
        let module = makeModule(runner: runner)

        module.activate()
        while module.isListing { await Task.yield() }

        #expect(module.names.isEmpty)
    }

    @Test("deactivating cancels an in-flight listing before it can apply a stale result")
    func deactivateCancelsListing() async {
        let runner = FakeShortcutsRunner()
        await runner.setListDelay(.milliseconds(30))
        await runner.setListResult(.success(["Should Not Appear"]))
        let module = makeModule(runner: runner)

        module.activate()
        module.deactivate()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(module.names.isEmpty)
        #expect(!module.isListing)
    }

    @Test("running a shortcut sets and clears runningName, and forwards the name")
    func runSetsAndClearsRunningName() async {
        let runner = FakeShortcutsRunner()
        let module = makeModule(runner: runner)

        module.run("Focus Mode")
        #expect(module.runningName == "Focus Mode")

        while module.runningName != nil { await Task.yield() }

        #expect(await runner.ranNames == ["Focus Mode"])
    }

    @Test("a second run request is ignored while one is already in flight")
    func concurrentRunIsIgnored() async {
        let runner = FakeShortcutsRunner()
        let module = makeModule(runner: runner)

        module.run("First")
        module.run("Second")
        while module.runningName != nil { await Task.yield() }

        #expect(await runner.ranNames == ["First"])
    }

    @Test("search and pinning compose: pinned matches sort ahead of other matches")
    func visibleNamesComposesSearchAndPins() async {
        let runner = FakeShortcutsRunner()
        await runner.setListResult(.success(["Zebra Task", "Apple Task", "Zesty Snack"]))
        let module = makeModule(runner: runner)
        module.activate()
        while module.isListing { await Task.yield() }
        module.togglePin("Zebra Task")

        module.query = "z"

        #expect(module.visibleNames == ["Zebra Task", "Zesty Snack"])
    }
}

private extension FakeShortcutsRunner {
    func setListResult(_ result: Result<[String], Error>) {
        listResult = result
    }

    func setListDelay(_ delay: Duration) {
        listDelay = delay
    }
}
