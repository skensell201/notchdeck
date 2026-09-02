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

    public init(
        metrics: NotchMetrics,
        openSize: CGSize = CGSize(width: 620, height: 200),
        peekSideWidth: CGFloat = 140
    ) {
        self.metrics = metrics
        self.openSize = openSize
        self.peekSideWidth = peekSideWidth
    }

    /// The size the notch surface should currently occupy.
    public var targetSize: CGSize {
        switch mode {
        case .closed:
            metrics.rect.size
        case .peek:
            CGSize(width: metrics.rect.width + peekSideWidth * 2, height: metrics.rect.height)
        case .open, .pinned:
            openSize
        }
    }

    /// The maximum size the hosting panel must reserve, regardless of mode.
    public var maximumSize: CGSize {
        CGSize(
            width: max(openSize.width, metrics.rect.width + peekSideWidth * 2),
            height: max(openSize.height, metrics.rect.height)
        )
    }

    /// The rect that should swallow mouse events, in global screen coordinates.
    public var interactiveRect: CGRect {
        let size = targetSize
        return CGRect(
            x: metrics.rect.midX - size.width / 2,
            y: metrics.rect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
