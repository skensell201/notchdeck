import Observation

/// The login item, owned by whoever owns `SMAppService`.
///
/// The settings window only shows a switch and whatever went wrong. Registration
/// can fail — most often because the app is running from a build directory
/// rather than `/Applications` — and when it does the General tab says so
/// instead of leaving a switch that silently does nothing.
@MainActor
public protocol LaunchAtLoginControlling: AnyObject, Observable {
    var isEnabled: Bool { get set }
    /// Non-nil when the last change did not take. Shown verbatim.
    var failureDescription: String? { get }
}

/// A `LaunchAtLoginControlling` made of closures, for wiring `SMAppService` in
/// one expression at the call site.
@MainActor
@Observable
public final class ClosureLaunchAtLogin: LaunchAtLoginControlling {
    private let read: () -> Bool
    private let write: (Bool) throws -> Void

    public private(set) var failureDescription: String?

    public init(read: @escaping () -> Bool, write: @escaping (Bool) throws -> Void) {
        self.read = read
        self.write = write
    }

    public var isEnabled: Bool {
        // Read through every time: the user can remove the login item in System
        // Settings while this window is open.
        get { read() }
        set {
            do {
                try write(newValue)
                failureDescription = nil
            } catch {
                failureDescription = error.localizedDescription
            }
        }
    }
}
