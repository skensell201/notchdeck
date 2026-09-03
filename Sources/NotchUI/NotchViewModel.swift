import CoreGraphics
import NotchCore
import Observation

@MainActor
@Observable
public final class NotchViewModel {
    /// Geometry of the notch on this screen, in global screen coordinates.
    public var metrics: NotchMetrics
    public var mode: NotchMode = .closed

    /// Size of the fully expanded panel content.
    public let openSize: CGSize
    /// Extra width added on each side while peeking.
    public let peekSideWidth: CGFloat
    /// How far the collapsed surface extends past the notch on each side, so the
    /// concave top corners are visible against the menu bar instead of hiding
    /// behind the opaque camera housing.
    public let closedFlare: CGFloat
    /// How the shell is painted. Layout never reads this except to reserve room
    /// for the bloom.
    public let appearance: NotchAppearance

    public init(
        metrics: NotchMetrics,
        openSize: CGSize = CGSize(width: 620, height: 200),
        peekSideWidth: CGFloat = 140,
        closedFlare: CGFloat = 8,
        appearance: NotchAppearance = NotchAppearance()
    ) {
        self.metrics = metrics
        self.openSize = openSize
        self.peekSideWidth = peekSideWidth
        self.closedFlare = closedFlare
        self.appearance = appearance
    }

    /// The size the peek band settles at. Content is laid out at this size for the
    /// whole animation so it never reflows while the panel is in flight.
    public var peekSize: CGSize {
        CGSize(width: metrics.rect.width + peekSideWidth * 2, height: metrics.rect.height)
    }

    public var targetSize: CGSize {
        switch mode {
        case .closed:
            CGSize(width: metrics.rect.width + closedFlare * 2, height: metrics.rect.height)
        case .peek:
            CGSize(width: metrics.rect.width + peekSideWidth * 2, height: metrics.rect.height)
        case .open, .pinned:
            openSize
        }
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
            height: max(openSize.height, metrics.rect.height) + appearance.bloomMargin
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
