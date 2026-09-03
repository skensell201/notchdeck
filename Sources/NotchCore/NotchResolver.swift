import CoreGraphics

public enum NotchKind: Equatable, Sendable {
    /// A real camera housing reported by the display.
    case physical
    /// A notch we draw ourselves because the display has none.
    case synthetic
}

public struct NotchMetrics: Equatable, Sendable {
    public var rect: CGRect
    public var kind: NotchKind

    public init(rect: CGRect, kind: NotchKind) {
        self.rect = rect
        self.kind = kind
    }
}

public enum NotchResolver {
    public static func resolve(screen: ScreenDescription, syntheticSize: CGSize) -> NotchMetrics {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.topSafeAreaInset > 0,
           right.minX > left.maxX {
            // Every edge comes from the auxiliary rects, which are self-consistent;
            // `topSafeAreaInset` is only the signal that a notch exists at all.
            // The housing is as tall as the menu bar, which can exceed the
            // auxiliary areas' height by a point; size to whichever is taller so
            // no sliver of housing shows beneath the surface.
            let height = max(left.height, screen.menuBarHeight)
            let rect = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - height,
                width: right.minX - left.maxX,
                height: height
            )
            return NotchMetrics(rect: rect, kind: .physical)
        }

        // Clamp to the display, and keep the origin integral so the rect stays
        // crisp on non-Retina externals.
        let width = min(syntheticSize.width, screen.frame.width)
        let height = min(syntheticSize.height, screen.frame.height)
        let rect = CGRect(
            x: (screen.frame.midX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        return NotchMetrics(rect: rect, kind: .synthetic)
    }
}
