import AppKit

/// The panel spans the whole expanded area at all times so the notch can grow
/// without resizing the window. Only the part currently covered by the notch
/// surface should react to the mouse; everything else must fall through to the
/// app underneath.
public final class NotchContainerView: NSView {
    /// The interactive area in this view's coordinate space.
    public var interactiveRect: NSRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    public override var isFlipped: Bool { true }
}
