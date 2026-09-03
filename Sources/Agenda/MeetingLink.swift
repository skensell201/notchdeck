import Foundation

/// A joinable meeting URL found on an event.
public struct MeetingLink: Hashable, Sendable {
    public enum Provider: String, Hashable, Sendable {
        case zoom
        case googleMeet
        case teams
        case webex

        public var name: String {
            switch self {
            case .zoom: "Zoom"
            case .googleMeet: "Google Meet"
            case .teams: "Teams"
            case .webex: "Webex"
            }
        }
    }

    public let provider: Provider
    public let url: URL

    public init(provider: Provider, url: URL) {
        self.provider = provider
        self.url = url
    }
}

/// Finds the one link worth putting a Join button on.
///
/// Invitations bury the URL somewhere different in every calendar system, so all
/// three fields are searched. Recognition is by *host*, never by the word: an
/// agenda line reading "zoom in on the Q3 numbers" is prose, and a button that
/// opened a search for it would be worse than no button.
public enum MeetingLinkDetector {
    /// The structured `url` field first, then `location`, then `notes`.
    ///
    /// The order is the order of confidence. Google Calendar and Outlook both put
    /// the real conference link in `url` or `location`; `notes` is the field that
    /// also contains last week's link, a dial-in, and a wiki page, so it is
    /// consulted only when nothing better exists.
    public static func firstLink(in event: AgendaEvent) -> MeetingLink? {
        if let url = event.url, let link = link(from: url) { return link }
        if let location = event.location, let link = firstLink(in: location) { return link }
        if let notes = event.notes, let link = firstLink(in: notes) { return link }
        return nil
    }

    /// The first joinable URL in a block of free text.
    public static func firstLink(in text: String) -> MeetingLink? {
        for token in tokens(in: text) {
            // A scheme-less "meet.google.com/abc-defg-hij" is a link a human
            // would click, and invitations do paste them that way.
            let candidate = token.contains("://") ? token : "https://\(token)"
            guard let url = URL(string: candidate), let link = link(from: url) else { continue }
            return link
        }
        return nil
    }

    static func link(from url: URL) -> MeetingLink? {
        guard let host = url.host()?.lowercased(), let provider = provider(forHost: host) else { return nil }
        // A bare host is a mention, not a meeting: every provider puts the room in
        // the path, so "see zoom.us for details" and "bob@zoom.us" are excluded
        // by the same rule.
        guard url.path().count > 1 else { return nil }
        return MeetingLink(provider: provider, url: url)
    }

    static func provider(forHost host: String) -> MeetingLink.Provider? {
        // Suffix matching, not `contains`: every provider hands out per-tenant
        // subdomains (`us02web.zoom.us`, `acme.webex.com`), while a lookalike
        // such as "notzoom.us" must not match.
        if matches(host, "zoom.us") || matches(host, "zoomgov.com") { return .zoom }
        if matches(host, "meet.google.com") { return .googleMeet }
        if matches(host, "teams.microsoft.com") || matches(host, "teams.live.com") { return .teams }
        if matches(host, "webex.com") { return .webex }
        return nil
    }

    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    /// Splits text the way a mail client does when it linkifies: on whitespace and
    /// on the punctuation that wraps URLs but is never part of one.
    private static func tokens(in text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || "<>\"'“”()[]{},;".contains($0) })
            // Trailing sentence punctuation belongs to the sentence, not the URL.
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")) }
            .filter { !$0.isEmpty }
    }
}
