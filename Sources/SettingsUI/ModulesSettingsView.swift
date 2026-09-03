import NotchCore
import SwiftUI

/// Every module this build has, in the order the notch will show them, with a
/// checkbox and a drag handle.
struct ModulesSettingsView: View {
    let model: ModulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(model.rows) { row in
                    HStack(spacing: 8) {
                        Toggle(isOn: enabled(row.id)) {
                            Label(row.title, systemImage: row.symbolName)
                        }
                        .toggleStyle(.checkbox)
                        Spacer(minLength: 0)
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                }
            }
            .alternatingRowBackgrounds()

            Divider()

            Text(footnote)
                .font(.callout)
                .foregroundStyle(model.everythingIsDisabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footnote: String {
        // Turning everything off is allowed. Saying what that does beats a
        // checkbox that refuses to move and does not explain itself.
        if model.everythingIsDisabled {
            "Every module is off. The notch still opens and still announces volume and power, but the panel has nothing to show until you switch one back on."
        } else {
            "Drag to reorder. The notch opens on the first enabled module."
        }
    }

    private func enabled(_ id: ModuleID) -> Binding<Bool> {
        Binding(
            get: { model.rows.first { $0.id == id }?.isEnabled ?? false },
            set: { model.setEnabled($0, for: id) }
        )
    }
}
