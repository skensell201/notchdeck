import EventKit
import Foundation
import NotchUI
import Support

/// The real `EventSourcing`: one `EKEventStore`, read-only.
///
/// Constructing the store does not prompt and does not need access — only
/// `requestAccess()` prompts — so the module can hold one from launch and still
/// show its permission empty state without ever touching TCC.
@MainActor
public final class EventKitSource: EventSourcing {
    private let store = EKEventStore()
    private let logger = Log.make("agenda")
    private var observer: (any NSObjectProtocol)?

    public init() {}

    public var authorizationStatus: PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .fullAccess:
            .granted
        // Write-only is a grant, but not one this module can use: it may add
        // events and may not read them, which is exactly what it needs to do.
        case .denied, .restricted, .writeOnly:
            .blocked
        @unknown default:
            .blocked
        }
    }

    public func requestAccess() async -> PermissionStatus {
        // The completion-handler form rather than the `async` one: the store is
        // main-actor state here, and handing it to a nonisolated async call would
        // send it out of its region for no gain.
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { _, error in
                if let error {
                    // Not fatal: the status read below is the real answer, and a
                    // user who declined is not an error worth shouting about.
                    Log.make("agenda").notice(
                        "calendar access request returned an error: \(error.localizedDescription, privacy: .public)"
                    )
                }
                continuation.resume()
            }
        }
        return authorizationStatus
    }

    public func events(in interval: DateInterval) -> [AgendaEvent] {
        // Without access this returns nothing rather than failing, so the caller's
        // status check — not this method — is what puts the empty state on screen.
        guard authorizationStatus == .granted else { return [] }
        let predicate = store.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        return store.events(matching: predicate).compactMap(Self.event(from:))
    }

    public func startObserving(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        stopObserving()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            // Hopped rather than assumed: the notification is delivered on the
            // main *thread*, which is not the same promise as main-actor
            // isolation, and this costs one turn.
            Task { @MainActor in onChange() }
        }
    }

    public func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    // MARK: Mapping

    private static func event(from event: EKEvent) -> AgendaEvent? {
        // EventKit permits both to be nil on a malformed event; a row with no
        // time is worse than no row.
        guard let start = event.startDate, let end = event.endDate else { return nil }
        return AgendaEvent(
            // A recurring event repeats its identifier for every occurrence, so
            // the start disambiguates them; without it a `ForEach` over two
            // occurrences of the same standup collapses to one row.
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(start.timeIntervalSinceReferenceDate)",
            title: event.title ?? "Untitled",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarColor: event.calendar.flatMap { EventColor(cgColor: $0.cgColor) },
            location: event.location,
            notes: event.notes,
            url: event.url
        )
    }
}

private extension EventColor {
    /// Calendar colours arrive as `CGColor` in whatever space the calendar was
    /// created with; converting to sRGB keeps the dot the colour the user picked.
    init?(cgColor: CGColor?) {
        guard
            let cgColor,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
            let components = converted.components,
            components.count >= 3
        else { return nil }
        self.init(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2])
        )
    }
}
