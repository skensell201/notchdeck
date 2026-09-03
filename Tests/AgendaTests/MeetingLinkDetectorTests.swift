import Foundation
import Testing
@testable import Agenda

@Suite("Meeting link detection")
struct MeetingLinkDetectorTests {
    private func event(
        url: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) -> AgendaEvent {
        AgendaEvent(
            id: "event",
            title: "Weekly sync",
            start: Date(timeIntervalSinceReferenceDate: 0),
            end: Date(timeIntervalSinceReferenceDate: 1800),
            location: location,
            notes: notes,
            url: url.flatMap(URL.init(string:))
        )
    }

    // MARK: Providers

    @Test(
        "each provider is recognised by its host",
        arguments: [
            ("https://us02web.zoom.us/j/8412345678?pwd=Zm9v", MeetingLink.Provider.zoom),
            ("https://zoom.us/j/8412345678", .zoom),
            ("https://agency.zoomgov.com/j/1600123456", .zoom),
            ("https://meet.google.com/abc-defg-hij", .googleMeet),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC/0", .teams),
            ("https://teams.live.com/meet/9312345678901", .teams),
            ("https://acme.webex.com/acme/j.php?MTID=m1234", .webex),
            ("https://webex.com/meet/ada", .webex)
        ]
    )
    func providersAreRecognised(link: String, expected: MeetingLink.Provider) {
        let found = MeetingLinkDetector.firstLink(in: event(url: link))

        #expect(found?.provider == expected)
        #expect(found?.url.absoluteString == link)
    }

    // MARK: False positives

    @Test(
        "prose is never a meeting link",
        arguments: [
            "Let's zoom in on the Q3 numbers before we decide.",
            "Zoom call to be scheduled — Bob will send the link.",
            "We'll meet in the kitchen.",
            "Ask the teams to send their updates.",
            "Bring a webex headset."
        ]
    )
    func proseIsNotALink(text: String) {
        // A button that opened a web search for the word "zoom" would be worse
        // than no button, so recognition is by host and never by the word.
        #expect(MeetingLinkDetector.firstLink(in: event(notes: text)) == nil)
    }

    @Test(
        "a host that merely ends in a provider's name is not that provider",
        arguments: ["https://notzoom.us/j/123", "https://fakewebex.com/meet/ada", "https://meet.google.com.evil.example/x"]
    )
    func lookalikeHostsAreRejected(link: String) {
        #expect(MeetingLinkDetector.firstLink(in: event(url: link)) == nil)
    }

    @Test("a bare host with no room in it is a mention, not a meeting")
    func bareHostIsRejected() {
        #expect(MeetingLinkDetector.firstLink(in: event(notes: "Details on zoom.us later")) == nil)
        #expect(MeetingLinkDetector.firstLink(in: event(notes: "Write to ada@zoom.us")) == nil)
    }

    @Test("an event with no link anywhere yields nothing")
    func noLink() {
        #expect(MeetingLinkDetector.firstLink(in: event()) == nil)
        #expect(
            MeetingLinkDetector.firstLink(
                in: event(url: "https://wiki.example.com/agenda", location: "Room 4", notes: "Bring the deck")
            ) == nil
        )
    }

    // MARK: Field priority

    @Test("the structured url field wins over a link buried in the notes")
    func urlFieldWins() {
        // Notes accumulate: last week's link, a dial-in, a wiki page. The `url`
        // field is the one the invitation actually set.
        let found = MeetingLinkDetector.firstLink(
            in: event(
                url: "https://meet.google.com/current-room",
                notes: "Old room: https://us02web.zoom.us/j/111 — do not use"
            )
        )

        #expect(found?.url.absoluteString == "https://meet.google.com/current-room")
    }

    @Test("location beats notes when the url field is empty")
    func locationBeatsNotes() {
        let found = MeetingLinkDetector.firstLink(
            in: event(
                location: "https://acme.webex.com/acme/j.php?MTID=m99",
                notes: "Agenda: https://us02web.zoom.us/j/111"
            )
        )

        #expect(found?.provider == .webex)
    }

    @Test("notes are read when nothing better is offered")
    func notesAreTheLastResort() {
        let found = MeetingLinkDetector.firstLink(
            in: event(
                location: "Conference room B",
                notes: "Dial in or join at https://teams.microsoft.com/l/meetup-join/19%3aabc/0 if remote."
            )
        )

        #expect(found?.provider == .teams)
    }

    // MARK: Text handling

    @Test("a link at the end of a sentence keeps its path and loses the full stop")
    func trailingPunctuationIsTrimmed() {
        let found = MeetingLinkDetector.firstLink(
            in: event(notes: "Join at https://meet.google.com/abc-defg-hij.")
        )

        #expect(found?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("a link wrapped in angle brackets is still a link")
    func bracketedLink() {
        let found = MeetingLinkDetector.firstLink(
            in: event(notes: "Room: <https://us02web.zoom.us/j/8412345678>")
        )

        #expect(found?.provider == .zoom)
    }

    @Test("a scheme-less link pasted into notes is still joinable")
    func schemeLessLink() {
        // Invitations paste them this way, and a human would click it.
        let found = MeetingLinkDetector.firstLink(in: event(notes: "meet.google.com/abc-defg-hij"))

        #expect(found?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("the first joinable link in a block of notes wins")
    func firstLinkInNotesWins() {
        let found = MeetingLinkDetector.firstLink(
            in: event(
                notes: """
                Agenda: https://wiki.example.com/agenda
                Join: https://us02web.zoom.us/j/8412345678
                Backup: https://meet.google.com/abc-defg-hij
                """
            )
        )

        #expect(found?.url.absoluteString == "https://us02web.zoom.us/j/8412345678")
    }

    @Test("host matching ignores case")
    func caseInsensitiveHost() {
        #expect(MeetingLinkDetector.firstLink(in: event(url: "https://US02WEB.ZOOM.US/j/84"))?.provider == .zoom)
    }
}
