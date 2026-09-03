import AppKit
import SwiftUI

struct ClipboardView: View {
    @Bindable var module: ClipboardModule

    var body: some View {
        VStack(spacing: 4) {
            search
            if module.visibleEntries.isEmpty {
                empty
            } else {
                list
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var search: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search", text: $module.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
            if !module.store.entries.isEmpty {
                Button("Clear") { module.store.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.07)))
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.3))
            Text(module.query.isEmpty ? "Copied items will appear here" : "Nothing matches")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                ForEach(module.visibleEntries) { entry in
                    row(entry)
                }
            }
        }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph(for: entry.content))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 14)
            Text(preview(of: entry.content))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button {
                module.store.togglePin(entry.id)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(entry.isPinned ? 0.9 : 0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { module.copyBack(entry) }
        .contextMenu {
            Button("Copy") { module.copyBack(entry) }
            Button(entry.isPinned ? "Unpin" : "Pin") { module.store.togglePin(entry.id) }
            Divider()
            Button("Remove", role: .destructive) { module.store.remove(entry.id) }
        }
        .help("Click to copy")
    }

    private func glyph(for content: ClipboardContent) -> String {
        switch content {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        }
    }

    private func preview(of content: ClipboardContent) -> String {
        switch content {
        case .text(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        case .url(let value):
            value.absoluteString
        case .image(let data):
            "Image — \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
    }
}
