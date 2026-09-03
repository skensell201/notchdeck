import CoreGraphics
import Foundation
import NotchCore
import Observation
import Support

/// Everything the user can change, over `UserDefaults`.
///
/// Every default matches the constant it replaced, so an install that never opens
/// the settings window behaves exactly as it did before there was one. Writes
/// apply immediately: each of these is cheap to change and instantly visible, and
/// an Apply button would only add a state the user has to reason about.
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
        public static let clipboardCapacity = "ClipboardCapacity"
        public static let clipboardExclusions = "ClipboardExcludedBundleIdentifiers"
    }

    private let defaults: UserDefaults
    private let logger = Log.make("preferences")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Modules

    public var moduleLayout: ModuleLayout {
        get {
            guard let data = defaults.data(forKey: Key.moduleLayout) else { return ModuleLayout() }
            do {
                return try JSONDecoder().decode(ModuleLayout.self, from: data)
            } catch {
                logger.error("discarding an unreadable module layout: \(error.localizedDescription, privacy: .public)")
                return ModuleLayout()
            }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.moduleLayout)
        }
    }

    // MARK: Notch

    /// Clamped to something a notch can actually be: too small to hit, or wider
    /// than a display, are both worse than a default.
    public var syntheticNotchSize: CGSize {
        get {
            let width = defaults.object(forKey: Key.syntheticNotchWidth) as? Double ?? 220
            let height = defaults.object(forKey: Key.syntheticNotchHeight) as? Double ?? 32
            return CGSize(width: Self.clamp(width, 120, 600), height: Self.clamp(height, 20, 60))
        }
        set {
            defaults.set(Self.clamp(newValue.width, 120, 600), forKey: Key.syntheticNotchWidth)
            defaults.set(Self.clamp(newValue.height, 20, 60), forKey: Key.syntheticNotchHeight)
        }
    }

    public var timing: NotchTiming {
        NotchTiming(
            hoverDwell: .milliseconds(hoverDwellMilliseconds),
            exitGrace: .milliseconds(exitGraceMilliseconds)
        )
    }

    /// A dwell of zero opens the notch on any pointer that crosses it; anything
    /// beyond a second feels broken. Both ends are worth refusing.
    public var hoverDwellMilliseconds: Int {
        get { Int(Self.clamp(Double(defaults.object(forKey: Key.hoverDwellMilliseconds) as? Int ?? 180), 60, 1000)) }
        set { defaults.set(Int(Self.clamp(Double(newValue), 60, 1000)), forKey: Key.hoverDwellMilliseconds) }
    }

    public var exitGraceMilliseconds: Int {
        get { Int(Self.clamp(Double(defaults.object(forKey: Key.exitGraceMilliseconds) as? Int ?? 220), 0, 2000)) }
        set { defaults.set(Int(Self.clamp(Double(newValue), 0, 2000)), forKey: Key.exitGraceMilliseconds) }
    }

    // MARK: Behaviour

    public var suppressVolumeHUD: Bool {
        get { defaults.bool(forKey: Key.suppressVolumeHUD) }
        set { defaults.set(newValue, forKey: Key.suppressVolumeHUD) }
    }

    public var dismissWithEscape: Bool {
        get { defaults.bool(forKey: Key.dismissWithEscape) }
        set { defaults.set(newValue, forKey: Key.dismissWithEscape) }
    }

    // MARK: Clipboard

    public var clipboardCapacity: Int {
        get { Int(Self.clamp(Double(defaults.object(forKey: Key.clipboardCapacity) as? Int ?? 60), 5, 500)) }
        set { defaults.set(Int(Self.clamp(Double(newValue), 5, 500)), forKey: Key.clipboardCapacity) }
    }

    public var clipboardExclusions: [String] {
        get { defaults.stringArray(forKey: Key.clipboardExclusions) ?? [] }
        set { defaults.set(newValue, forKey: Key.clipboardExclusions) }
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
