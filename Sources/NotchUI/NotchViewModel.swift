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

    public init(
        metrics: NotchMetrics,
        openSize: CGSize = CGSize(width: 620, height: 200),
        peekSideWidth: CGFloat = 140,
        closedFlare: CGFloat = 8
    ) {
        self.metrics = metrics
        self.openSize = openSize
        self.peekSideWidth = peekSideWidth
        self.closedFlare = closedFlare
    }

    /// The size the notch surface should currently occupy.
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
    public var maximumSize: CGSize {
        CGSize(
            width: max(
                openSize.width,
                metrics.rect.width + peekSideWidth * 2,
                metrics.rect.width + closedFlare * 2
            ),
            height: max(openSize.height, metrics.rect.height)
        )
    }

    /// The rect that should swallow mouse events, in global screen coordinates,
    /// origin bottom-left, y up.
    public var surfaceRectInScreen: CGRect {
        let size = targetSize
        return CGRect(
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
