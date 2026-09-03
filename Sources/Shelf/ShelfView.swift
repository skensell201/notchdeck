import SwiftUI

struct ShelfView: View {
    let module: ShelfModule

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if module.store.items.isEmpty {
                    empty
                } else {
                    items
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 4) {
                AirDropZone(module: module)
                if !module.store.items.isEmpty {
                    Button("Clear") { module.confirmClear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 78)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.35))
            Text("Drop files here to keep them handy")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var items: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(module.store.items) { item in
                    ShelfItemView(
                        item: item,
                        url: module.store.url(for: item),
                        onReveal: { module.reveal(item) },
                        onQuickLook: { module.quickLook(item) },
                        onCopy: { module.copy(item) },
                        onRemove: { module.store.remove(item.id) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
