import AppKit
import Media
import NotchCore
import NotchUI
import NotchWindow
import Support

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Log.make("app")
    private let controller = NotchController()
    private var registry: ModuleRegistry?
    private var media: MediaModule?
    private var surfaces: NotchSurfaceManager?
    private var monitor: NotchEventMonitor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = ModuleRegistry()
        let media = MediaModule()
        registry.register(media)
        self.registry = registry
        self.media = media

        let surfaces = NotchSurfaceManager(registry: registry)
        self.surfaces = surfaces

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
        media.activate()

        installStatusItem()
        logger.notice("NotchDeck started with \(surfaces.allSurfaces.count, privacy: .public) surfaces")
    }

    func applicationWillTerminate(_ notification: Notification) {
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
