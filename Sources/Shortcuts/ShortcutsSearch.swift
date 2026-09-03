import Foundation

/// Case-insensitive search over a list of shortcut names.
public enum ShortcutsSearch {
    public static func filter(_ names: [String], matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
