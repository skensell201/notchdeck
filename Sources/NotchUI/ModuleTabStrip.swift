import SwiftUI

public struct ModuleTabStrip: View {
    private let registry: ModuleRegistry
    private let modules: [any NotchModule]

    public init(registry: ModuleRegistry, modules: [any NotchModule]) {
        self.registry = registry
        self.modules = modules
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(modules, id: \.id) { module in
                let isSelected = registry.selection == module.id
                Button {
                    registry.select(module.id)
                } label: {
                    Image(systemName: module.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(isSelected ? 0.18 : 0))
                        )
                        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
                }
                .buttonStyle(.plain)
                .help(module.title)
            }
        }
    }
}
