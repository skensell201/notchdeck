import CoreGraphics

/// An AppKit-free snapshot of everything the resolver needs to know about a screen.
public struct ScreenDescription: Equatable, Sendable {
    public var frame: CGRect
    public var topSafeAreaInset: CGFloat
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?
    /// Height of the menu bar band, `frame.maxY - visibleFrame.maxY`. On a notched
    /// display the camera housing is as tall as the menu bar, and that can be a
    /// point taller than `topSafeAreaInset` reports — measured 33 against 32 on a
    /// 14-inch MacBook Pro — which leaves a visible sliver of housing below a
    /// surface sized from the inset alone. Zero when the menu bar is hidden.
    public var menuBarHeight: CGFloat

    public init(
        frame: CGRect,
        topSafeAreaInset: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        menuBarHeight: CGFloat = 0
    ) {
        self.frame = frame
        self.topSafeAreaInset = topSafeAreaInset
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.menuBarHeight = menuBarHeight
    }
}
