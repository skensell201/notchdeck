import Testing
@testable import Shortcuts

@Suite("Shortcuts list parser")
struct ShortcutsListParserTests {
    @Test("completely empty output parses to no shortcuts")
    func emptyOutput() {
        #expect(ShortcutsListParser.parse("") == [])
    }

    @Test("blank lines between names are dropped")
    func blankLines() {
        let output = "One\n\n\nTwo\n"
        #expect(ShortcutsListParser.parse(output) == ["One", "Two"])
    }

    @Test("trailing whitespace on a line is trimmed")
    func trailingWhitespace() {
        let output = "One  \nTwo\t\n"
        #expect(ShortcutsListParser.parse(output) == ["One", "Two"])
    }

    @Test("a name containing spaces is kept whole")
    func nameWithSpaces() {
        let output = "Good Morning Routine\n"
        #expect(ShortcutsListParser.parse(output) == ["Good Morning Routine"])
    }

    @Test("a name containing a quote is kept as-is")
    func nameWithQuote() {
        let output = "Say \"Hello\"\n"
        #expect(ShortcutsListParser.parse(output) == ["Say \"Hello\""])
    }

    @Test("a name containing an emoji is kept as-is")
    func nameWithEmoji() {
        let output = "🎉 Party Mode\n"
        #expect(ShortcutsListParser.parse(output) == ["🎉 Party Mode"])
    }

    @Test("duplicate names are preserved, not deduplicated")
    func duplicateNames() {
        let output = "Focus\nFocus\n"
        #expect(ShortcutsListParser.parse(output) == ["Focus", "Focus"])
    }

    @Test("output with no trailing newline still parses its last line")
    func noTrailingNewline() {
        let output = "One\nTwo"
        #expect(ShortcutsListParser.parse(output) == ["One", "Two"])
    }

    @Test("output that is only whitespace parses to no shortcuts")
    func whitespaceOnlyOutput() {
        #expect(ShortcutsListParser.parse("   \n\t\n") == [])
    }
}
