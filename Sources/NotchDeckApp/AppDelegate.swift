import AppKit
import NotchCore
import NotchWindow
import Support

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Log.make("app")
    private let controller = NotchController()
    private var surfaces: NotchSurfaceManager?
    private var monitor: NotchEventMonitor?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let surfaces = NotchSurfaceManager()
        self.surfaces = surfaces

        controller.onStateChange = { state in
            surfaces.apply(mode: state.mode)
        }

        let monitor = NotchEventMonitor(surfaces: surfaces) { [weak self] event in
            self?.controller.send(event)
        }
        monitor.start()
        self.monitor = monitor

        installStatusItem()
        logger.info("NotchDeck started with \(surfaces.allSurfaces.count, privacy: .public) surfaces")
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
