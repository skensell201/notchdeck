import AppKit

/// The panel spans the whole expanded area at all times so the notch can grow
/// without resizing the window. Only the part currently covered by the notch
/// surface should react to the mouse; everything else must fall through to the
/// app underneath.
public final class NotchContainerView: NSView {
    /// The interactive area in this view's coordinate space (origin top-left,
    /// y down — this view is flipped). Assigned on every animation frame, so the
    /// guard keeps any work added here off the redundant path.
    public var interactiveRect: NSRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// The app is an accessory and this panel can never become key, so every
    /// click is a "first click". Without this, AppKit swallows all of them as
    /// activation clicks and `mouseDown` never arrives.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override var isFlipped: Bool { true }
}
