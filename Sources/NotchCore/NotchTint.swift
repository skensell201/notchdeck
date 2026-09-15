import CoreGraphics

/// A colour the expanded panel fades to, held as components rather than as a
/// `Color`, so it survives a round trip through `UserDefaults` and can be compared
/// in a test without a rendering context.
public struct NotchTint: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = NotchTint(red: 0, green: 0, blue: 0)

    /// Towards black, never past the colour: a strength of one is the tint itself.
    public func scaled(by factor: Double) -> NotchTint {
        NotchTint(red: red * factor, green: green * factor, blue: blue * factor)
    }
}
