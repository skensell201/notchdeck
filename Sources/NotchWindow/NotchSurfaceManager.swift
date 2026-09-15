import AppKit
import NotchCore
import NotchUI
import Support

/// Owns one `NotchSurface` per screen and rebuilds them when displays change.
@MainActor
public final class NotchSurfaceManager {
    private let logger = Log.make("surfaces")
    private let registry: ModuleRegistry
    /// Settable so the Notch tab previews on the displays it affects. Changing it
    /// re-resolves every surface, which is exactly what a display reconfiguration
    /// does, so the path is already exercised.
    public var syntheticSize: CGSize {
        didSet {
            guard syntheticSize != oldValue else { return }
            rebuild()
        }
    }
    /// Settable for the same reason as `syntheticSize`: the settings window has to
    /// be able to repaint a running notch. Unlike a resize this needs no rebuild —
    /// each surface keeps its panel and only its model changes.
    public var appearance: NotchAppearance {
        didSet {
            guard appearance != oldValue else { return }
            for surface in surfaces.values {
                surface.update(appearance: appearance)
            }
        }
    }
    private var surfaces: [CGDirectDisplayID: NotchSurface] = [:]
    private var observer: NSObjectProtocol?
    private var mode: NotchMode = .closed
    /// Remembered alongside the mode so a surface rebuilt mid-announcement — a
    /// display waking while a drop is falling — comes back showing it.
    private var drop: PeekPayload?

    /// Settable for the same reason as `appearance`, and pushed to every surface
    /// rather than read from a preference by each of them: the shell knows how
    /// wide to draw, not where the choice is stored.
    public var showsLiveContentWhenClosed: Bool {
        didSet {
            guard showsLiveContentWhenClosed != oldValue else { return }
            for surface in surfaces.values {
                surface.update(showsLiveContentWhenClosed: showsLiveContentWhenClosed)
            }
        }
    }

    /// One drag-handling seam for every surface, present and future. Each surface
    /// forwards to these at call time, so they may be assigned after `init`.
    public var onDragEntered: (() -> Void)?
    public var onDragExited: (() -> Void)?
    public var onDragMoved: ((CGPoint) -> Void)?
    public var onDrop: (([URL], CGPoint) -> Bool)?

    public init(
        registry: ModuleRegistry,
        syntheticSize: CGSize = CGSize(width: 220, height: 32),
        appearance: NotchAppearance = NotchAppearance(),
        showsLiveContentWhenClosed: Bool = false
    ) {
        self.registry = registry
        self.syntheticSize = syntheticSize
        self.appearance = appearance
        self.showsLiveContentWhenClosed = showsLiveContentWhenClosed
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    // The observer token is not `Sendable`, so a nonisolated `deinit` may not
    // touch it. `isolated deinit` runs the teardown on the main actor instead.
    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var allSurfaces: [NotchSurface] { Array(surfaces.values) }

    /// The surface whose hover rect contains the given global point, if any.
    public func surface(containing point: CGPoint) -> NotchSurface? {
        surfaces.values.first { $0.hoverRect.contains(point) }
    }

    public func apply(mode: NotchMode, drop: PeekPayload? = nil) {
        self.mode = mode
        self.drop = drop
        for surface in surfaces.values {
            surface.update(mode: mode)
            surface.update(drop: drop)
        }
    }

    private func rebuild() {
        let live = Set(NSScreen.screens.compactMap(\.displayID))

        for (id, surface) in surfaces where !live.contains(id) {
            surface.close()
            surfaces[id] = nil
        }

        for screen in NSScreen.screens {
            guard let id = screen.displayID else {
                logger.error("skipping a screen with no display ID; it will have no notch")
                continue
            }
            if let existing = surfaces[id] {
                existing.update(screen: screen, syntheticSize: syntheticSize)
                existing.update(appearance: appearance)
            } else {
                let surface = NotchSurface(
                    screen: screen,
                    displayID: id,
                    registry: registry,
                    syntheticSize: syntheticSize,
                    appearance: appearance
                )
                surface.onDragEntered = { [weak self] in self?.onDragEntered?() }
                surface.onDragExited = { [weak self] in self?.onDragExited?() }
                surface.onDragMoved = { [weak self] point in self?.onDragMoved?(point) }
                surface.onDrop = { [weak self] urls, point in self?.onDrop?(urls, point) ?? false }
                surfaces[id] = surface
            }
        }

        for surface in surfaces.values {
            surface.update(mode: mode)
            surface.update(drop: drop)
            surface.update(showsLiveContentWhenClosed: showsLiveContentWhenClosed)
        }

        logger.notice("rebuilt \(self.surfaces.count, privacy: .public) notch surfaces")
    }
}
