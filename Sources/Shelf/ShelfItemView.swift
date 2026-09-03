import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItemView: View {
    let item: ShelfItem
    let url: URL?
    let onReveal: () -> Void
    let onQuickLook: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        tile
            .contextMenu {
                Button("Reveal in Finder", action: onReveal).disabled(!item.isAvailable)
                Button("Quick Look", action: onQuickLook).disabled(!item.isAvailable)
                Button("Copy", action: onCopy).disabled(!item.isAvailable)
                Divider()
                Button("Remove from Shelf", role: .destructive, action: onRemove)
            }
            .help(item.isAvailable ? item.resolvedPath : "\(item.name) — missing")
    }

    @ViewBuilder
    private var tile: some View {
        if let url, item.isAvailable {
            // Hands the real file URL to the destination: Finder copies it, an app
            // opens it. No file promise is needed because the file already exists.
            base.onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider()
            } preview: {
                icon.frame(width: 44, height: 44)
            }
        } else {
            base
        }
    }

    private var base: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 40, height: 40)
                .opacity(item.isAvailable ? 1 : 0.35)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(item.isAvailable ? 0.9 : 0.4))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06))
        )
    }

    private var icon: some View {
        let image: NSImage = if let url, item.isAvailable {
            NSWorkspace.shared.icon(forFile: url.path)
        } else {
            NSWorkspace.shared.icon(for: .data)
        }
        return Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
    }
}
