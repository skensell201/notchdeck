import NotchCore
import Observation

/// Owns the app's modules, honours the user's layout, and tracks which tab is
/// showing. Shared across every screen surface, so all displays agree.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var layout: ModuleLayout
    public private(set) var selection: ModuleID?

    private var modules: [ModuleID: any NotchModule] = [:]
    private var activated: ModuleID?

    public init(layout: ModuleLayout = ModuleLayout()) {
        self.layout = layout
    }

    public func register(_ module: any NotchModule) {
        modules[module.id] = module
        layout.register(module.id)
        if selection == nil {
            selection = layout.defaultSelection
        }
    }

    public var visibleModules: [any NotchModule] {
        layout.enabledOrder.compactMap { modules[$0] }
    }

    public func module(_ id: ModuleID) -> (any NotchModule)? {
        modules[id]
    }

    public var selectedModule: (any NotchModule)? {
        guard let selection else { return nil }
        return modules[selection]
    }

    public func select(_ id: ModuleID) {
        guard modules[id] != nil, !layout.disabled.contains(id) else { return }
        selection = id
    }

    /// Activates the selected module and deactivates whichever was active before,
    /// so exactly one module holds live resources at a time.
    public func setPanelVisible(_ visible: Bool) {
        let wanted = visible ? selection : nil
        guard wanted != activated else { return }

        if let activated, let module = modules[activated] {
            module.deactivate()
        }
        activated = wanted
        if let wanted, let module = modules[wanted] {
            module.activate()
        }
    }

    /// The first visible module offering live content for the collapsed notch.
    public var peekProvider: (any NotchModule)? {
        visibleModules.first { $0.peekView() != nil }
    }
}
