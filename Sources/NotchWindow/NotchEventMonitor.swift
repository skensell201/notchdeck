import AppKit
import NotchCore

/// Translates raw `NSEvent`s into `NotchEvent`s for the controller.
@MainActor
public final class NotchEventMonitor {
    private let surfaces: NotchSurfaceManager
    private let send: (NotchEvent) -> Void
    private let onHorizontalSwipe: (ScrollDirection) -> Void

    private var accumulator = ScrollAccumulator()
    private var pointerIsInside = false
    private var monitors: [Any] = []

    public init(
        surfaces: NotchSurfaceManager,
        send: @escaping (NotchEvent) -> Void,
        onHorizontalSwipe: @escaping (ScrollDirection) -> Void
    ) {
        self.surfaces = surfaces
        self.send = send
        self.onHorizontalSwipe = onHorizontalSwipe
    }

    public func start() {
        add(mask: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.handlePointerMove(at: NSEvent.mouseLocation)
        }
        add(mask: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event)
        }
        add(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
    }

    public func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    private func add(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Reconciles the pointer flag with where the pointer actually is, emitting the
    /// enter or exit the reducer has not seen yet. Idempotent: a move that does not
    /// cross the boundary sends nothing.
    private func handlePointerMove(at location: CGPoint) {
        let inside = surfaces.surface(containing: location) != nil
        guard inside != pointerIsInside else { return }
        pointerIsInside = inside
        send(inside ? .pointerEntered : .pointerExited)
    }

    private func handleScroll(_ event: NSEvent) {
        // The reducer opens on a scroll but only arms the exit-grace timer from
        // `.pointerExited`, which it ignores unless it has seen `.pointerEntered`.
        // The pointer can reach the notch without a `.mouseMoved` we saw — another
        // app warping the cursor, a display reconfiguration sliding a surface under
        // a stationary pointer, our monitors starting with the pointer already on
        // the notch — so resolve the truth here rather than trusting the last move.
        handlePointerMove(at: NSEvent.mouseLocation)

        guard surfaces.surface(containing: NSEvent.mouseLocation) != nil else { return }

        // Momentum first: during the inertial tail `phase` is empty, so testing it
        // first would misread the tail as a fresh `.changed` delta and fire twice.
        let phase: ScrollPhase =
            if !event.momentumPhase.isEmpty { .momentum }
            else if event.phase.contains(.began) { .began }
            else if event.phase.contains(.ended) || event.phase.contains(.cancelled) { .ended }
            else if event.phase.isEmpty { .discrete }
            else { .changed }

        guard let direction = accumulator.consume(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: phase,
            timestamp: event.timestamp
        ) else { return }

        switch direction {
        case .down, .up:
            send(.scrolled(direction))
        case .left, .right:
            // Track changes are the media module's business; the notch state
            // machine has nothing to say about them.
            onHorizontalSwipe(direction)
        }
    }

    private func handleClick(at location: CGPoint) {
        // Same reason as in `handleScroll`: a click may be the first event that
        // tells us where the pointer is, and `.clicked` opens without arming the
        // timer that eventually closes the notch again.
        handlePointerMove(at: location)

        if surfaces.surface(containing: location) != nil {
            send(.clicked)
        } else {
            send(.clickedOutside)
        }
    }
}
