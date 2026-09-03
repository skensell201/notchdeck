import CoreGraphics

/// Everything about how the notch shell is painted, in one place, so it can be
/// tuned without touching layout.
public struct NotchAppearance: Equatable, Sendable {
    /// A hairline along the shape's edge, catching light like a physical bevel.
    public var rimWidth: CGFloat
    public var rimOpacity: Double
    /// Where the rim reaches full strength, as a fraction of the shape's height.
    /// It starts at zero along the top edge so nothing ever draws a bright line
    /// across the menu bar.
    public var rimFadeEnd: Double

    /// How far the shadow is pushed down. Nothing is offset upwards: the top
    /// edge is flush with the screen and there is nowhere to bleed into.
    public var shadowOffset: CGFloat

    /// A dark drop shadow. This is what separates the panel on a light wallpaper,
    /// where a white glow is invisible.
    public var shadowRadius: CGFloat
    public var shadowOpacity: Double

    /// Room the panel reserves around the shape so the shadow is not clipped at the
    /// window edge. Nothing is reserved above the shape: its top edge is flush with
    /// the screen and there is nowhere to bleed into.
    public var bloomMargin: CGFloat {
        (shadowRadius + shadowOffset) * 2
    }

    public init(
        rimWidth: CGFloat = 1,
        rimOpacity: Double = 0.22,
        rimFadeEnd: Double = 0.45,
        shadowOffset: CGFloat = 5,
        shadowRadius: CGFloat = 18,
        shadowOpacity: Double = 0.45
    ) {
        self.rimWidth = rimWidth
        self.rimOpacity = rimOpacity
        self.rimFadeEnd = rimFadeEnd
        self.shadowOffset = shadowOffset
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }
}
