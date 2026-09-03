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

    /// Adopts a layout the user edited — a stored one at launch, or the settings
    /// window's while running.
    ///
    /// Identifiers the registry does not know are kept exactly as given: the
    /// layout is persisted, and a build that lacks a module must not discard the
    /// position it holds in the build that has it. If the selected module has
    /// just been switched off, selection falls to the first module still
    /// showing, so the panel never opens on a tab that is no longer there.
    public func apply(_ layout: ModuleLayout) {
        self.layout = layout
        // A selection that is still showing is kept, so reordering does not move
        // the user off the tab they were looking at.
        let stillShowing = selection.map { modules[$0] != nil && !layout.disabled.contains($0) } ?? false
        if !stillShowing {
            selection = visibleModules.first?.id
        }
        reconcileActivation()
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

    /// Whether any visible module has content for the collapsed notch. Drives
    /// the collapsed notch's width, so it is read on every layout pass.
    public var hasLiveContent: Bool {
        visibleModules.contains { $0.hasLiveContent }
    }
}
