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

    /// A soft bloom outside the shape, offset downwards for the same reason.
    public var glowRadius: CGFloat
    public var glowOpacity: Double
    public var glowOffset: CGFloat

    /// A dark drop shadow. This is what separates the panel on a light wallpaper,
    /// where a white glow is invisible.
    public var shadowRadius: CGFloat
    public var shadowOpacity: Double

    /// Room the panel reserves around the shape so the bloom is not clipped at the
    /// window edge. Nothing is reserved above the shape: its top edge is flush with
    /// the screen and there is nowhere to bleed into.
    public var bloomMargin: CGFloat {
        max(glowRadius + glowOffset, shadowRadius) * 2
    }

    public init(
        rimWidth: CGFloat = 1,
        rimOpacity: Double = 0.22,
        rimFadeEnd: Double = 0.45,
        glowRadius: CGFloat = 14,
        glowOpacity: Double = 0.10,
        glowOffset: CGFloat = 5,
        shadowRadius: CGFloat = 18,
        shadowOpacity: Double = 0.45
    ) {
        self.rimWidth = rimWidth
        self.rimOpacity = rimOpacity
        self.rimFadeEnd = rimFadeEnd
        self.glowRadius = glowRadius
        self.glowOpacity = glowOpacity
        self.glowOffset = glowOffset
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
    }
}
