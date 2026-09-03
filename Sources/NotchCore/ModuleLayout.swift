/// Which modules the panel shows, in what order, and which the user turned off.
///
/// The order deliberately keeps disabled modules in place so that re-enabling one
/// puts it back where the user left it. Unknown identifiers are preserved through
/// a round trip so that downgrading a build does not discard a newer module's
/// position.
public struct ModuleLayout: Equatable, Sendable, Codable {
    public private(set) var order: [ModuleID]
    public private(set) var disabled: Set<ModuleID>

    public init(order: [ModuleID] = [], disabled: Set<ModuleID> = []) {
        self.order = order
        self.disabled = disabled
    }

    public var enabledOrder: [ModuleID] {
        order.filter { !disabled.contains($0) }
    }

    public var defaultSelection: ModuleID? {
        enabledOrder.first
    }

    /// Adds a module the build knows about. Registering an already-known module
    /// leaves its position and enabled state untouched.
    public mutating func register(_ id: ModuleID) {
        guard !order.contains(id) else { return }
        order.append(id)
    }

    public mutating func move(_ id: ModuleID, to index: Int) {
        guard let current = order.firstIndex(of: id) else { return }
        order.remove(at: current)
        order.insert(id, at: min(max(index, 0), order.count))
    }

    public mutating func setEnabled(_ enabled: Bool, for id: ModuleID) {
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
    }
}
