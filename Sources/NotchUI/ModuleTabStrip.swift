import SwiftUI

public struct ModuleTabStrip: View {
    private let registry: ModuleRegistry

    public init(registry: ModuleRegistry) {
        self.registry = registry
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(registry.visibleModules, id: \.id) { module in
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
