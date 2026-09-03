import Foundation
import NotchCore
import Observation

/// A module this build knows how to draw, as the Modules tab needs to describe it.
///
/// Deliberately not a `NotchModule`: the tab shows a name, a symbol and a
/// position, and taking only those keeps the list testable without standing up
/// eight real modules.
public struct SettingsModuleDescriptor: Equatable, Sendable {
    public let id: ModuleID
    public let title: String
    public let symbolName: String

    public init(id: ModuleID, title: String, symbolName: String) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
    }
}

/// One line of the Modules tab.
public struct SettingsModuleRow: Identifiable, Equatable, Sendable {
    public let id: ModuleID
    public let title: String
    public let symbolName: String
    public let isEnabled: Bool
    /// Position among the rows the user can see — not the index in the stored
    /// layout, which may carry modules this build does not have.
    public let position: Int
}

/// The Modules tab's logic: the stored layout plus the modules this build
/// registered, mapped to rows, reordered, and switched on and off.
///
/// A stored layout may name a module this build lacks — a newer build's module
/// after a downgrade. Such an identifier has no row, because there is nothing to
/// show, and every write here goes through `ModuleLayout`, which keeps it in
/// place. Dropping it would silently discard the position the user chose in the
/// build that has it.
@MainActor
@Observable
public final class ModulesViewModel {
    public private(set) var layout: ModuleLayout

    private let descriptors: [ModuleID: SettingsModuleDescriptor]
    private let commit: (ModuleLayout) -> Void

    public init(
        descriptors: [SettingsModuleDescriptor],
        layout: ModuleLayout,
        commit: @escaping (ModuleLayout) -> Void
    ) {
        var layout = layout
        // A module this build added since the layout was stored belongs at the
        // end, enabled — the same thing `ModuleRegistry` does at launch.
        for descriptor in descriptors {
            layout.register(descriptor.id)
        }
        self.layout = layout
        self.descriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        self.commit = commit
    }

    public var rows: [SettingsModuleRow] {
        knownOrder.enumerated().map { position, id in
            let descriptor = descriptors[id]!
            return SettingsModuleRow(
                id: id,
                title: descriptor.title,
                symbolName: descriptor.symbolName,
                isEnabled: !layout.disabled.contains(id),
                position: position
            )
        }
    }

    public var enabledCount: Int {
        knownOrder.count { !layout.disabled.contains($0) }
    }

    /// True when the user has switched everything off. Allowed on purpose: the
    /// tab says what the notch will do instead of refusing the last toggle.
    public var everythingIsDisabled: Bool {
        !rows.isEmpty && enabledCount == 0
    }

    public func setEnabled(_ enabled: Bool, for id: ModuleID) {
        guard descriptors[id] != nil else { return }
        var updated = layout
        updated.setEnabled(enabled, for: id)
        apply(updated)
    }

    /// Moves a module to a position among the visible rows. Out-of-range
    /// destinations clamp to the ends rather than being refused, because a drag
    /// past the last row means the last row.
    public func move(_ id: ModuleID, toRow destination: Int) {
        guard descriptors[id] != nil, layout.order.contains(id) else { return }

        let remaining = layout.order.filter { $0 != id }
        // Positions in the stored layout of the rows that will surround the
        // moved module, so unknown identifiers keep the neighbours they had.
        let knownIndices = remaining.indices.filter { descriptors[remaining[$0]] != nil }
        let clamped = min(max(destination, 0), knownIndices.count)
        // Past the last row lands after any trailing unknown identifiers, which
        // keeps them stored without giving them a position they cannot show.
        let index = clamped < knownIndices.count ? knownIndices[clamped] : remaining.count

        var updated = layout
        updated.move(id, to: index)
        apply(updated)
    }

    /// The shape `List`'s `onMove` hands over: source offsets and a destination
    /// measured before the move happens.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let rows = rows
        guard let from = source.first, source.count == 1, rows.indices.contains(from) else { return }
        move(rows[from].id, toRow: destination > from ? destination - 1 : destination)
    }

    private var knownOrder: [ModuleID] {
        layout.order.filter { descriptors[$0] != nil }
    }

    private func apply(_ updated: ModuleLayout) {
        guard updated != layout else { return }
        layout = updated
        commit(updated)
    }
}
