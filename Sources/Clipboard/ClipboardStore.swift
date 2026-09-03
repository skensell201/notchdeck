import Foundation
import Observation
import Support

/// The clipboard history and every rule about what may enter it.
///
/// The rules are the point: a password manager's copy, a transient scratch copy,
/// and anything from an app the user excluded must never reach the history, and
/// images must never reach the disk.
@MainActor
@Observable
public final class ClipboardStore {
    public private(set) var entries: [ClipboardEntry] = []

    private let persistence: any ClipboardPersisting
    private let capacity: Int
    private let excluded: Set<String>
    private let logger = Log.make("clipboard")

    public init(
        persistence: any ClipboardPersisting,
        capacity: Int = 60,
        excludedBundleIdentifiers: Set<String> = []
    ) {
        self.persistence = persistence
        self.capacity = capacity
        self.excluded = excludedBundleIdentifiers
    }

    public func load() {
        do {
            entries = try persistence.load()
        } catch {
            logger.error("could not load the clipboard history: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    /// Records a pasteboard change. Returns whether it was kept.
    @discardableResult
    public func record(_ candidate: ClipboardCandidate) -> Bool {
        guard !candidate.isConcealed, !candidate.isTransient else { return false }
        if let source = candidate.sourceBundleIdentifier, excluded.contains(source) { return false }
        guard !isBlank(candidate.content) else { return false }

        let fingerprint = candidate.content.fingerprint
        if let existing = entries.firstIndex(where: { $0.content.fingerprint == fingerprint }) {
            var entry = entries.remove(at: existing)
            entry.copiedAt = Date()
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                ClipboardEntry(content: candidate.content, sourceBundleIdentifier: candidate.sourceBundleIdentifier),
                at: 0
            )
            evictIfNeeded()
        }
        save()
        return true
    }

    public func togglePin(_ id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        save()
    }

    public func remove(_ id: ClipboardEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Drops everything the user did not explicitly pin — pinning is how they say
    /// "keep this", so clearing must respect it.
    public func clear() {
        entries.removeAll { !$0.isPinned }
        save()
    }

    public func entries(matching query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.content.searchableText.localizedCaseInsensitiveContains(trimmed) }
    }

    private func isBlank(_ content: ClipboardContent) -> Bool {
        switch content {
        case .text(let value): value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url, .image: false
        }
    }

    private func evictIfNeeded() {
        guard entries.count > capacity else { return }
        // Evict the oldest unpinned entry, never a pinned one; if everything is
        // pinned the history is allowed to exceed the cap rather than discard
        // something the user asked to keep.
        while entries.count > capacity, let victim = entries.lastIndex(where: { !$0.isPinned }) {
            entries.remove(at: victim)
        }
    }

    private func save() {
        do {
            try persistence.save(entries.filter { $0.content.isPersistable })
        } catch {
            logger.error("could not save the clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
