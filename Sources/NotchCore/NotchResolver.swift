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
            let rect = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.topSafeAreaInset,
                width: right.minX - left.maxX,
                height: screen.topSafeAreaInset
            )
            return NotchMetrics(rect: rect, kind: .physical)
        }

        let rect = CGRect(
            x: screen.frame.midX - syntheticSize.width / 2,
            y: screen.frame.maxY - syntheticSize.height,
            width: syntheticSize.width,
            height: syntheticSize.height
        )
        return NotchMetrics(rect: rect, kind: .synthetic)
    }
}
