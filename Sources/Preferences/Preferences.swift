import CoreGraphics
import Foundation
import NotchCore
import Observation
import Support

/// Everything the user can change, over `UserDefaults`.
///
/// The values are held in memory and written through on change, rather than read
/// from `UserDefaults` on every access. That is not an optimisation: `@Observable`
/// instruments stored properties, so a computed property over `UserDefaults` is
/// invisible to SwiftUI — a control bound to one moves, writes, and never sees its
/// own label update.
///
/// Every default matches the constant it replaced, so an install that never opens
/// the settings window behaves exactly as it did before there was one. Values that
/// can be set to something unusable are clamped on the way in.
@MainActor
@Observable
public final class Preferences {
    public enum Key {
        public static let moduleLayout = "ModuleLayout"
        public static let syntheticNotchWidth = "SyntheticNotchWidth"
        public static let syntheticNotchHeight = "SyntheticNotchHeight"
        public static let hoverDwellMilliseconds = "HoverDwellMilliseconds"
        public static let exitGraceMilliseconds = "ExitGraceMilliseconds"
        public static let suppressVolumeHUD = "SuppressSystemVolumeHUD"
        public static let dismissWithEscape = "DismissWithEscape"
        public static let notchTintRed = "NotchTintRed"
        public static let notchTintGreen = "NotchTintGreen"
        public static let notchTintBlue = "NotchTintBlue"
        public static let notchTintStrength = "NotchTintStrength"
        public static let clipboardCapacity = "ClipboardCapacity"
        public static let clipboardExclusions = "ClipboardExcludedBundleIdentifiers"
    }

    /// The ranges the setters clamp to, published so a slider's track ends where
    /// the value actually stops. A control that runs past its own limit is a lie.
    public enum Range {
        public static let hoverDwellMilliseconds = 60...1000
        public static let exitGraceMilliseconds = 0...2000
        public static let syntheticNotchWidth = 120.0...600.0
        public static let syntheticNotchHeight = 20.0...60.0
        public static let notchTintStrength = 0.0...1.0
        public static let clipboardCapacity = 5...500
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Log.make("preferences")

    private var storedLayout: ModuleLayout
    private var storedNotchWidth: Double
    private var storedNotchHeight: Double
    private var storedTint: NotchTint?
    private var storedTintStrength: Double
    private var storedHoverDwell: Int
    private var storedExitGrace: Int
    private var storedSuppressVolumeHUD: Bool
    private var storedDismissWithEscape: Bool
    private var storedClipboardCapacity: Int
    private var storedClipboardExclusions: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.moduleLayout) {
            do {
                storedLayout = try JSONDecoder().decode(ModuleLayout.self, from: data)
            } catch {
                Log.make("preferences").error(
                    "discarding an unreadable module layout: \(error.localizedDescription, privacy: .public)"
                )
                storedLayout = ModuleLayout()
            }
        } else {
            storedLayout = ModuleLayout()
        }

        storedNotchWidth = Self.clamp(defaults.object(forKey: Key.syntheticNotchWidth) as? Double ?? 220, Range.syntheticNotchWidth)
        storedNotchHeight = Self.clamp(defaults.object(forKey: Key.syntheticNotchHeight) as? Double ?? 32, Range.syntheticNotchHeight)
        // All three components or none: a half-written tint is not a colour, and
        // reading one back as black would silently repaint the panel.
        if let red = defaults.object(forKey: Key.notchTintRed) as? Double,
           let green = defaults.object(forKey: Key.notchTintGreen) as? Double,
           let blue = defaults.object(forKey: Key.notchTintBlue) as? Double {
            storedTint = NotchTint(red: red, green: green, blue: blue)
        } else {
            storedTint = nil
        }
        storedTintStrength = Self.clamp(
            defaults.object(forKey: Key.notchTintStrength) as? Double ?? 0.7,
            Range.notchTintStrength
        )
        storedHoverDwell = Self.clamp(defaults.object(forKey: Key.hoverDwellMilliseconds) as? Int ?? 180, Range.hoverDwellMilliseconds)
        storedExitGrace = Self.clamp(defaults.object(forKey: Key.exitGraceMilliseconds) as? Int ?? 220, Range.exitGraceMilliseconds)
        storedSuppressVolumeHUD = defaults.bool(forKey: Key.suppressVolumeHUD)
        storedDismissWithEscape = defaults.bool(forKey: Key.dismissWithEscape)
        storedClipboardCapacity = Self.clamp(defaults.object(forKey: Key.clipboardCapacity) as? Int ?? 60, Range.clipboardCapacity)
        storedClipboardExclusions = defaults.stringArray(forKey: Key.clipboardExclusions) ?? []
    }

    // MARK: Modules

    public var moduleLayout: ModuleLayout {
        get { storedLayout }
        set {
            storedLayout = newValue
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.moduleLayout)
        }
    }

    // MARK: Notch

    public var syntheticNotchSize: CGSize {
        get { CGSize(width: storedNotchWidth, height: storedNotchHeight) }
        set {
            storedNotchWidth = Self.clamp(newValue.width, Range.syntheticNotchWidth)
            storedNotchHeight = Self.clamp(newValue.height, Range.syntheticNotchHeight)
            defaults.set(storedNotchWidth, forKey: Key.syntheticNotchWidth)
            defaults.set(storedNotchHeight, forKey: Key.syntheticNotchHeight)
        }
    }

    /// The colour the expanded panel fades to below the camera housing, or nil for
    /// the flat black the shell had before this existed. Off by default: a tint is
    /// something the user goes and asks for.
    public var notchTint: NotchTint? {
        get { storedTint }
        set {
            storedTint = newValue
            guard let newValue else {
                defaults.removeObject(forKey: Key.notchTintRed)
                defaults.removeObject(forKey: Key.notchTintGreen)
                defaults.removeObject(forKey: Key.notchTintBlue)
                return
            }
            defaults.set(newValue.red, forKey: Key.notchTintRed)
            defaults.set(newValue.green, forKey: Key.notchTintGreen)
            defaults.set(newValue.blue, forKey: Key.notchTintBlue)
        }
    }

    public var notchTintStrength: Double {
        get { storedTintStrength }
        set {
            storedTintStrength = Self.clamp(newValue, Range.notchTintStrength)
            defaults.set(storedTintStrength, forKey: Key.notchTintStrength)
        }
    }

    public var timing: NotchTiming {
        NotchTiming(
            hoverDwell: .milliseconds(storedHoverDwell),
            exitGrace: .milliseconds(storedExitGrace)
        )
    }

    /// A dwell of zero opens the notch on any pointer that crosses it; anything
    /// beyond a second feels broken. Both ends are worth refusing.
    public var hoverDwellMilliseconds: Int {
        get { storedHoverDwell }
        set {
            storedHoverDwell = Self.clamp(newValue, Range.hoverDwellMilliseconds)
            defaults.set(storedHoverDwell, forKey: Key.hoverDwellMilliseconds)
        }
    }

    public var exitGraceMilliseconds: Int {
        get { storedExitGrace }
        set {
            storedExitGrace = Self.clamp(newValue, Range.exitGraceMilliseconds)
            defaults.set(storedExitGrace, forKey: Key.exitGraceMilliseconds)
        }
    }

    // MARK: Behaviour

    public var suppressVolumeHUD: Bool {
        get { storedSuppressVolumeHUD }
        set {
            storedSuppressVolumeHUD = newValue
            defaults.set(newValue, forKey: Key.suppressVolumeHUD)
        }
    }

    public var dismissWithEscape: Bool {
        get { storedDismissWithEscape }
        set {
            storedDismissWithEscape = newValue
            defaults.set(newValue, forKey: Key.dismissWithEscape)
        }
    }

    // MARK: Clipboard

    public var clipboardCapacity: Int {
        get { storedClipboardCapacity }
        set {
            storedClipboardCapacity = Self.clamp(newValue, Range.clipboardCapacity)
            defaults.set(storedClipboardCapacity, forKey: Key.clipboardCapacity)
        }
    }

    public var clipboardExclusions: [String] {
        get { storedClipboardExclusions }
        set {
            storedClipboardExclusions = newValue
            defaults.set(newValue, forKey: Key.clipboardExclusions)
        }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
