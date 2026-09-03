import SwiftUI

struct ShortcutsView: View {
    @Bindable var module: ShortcutsModule

    var body: some View {
        VStack(spacing: 4) {
            search
            if module.isListing && module.names.isEmpty {
                loading
            } else if module.visibleNames.isEmpty {
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
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.07)))
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.3))
            Text(module.query.isEmpty ? "No shortcuts found" : "Nothing matches")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                ForEach(module.visibleNames, id: \.self) { name in
                    row(name)
                }
            }
        }
    }

    private func row(_ name: String) -> some View {
        let isRunning = module.runningName == name
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 14)
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            Button {
                module.togglePin(name)
            } label: {
                Image(systemName: module.isPinned(name) ? "pin.fill" : "pin")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(module.isPinned(name) ? 0.9 : 0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.05)))
        .opacity(isRunning ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { module.run(name) }
        .help(isRunning ? "Running…" : "Click to run")
    }
}
