import CoreGraphics

/// An AppKit-free snapshot of everything the resolver needs to know about a screen.
public struct ScreenDescription: Equatable, Sendable {
    public var frame: CGRect
    public var topSafeAreaInset: CGFloat
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?

    public init(
        frame: CGRect,
        topSafeAreaInset: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        self.frame = frame
        self.topSafeAreaInset = topSafeAreaInset
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }
}
