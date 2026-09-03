import AppKit

/// The panel spans the whole expanded area at all times so the notch can grow
/// without resizing the window. Only the part currently covered by the notch
/// surface should react to the mouse; everything else must fall through to the
/// app underneath.
public final class NotchContainerView: NSView {
    /// The interactive area in this view's coordinate space (origin top-left,
    /// y down — this view is flipped). Assigned on every animation frame.
    public var interactiveRect: NSRect = .zero

    /// Drag-and-drop, forwarded to whoever owns this surface. The container is
    /// the single drag destination for the notch: AppKit picks the deepest view
    /// registered for the dragged types, and a SwiftUI `.onDrop` inside the
    /// hosting view would win that contest and steal the enter/exit events the
    /// notch needs to open itself.
    public var onDragEntered: (() -> Void)?
    public var onDragExited: (() -> Void)?
    /// Receives the dropped file URLs and the drop location in this view's
    /// (flipped) coordinate space. Returns whether the drop was accepted.
    public var onDrop: (([URL], CGPoint) -> Bool)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
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

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.fileURLs(in: sender)?.isEmpty == false else { return [] }
        onDragEntered?()
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExited?()
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = Self.fileURLs(in: sender), !urls.isEmpty else { return false }
        let location = convert(sender.draggingLocation, from: nil)
        return onDrop?(urls, location) ?? false
    }

    private static func fileURLs(in info: any NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
