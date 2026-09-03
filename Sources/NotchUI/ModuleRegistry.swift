import NotchCore
import Observation
import SwiftUI

/// Owns the app's modules, honours the user's layout, and tracks which tab is
/// showing. Shared across every screen surface, so all displays agree.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var layout: ModuleLayout
    public private(set) var selection: ModuleID?

    private var modules: [ModuleID: any NotchModule] = [:]
    private var activated: ModuleID?
    private var panelVisible = false

    public init(layout: ModuleLayout = ModuleLayout()) {
        self.layout = layout
    }

    public func register(_ module: any NotchModule) {
        precondition(modules[module.id] == nil, "module \(module.id.rawValue) registered twice")
        modules[module.id] = module
        layout.register(module.id)
        if selection == nil {
            selection = visibleModules.first?.id
        }
    }

    public var visibleModules: [any NotchModule] {
        layout.enabledOrder.compactMap { modules[$0] }
    }

    public func module(_ id: ModuleID) -> (any NotchModule)? {
        modules[id]
    }

    public var selectedModule: (any NotchModule)? {
        if let selection, let module = modules[selection] {
            return module
        }
        return visibleModules.first
    }

    public func select(_ id: ModuleID) {
        guard modules[id] != nil, !layout.disabled.contains(id) else { return }
        selection = id
        reconcileActivation()
    }

    /// Activates the selected module and deactivates whichever was active before,
    /// so exactly one module holds live resources at a time — whether the change
    /// came from the panel opening or from the user switching tabs while it is open.
    public func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        reconcileActivation()
    }

    private func reconcileActivation() {
        let wanted = panelVisible ? selection : nil
        guard wanted != activated else { return }

        if let activated, let module = modules[activated] {
            module.deactivate()
        }
        activated = wanted
        if let wanted, let module = modules[wanted] {
            module.activate()
        }
    }

    /// The first visible module's live content for the collapsed notch, if any.
    public var peekView: AnyView? {
        visibleModules.lazy.compactMap { $0.peekView() }.first
    }
}
