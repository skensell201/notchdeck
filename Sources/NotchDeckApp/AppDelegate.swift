import AppKit
import Clipboard
import Media
import Mirror
import NotchCore
import NotchUI
import NotchWindow
import Pomodoro
import Shelf
import Stats
import Support

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Log.make("app")
    private let controller = NotchController()
    private var registry: ModuleRegistry?
    private var media: MediaModule?
    private var shelf: ShelfModule?
    private var clipboard: ClipboardModule?
    private var timer: TimerModule?
    private var stats: StatsModule?
    private var mirror: MirrorModule?
    private var surfaces: NotchSurfaceManager?
    private var monitor: NotchEventMonitor?
    private var statusItem: NSStatusItem?
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        routeSignalsThroughTerminate()
        let registry = ModuleRegistry()
        let media = MediaModule()
        registry.register(media)
        self.registry = registry
        self.media = media

        let shelf = ShelfModule()
        registry.register(shelf)
        self.shelf = shelf

        let clipboard = ClipboardModule()
        registry.register(clipboard)
        self.clipboard = clipboard

        let timer = TimerModule()
        registry.register(timer)
        self.timer = timer

        let stats = StatsModule()
        registry.register(stats)
        self.stats = stats

        let mirror = MirrorModule()
        registry.register(mirror)
        self.mirror = mirror

        let surfaces = NotchSurfaceManager(registry: registry)
        self.surfaces = surfaces

        surfaces.onDragEntered = { [weak self] in
            // Open the notch and land the drag on the shelf, whichever tab was
            // showing — a dragged file has exactly one sensible destination.
            self?.controller.send(.dragEntered)
            registry.select(ShelfModule.id)
        }
        surfaces.onDragExited = { [weak self] in
            self?.controller.send(.dragExited)
        }
        surfaces.onDragMoved = { point in
            shelf.dragMoved(to: point)
        }
        surfaces.onDrop = { urls, point in
            shelf.accept(urls, at: point)
        }

        controller.onStateChange = { state in
            surfaces.apply(mode: state.mode)
            registry.setPanelVisible(state.isExpanded)
        }

        let monitor = NotchEventMonitor(
            surfaces: surfaces,
            send: { [weak self] event in self?.controller.send(event) },
            onHorizontalSwipe: { [weak media] direction in
                // Leftward moves forward, matching the natural-scrolling
                // convention the accumulator documents.
                media?.perform(direction == .left ? .next : .previous)
            }
        )
        monitor.start()
        self.monitor = monitor

        // The stream must be up before the panel is ever opened, or the collapsed
        // peek has nothing to show.
        media.startStreaming()

        installStatusItem()
        logger.notice("NotchDeck started with \(surfaces.allSurfaces.count, privacy: .public) surfaces")
    }

    /// A Cocoa app that receives SIGTERM just dies — `applicationWillTerminate`
    /// never runs, so nothing would stop the adapter subprocess. `pkill`, `run.sh`
    /// and logout all deliver SIGTERM. Turning it into a normal `terminate` gives
    /// every quit path the same clean shutdown.
    private func routeSignalsThroughTerminate() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        termination = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchronous on purpose: this is the last main-actor turn. The adapter
        // subprocess is silent while nothing plays, so it would otherwise outlive
        // the app indefinitely.
        media?.shutdown()
        monitor?.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "NotchDeck"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Notch",
            action: #selector(openNotch),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit NotchDeck",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        controller.send(.clicked)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
