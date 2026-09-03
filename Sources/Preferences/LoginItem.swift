import Foundation
import ServiceManagement
import Support

/// Registers the app to start at login.
///
/// Registration genuinely fails in the common development case — an app run from
/// a build directory rather than `/Applications` — so the result is reported
/// rather than assumed, and the settings window says what happened instead of
/// leaving a switch that silently does nothing.
@MainActor
public struct LoginItem {
    private let logger = Log.make("login-item")

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the app ended up in the requested state.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled == enabled
        } catch {
            logger.error("could not \(enabled ? "register" : "unregister", privacy: .public) the login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Why the last attempt is likely to have failed, for the settings window.
    public var failureExplanation: String {
        "Launching at login needs NotchDeck to live in Applications. Move it there and try again."
    }
}
