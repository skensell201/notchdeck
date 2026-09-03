import Foundation
import Support

/// Keeps the system volume overlay suppressed while the preference is on.
///
/// `OSDUIHelper` respawns, so this re-checks on a timer rather than acting once.
/// The preference is off by default: suppression is an undocumented trick, and
/// the honest failure mode after a macOS update is two overlays rather than a
/// broken app.
@MainActor
public final class SystemHUDController {
    public static let preferenceKey = "SuppressSystemVolumeHUD"

    private let suppressor: OSDSuppressor
    private let defaults: UserDefaults
    private let interval: Duration
    private let logger = Log.make("system-hud")
    private var task: Task<Void, Never>?

    public init(
        suppressor: OSDSuppressor = OSDSuppressor(),
        defaults: UserDefaults = .standard,
        interval: Duration = .seconds(2)
    ) {
        self.suppressor = suppressor
        self.defaults = defaults
        self.interval = interval
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.preferenceKey) }
        set {
            defaults.set(newValue, forKey: Self.preferenceKey)
            applyPreference()
        }
    }

    public func applyPreference() {
        isEnabled ? start() : stop()
    }

    private func start() {
        guard task == nil else { return }
        logger.notice("suppressing the system volume overlay")
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.suppressor.enforce()
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
            }
        }
    }

    private func stop() {
        guard task != nil else { return }
        task?.cancel()
        task = nil
        suppressor.restore()
        logger.notice("restored the system volume overlay")
    }

    /// Called from `applicationWillTerminate`; safe when suppression was never on.
    public func restore() {
        task?.cancel()
        task = nil
        suppressor.restore()
    }
}
