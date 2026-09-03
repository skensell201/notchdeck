import Foundation

/// Parses `shortcuts list` output — one shortcut name per line.
///
/// Names are user data, not a controlled vocabulary: they can contain spaces,
/// quotes, emoji, or anything else the user typed while naming a shortcut in
/// the Shortcuts app. The only things this parser treats as its own — noise
/// from the CLI's line framing rather than part of a name — are blank lines
/// and leading/trailing whitespace. Everything else in a line survives
/// untouched, including a name that happens to duplicate another one; the
/// favourites store, not the parser, decides what to do with duplicates.
public enum ShortcutsListParser {
    public static func parse(_ output: String) -> [String] {
        output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
