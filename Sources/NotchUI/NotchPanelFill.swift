import CoreGraphics
import NotchCore

public struct PanelFillStop: Equatable, Sendable {
    public var tint: NotchTint
    public var location: Double

    public init(tint: NotchTint, location: Double) {
        self.tint = tint
        self.location = location
    }
}

/// The stops the expanded panel is painted with.
///
/// The panel's top edge lies over the camera housing, and the housing has to stay
/// invisible: colour that starts above the bottom of it draws an outline around
/// the notch instead of hiding it. So black is held flat across that band and the
/// fade to the tint happens entirely below it.
public enum NotchPanelFill {
    /// The hold can never reach the bottom edge, or there is nothing left to fade
    /// through and the panel turns into two flat bands with a hard seam.
    public static let holdCeiling = 0.95

    public static func stops(tint: NotchTint?, strength: Double, hold: Double) -> [PanelFillStop] {
        let strength = min(max(strength, 0), 1)
        guard let tint, strength > 0 else {
            return [
                PanelFillStop(tint: .black, location: 0),
                PanelFillStop(tint: .black, location: 1)
            ]
        }

        let hold = min(max(hold, 0), holdCeiling)
        let bottom = PanelFillStop(tint: tint.scaled(by: strength), location: 1)
        guard hold > 0 else {
            return [PanelFillStop(tint: .black, location: 0), bottom]
        }
        return [
            PanelFillStop(tint: .black, location: 0),
            PanelFillStop(tint: .black, location: hold),
            bottom
        ]
    }
}
