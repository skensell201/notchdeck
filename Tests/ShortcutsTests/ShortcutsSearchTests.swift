import Testing
@testable import Shortcuts

@Suite("Shortcuts search")
struct ShortcutsSearchTests {
    private let names = ["Good Morning", "good night owl", "Focus Mode", "🎉 Party"]

    @Test("an empty query returns everything, unfiltered")
    func emptyQueryReturnsAll() {
        #expect(ShortcutsSearch.filter(names, matching: "") == names)
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        #expect(ShortcutsSearch.filter(names, matching: "GOOD") == ["Good Morning", "good night owl"])
    }

    @Test("a query with no matches returns an empty list")
    func noMatches() {
        #expect(ShortcutsSearch.filter(names, matching: "zzz") == [])
    }

    @Test("a query matches anywhere in the name, not only the start")
    func matchesMidName() {
        #expect(ShortcutsSearch.filter(names, matching: "mode") == ["Focus Mode"])
    }

    @Test("whitespace-only queries behave like an empty query")
    func whitespaceOnlyQuery() {
        #expect(ShortcutsSearch.filter(names, matching: "   ") == names)
    }
}
