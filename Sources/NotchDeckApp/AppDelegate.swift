import Agenda
import AppKit
import Clipboard
import LiveActivities
import Media
import Mirror
import NotchCore
import NotchUI
import NotchWindow
import Preferences
import ServiceManagement
import SettingsUI
import Pomodoro
import Shelf
import Shortcuts
import Stats
import SystemHUD
import Support

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Log.make("app")
    private var controller = NotchController()
    private var registry: ModuleRegistry?
    private var media: MediaModule?
    private var shelf: ShelfModule?
    private var clipboard: ClipboardModule?
    private var timer: TimerModule?
    private var stats: StatsModule?
    private var mirror: MirrorModule?
    private var shortcuts: ShortcutsModule?
    private var agenda: AgendaModule?
    private var activities: LiveActivityCenter?
    private var hud: SystemHUDController?
    private let preferences = Preferences()
    private var escapeMonitor: Any?
    private var settings: SettingsWindowController?
    private var preferenceWatch: Task<Void, Never>?
    private var surfaces: NotchSurfaceManager?
    private var monitor: NotchEventMonitor?
    private var statusItem: NSStatusItem?
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        routeSignalsThroughTerminate()
        controller = NotchController(timing: preferences.timing)

        let registry = ModuleRegistry(layout: preferences.moduleLayout)
        let media = MediaModule()
        registry.register(media)
        self.registry = registry
        self.media = media

        let shelf = ShelfModule()
        registry.register(shelf)
        self.shelf = shelf

        let clipboard = ClipboardModule(
            capacity: preferences.clipboardCapacity,
            excludedBundleIdentifiers: Set(preferences.clipboardExclusions)
        )
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

        let shortcuts = ShortcutsModule()
        registry.register(shortcuts)
        self.shortcuts = shortcuts

        let agenda = AgendaModule()
        registry.register(agenda)
        self.agenda = agenda

        let surfaces = NotchSurfaceManager(registry: registry, syntheticSize: preferences.syntheticNotchSize)
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

        // Announcements — charging, volume, a device connecting — reach the notch
        // through the state machine's timed peek mode, which has existed and been
        // tested since P0 with nothing to trigger it.
        let activities = LiveActivityCenter()
        activities.onActivity = { [weak self] payload in
            self?.controller.send(.liveActivity(payload))
        }
        activities.start()
        self.activities = activities

        let hud = SystemHUDController()
        hud.applyPreference()
        self.hud = hud

        let settings = SettingsWindowController(
            preferences: preferences,
            registry: registry,
            launchAtLogin: ClosureLaunchAtLogin(
                read: { SMAppService.mainApp.status == .enabled },
                write: { enabled in
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                }
            )
        )
        self.settings = settings

        followPreferences(surfaces: surfaces, hud: hud)

        installEscapeMonitorIfPermitted()
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
        preferenceWatch?.cancel()
        activities?.stop()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        // The layout is the one setting the app itself changes at runtime, when a
        // module registers for the first time.
        if let registry {
            preferences.moduleLayout = registry.layout
        }
        // Last chance to give the Mac its own volume overlay back.
        hud?.restore()
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
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let suppress = NSMenuItem(
            title: "Replace the system volume overlay",
            action: #selector(toggleVolumeHUD),
            keyEquivalent: ""
        )
        suppress.target = self
        suppress.state = hud?.isEnabled == true ? .on : .off
        menu.addItem(suppress)
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

    /// `.escapePressed` has been in the state machine since P0 with nothing to
    /// send it: a global key monitor needs Accessibility, and nothing else in the
    /// app needs any permission at all. So it is opt-in and only installed when
    /// the grant is already there — asking for Accessibility on launch, for a
    /// keyboard shortcut, would be a bad trade.
    private func installEscapeMonitorIfPermitted() {
        guard preferences.dismissWithEscape, AXIsProcessTrusted() else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.controller.send(.escapePressed) }
        }
    }

    /// Preferences are the single source for everything the settings window can
    /// change, so the menu item and the window cannot disagree. Polling rather
    /// than observing: `Preferences` is `@Observable`, and observation outside a
    /// SwiftUI body needs a re-registering `withObservationTracking` loop that is
    /// more machinery than a one-second read of a handful of defaults.
    private func followPreferences(surfaces: NotchSurfaceManager, hud: SystemHUDController) {
        preferenceWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                controller.timing = preferences.timing
                surfaces.syntheticSize = preferences.syntheticNotchSize
                if hud.isEnabled != preferences.suppressVolumeHUD {
                    hud.isEnabled = preferences.suppressVolumeHUD
                }
            }
        }
    }

    @objc private func openSettings() {
        settings?.show()
    }

    @objc private func toggleVolumeHUD(_ sender: NSMenuItem) {
        preferences.suppressVolumeHUD.toggle()
        hud?.isEnabled = preferences.suppressVolumeHUD
        sender.state = preferences.suppressVolumeHUD ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
