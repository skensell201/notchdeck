import AppKit
import NotchCore
import NotchUI
import SwiftUI

/// One notch on one screen: the panel, its SwiftUI content, and the view model
/// that keeps the two in sync.
@MainActor
public final class NotchSurface {
    public let displayID: CGDirectDisplayID
    public let model: NotchViewModel

    private let panel: NotchPanel
    private let container: NotchContainerView

    /// Drag-and-drop from the container, forwarded to whoever owns this surface.
    /// The drop location is deliberately not forwarded yet.
    public var onDragEntered: (() -> Void)?
    public var onDragExited: (() -> Void)?
    public var onDragMoved: ((CGPoint) -> Void)?
    public var onDrop: (([URL], CGPoint) -> Bool)?

    public init(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        registry: ModuleRegistry,
        syntheticSize: CGSize,
        appearance: NotchAppearance = NotchAppearance()
    ) {
        self.displayID = displayID

        let metrics = NotchResolver.resolve(screen: screen.notchDescription, syntheticSize: syntheticSize)
        let model = NotchViewModel(registry: registry, metrics: metrics, appearance: appearance)
        self.model = model

        let maximum = model.maximumSize
        let frame = Self.panelFrame(metrics: metrics, maximum: maximum)

        panel = NotchPanel(contentRect: frame)
        container = NotchContainerView(frame: NSRect(origin: .zero, size: maximum))

        // Attach before the first layout pass, so the very first published frame
        // lands on the container. The hosting view fills the container, so the
        // presented rect is already in the container's flipped coordinate space —
        // no conversion, and the clickable area tracks the animation frame by frame.
        //
        // Captured weakly: `model` outlives `container` in the leak case (display
        // disconnect drops the surface but not the model's subscribers), so a
        // strong capture here would keep the container — and the hosting view and
        // `NotchShellView` it holds — alive forever via model -> closure -> container.
        model.onPresentedRectChange = { [weak container] rect in
            container?.interactiveRect = rect
        }

        // Forwarders rather than copies: the owner assigns its handlers after this
        // initialiser has returned, so the container must read them at call time.
        container.onDragEntered = { [weak self] in self?.onDragEntered?() }
        container.onDragExited = { [weak self] in self?.onDragExited?() }
        container.onDragMoved = { [weak self] point in self?.onDragMoved?(point) }
        container.onDrop = { [weak self] urls, point in self?.onDrop?(urls, point) ?? false }

        let hosting = NSHostingView(rootView: NotchShellView(model: model))
        // Without this, assigning the hosting view as a borderless panel's content
        // view resizes the panel down to the SwiftUI intrinsic size — a 620x200
        // panel silently becomes 100x20.
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
    }

    /// Global-coordinate rect the pointer must be inside to count as "on the notch".
    /// While collapsed this is the notch itself; while expanded it is the whole surface.
    ///
    /// This is the *target* geometry, not the animated one: hover deliberately does
    /// not chase the spring. Hit testing is the opposite — it follows the presented
    /// rect above, so clicks and visible pixels agree mid-transition.
    public var hoverRect: CGRect { model.surfaceRectInScreen }

    public func update(mode: NotchMode) {
        model.mode = mode
    }

    public func update(drop: PeekPayload?) {
        model.drop = drop
    }

    public func update(showsLiveContentWhenClosed: Bool) {
        model.showsLiveContentWhenClosed = showsLiveContentWhenClosed
    }

    /// Re-resolves this surface against its screen's current geometry. A display
    /// that stays connected can still change resolution, scale or arrangement, and
    /// `maximumSize` depends on the notch width, so the panel and container both
    /// have to be resized, not just repositioned.
    public func update(screen: NSScreen, syntheticSize: CGSize) {
        let metrics = NotchResolver.resolve(screen: screen.notchDescription, syntheticSize: syntheticSize)
        guard metrics != model.metrics else { return }

        model.metrics = metrics
        let maximum = model.maximumSize
        panel.setFrame(Self.panelFrame(metrics: metrics, maximum: maximum), display: true)
        container.frame = NSRect(origin: .zero, size: maximum)
    }

    /// Repaints without re-resolving. Nothing in the appearance changes
    /// `bloomMargin`, so the panel keeps the frame it already has.
    public func update(appearance: NotchAppearance) {
        guard appearance != model.appearance else { return }
        model.appearance = appearance
    }

    public func close() {
        // Torn down deterministically rather than relying on deallocation order:
        // once the panel is ordered out nothing should still be pushing frames
        // into a detached container.
        model.onPresentedRectChange = nil
        panel.orderOut(nil)
    }

    /// The panel always reserves the largest size any mode needs, anchored so its
    /// top edge sits on the screen's top edge and its centre lines up with the notch.
    private static func panelFrame(metrics: NotchMetrics, maximum: CGSize) -> NSRect {
        NSRect(
            x: metrics.rect.midX - maximum.width / 2,
            y: metrics.rect.maxY - maximum.height,
            width: maximum.width,
            height: maximum.height
        )
    }
}
