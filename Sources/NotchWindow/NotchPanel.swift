import AppKit

/// A borderless, non-activating panel that floats above the menu bar on every
/// Space and stays put when the user switches desktops.
///
/// This panel is deliberately never key and never main: it is a click-only
/// overlay for an accessory app, and `.nonactivatingPanel` earns its place by
/// keeping a click on the notch from activating the app. The consequence is that
/// nothing arrives through the responder chain except mouse clicks routed by
/// `NotchContainerView`. Pointer movement, scrolling and keyboard input must all
/// come from global `NSEvent` monitors instead — and global keyboard monitoring
/// additionally requires Accessibility permission, which is deferred to a later
/// phase.
public final class NotchPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
