import NotchCore
import SwiftUI

/// A self-contained feature that contributes views to the notch.
///
/// A module is an app-level singleton: its state is shared, and its views are
/// instantiated once per screen surface. State must therefore live on the module
/// (observable), never in a view.
@MainActor
public protocol NotchModule: AnyObject {
    static var id: ModuleID { get }

    var title: String { get }
    var symbolName: String { get }

    /// Called when the module becomes visible and when it is hidden.
    ///
    /// `deactivate` must release everything that only the open panel needed —
    /// timers, pollers, capture sessions. A module that feeds `peekView()` keeps
    /// that one source running, because the collapsed notch still shows it; the
    /// media module is the example, and it stops only its redraw tick.
    func activate()
    func deactivate()

    func expandedView() -> AnyView

    /// A compact representation for the collapsed notch, or nil when the module
    /// has nothing live to show.
    func peekView() -> AnyView?
}

public extension NotchModule {
    var id: ModuleID { Self.id }
}
