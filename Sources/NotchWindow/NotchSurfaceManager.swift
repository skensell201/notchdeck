import AppKit
import NotchCore
import Support

/// Owns one `NotchSurface` per screen and rebuilds them when displays change.
@MainActor
public final class NotchSurfaceManager {
    private let logger = Log.make("surfaces")
    private let syntheticSize: CGSize
    private var surfaces: [CGDirectDisplayID: NotchSurface] = [:]
    private var observer: NSObjectProtocol?
    private var mode: NotchMode = .closed

    public init(syntheticSize: CGSize = CGSize(width: 220, height: 32)) {
        self.syntheticSize = syntheticSize
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

    public func apply(mode: NotchMode) {
        self.mode = mode
        for surface in surfaces.values {
            surface.update(mode: mode)
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
            } else {
                surfaces[id] = NotchSurface(screen: screen, displayID: id, syntheticSize: syntheticSize)
            }
        }

        for surface in surfaces.values {
            surface.update(mode: mode)
        }

        logger.notice("rebuilt \(self.surfaces.count, privacy: .public) notch surfaces")
    }
}
