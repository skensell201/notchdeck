import CoreGraphics
import NotchCore
import Observation

@MainActor
@Observable
public final class NotchViewModel {
    /// The modules available in the expanded panel, shared across every surface.
    public let registry: ModuleRegistry

    /// Geometry of the notch on this screen, in global screen coordinates.
    public var metrics: NotchMetrics
    public var mode: NotchMode = .closed
    /// The announcement currently falling out of the notch, if any. Independent
    /// of `mode`: it hangs under a collapsed band and under an open panel alike.
    public var drop: PeekPayload?

    /// Size of the fully expanded panel content.
    public let openSize: CGSize
    /// Extra width added on each side while peeking.
    public let peekSideWidth: CGFloat
    /// How far the collapsed surface extends past the notch on each side, so the
    /// concave top corners are visible against the menu bar instead of hiding
    /// behind the opaque camera housing.
    public let closedFlare: CGFloat
    /// How the shell is painted. Layout never reads this except to reserve room
    /// for the bloom. Settable so the settings window can retint a running notch;
    /// nothing here changes `bloomMargin`, so the panel never has to be resized.
    public var appearance: NotchAppearance

    public init(
        registry: ModuleRegistry,
        metrics: NotchMetrics,
        openSize: CGSize = CGSize(width: 480, height: 150),
        peekSideWidth: CGFloat = 140,
        closedFlare: CGFloat = 8,
        appearance: NotchAppearance = NotchAppearance()
    ) {
        self.registry = registry
        self.metrics = metrics
        self.openSize = openSize
        self.peekSideWidth = peekSideWidth
        self.closedFlare = closedFlare
        self.appearance = appearance
    }

    /// The height `panelFillStops` are measured against, in points.
    ///
    /// Always the open panel, whatever mode the notch is in. The fill is laid out
    /// once at this height and the shape clips it, so collapsing the notch hides
    /// the lower part of the gradient rather than squeezing all of it into the
    /// band — which would put colour inside the camera housing, the one place it
    /// must never appear.
    public var panelFillHeight: CGFloat { openSize.height }

    /// The stops the expanded panel is filled with, top edge to bottom.
    ///
    /// The hold is measured rather than typed: it is exactly the fraction of the
    /// open panel that lies over the camera housing, so it follows a display with a
    /// taller notch and follows the Height slider on a synthetic one.
    public var panelFillStops: [PanelFillStop] {
        NotchPanelFill.stops(
            tint: appearance.tint,
            strength: appearance.tintStrength,
            hold: panelFillHeight > 0 ? metrics.rect.height / panelFillHeight : 0
        )
    }

    /// The size the peek band settles at. Content is laid out at this size for the
    /// whole animation so it never reflows while the panel is in flight.
    public var peekSize: CGSize {
        CGSize(width: metrics.rect.width + peekSideWidth * 2, height: metrics.rect.height)
    }

    /// The size the shape settles at for the current mode.
    ///
    /// A collapsed notch widens to `peekSize` while a module has live content —
    /// a playing track, say — without leaving `.closed`: `.peek` is the timed
    /// live-activity mode and would expire, whereas live content persists for as
    /// long as the module offers it. `surfaceRectInScreen` follows this, so the
    /// hover region grows with the band.
    public var targetSize: CGSize {
        switch mode {
        case .closed where registry.hasLiveContent:
            peekSize
        case .closed:
            closedSize
        case .peek:
            peekSize
        case .open, .pinned:
            openSize
        }
    }

    /// The collapsed band: the notch plus the flare that keeps its concave top
    /// corners clear of the camera housing.
    public var closedSize: CGSize {
        CGSize(width: metrics.rect.width + closedFlare * 2, height: metrics.rect.height)
    }

    /// The maximum size the hosting panel must reserve, regardless of mode.
    ///
    /// Larger than any shape the shell draws: the extra `bloomMargin` is the room
    /// the glow and shadow need, and without it they would be clipped flat against
    /// the window edge. Hover, hit testing and the presented rect all keep
    /// following the shape, never this.
    public var maximumSize: CGSize {
        CGSize(
            width: max(
                openSize.width,
                metrics.rect.width + peekSideWidth * 2,
                metrics.rect.width + closedFlare * 2
            ) + appearance.bloomMargin,
            height: max(
                openSize.height,
                metrics.rect.height,
                // A drop hangs below whatever shape is on screen — the open
                // panel included — and a window sized only to that shape would
                // clip the drop off at its edge.
                NotchDropGeometry.reach(bandHeight: max(openSize.height, metrics.rect.height))
            ) + appearance.bloomMargin
        )
    }

    /// The rect that counts as "the pointer is on the notch", in global screen
    /// coordinates, origin bottom-left, y up.
    ///
    /// This tracks the drawn shape, not the panel's reserved footprint: the panel
    /// always reserves the largest size any mode needs, and hovering that while
    /// collapsed would open the notch from most of the top of the screen, well
    /// outside anything the user can see.
    public var surfaceRectInScreen: CGRect {
        rectInScreen(size: targetSize)
    }

    /// Every notch rect shares an anchor: centred on the notch, top edge flush
    /// with the screen's top edge.
    private func rectInScreen(size: CGSize) -> CGRect {
        CGRect(
            x: metrics.rect.midX - size.width / 2,
            y: metrics.rect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The frame the shape is actually drawn at right now, in the hosting view's
    /// coordinate space (origin top-left, y down) — which is exactly the space
    /// `NotchContainerView`'s interactive rect expects, so no conversion is needed.
    ///
    /// Published by `NotchShellView` on every animation frame. Empty until the
    /// first layout pass.
    public var presentedRectInView: CGRect = .zero {
        didSet {
            guard presentedRectInView != oldValue else { return }
            onPresentedRectChange?(presentedRectInView)
        }
    }

    /// Set by the owning surface to forward the presented frame to its container view.
    public var onPresentedRectChange: ((CGRect) -> Void)?
}
