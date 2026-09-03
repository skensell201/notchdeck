import AppKit
import SwiftUI

/// One column per day across the panel.
///
/// The panel gives a module roughly 592 × 105 points — wide and short — so days
/// run across and events run down inside them. A vertical list of the same
/// events would show three rows and hide the day boundaries that make the list
/// readable.
struct AgendaView: View {
    // A plain reference is enough: the module is `@Observable`, so reads in
    // `body` are tracked.
    let module: AgendaModule

    var body: some View {
        if module.days.isEmpty {
            empty
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(module.days) { day in
                    column(day)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing scheduled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("The next few days are clear.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: A day

    private func column(_ day: AgendaDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    // All-day events first: they frame the day rather than sit at
                    // a point in it, so they read as a banner above the schedule.
                    ForEach(day.allDay) { event in
                        allDayRow(event)
                    }
                    ForEach(day.timed) { event in
                        timedRow(event)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allDayRow(_ event: AgendaEvent) -> some View {
        HStack(spacing: 5) {
            colorBar(event)
            Text(event.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text("All day")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // A filled plate, where a timed row has none: the difference has to be
        // visible at a glance, and an event with no time cannot show one.
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.1)))
    }

    private func timedRow(_ event: AgendaEvent) -> some View {
        let timing = module.timing(of: event)
        return HStack(spacing: 5) {
            colorBar(event)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(module.time(of: event.start))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                    Text(timing.text)
                        .font(.system(size: 10))
                        .foregroundStyle(timing.phase == .inProgress ? .white.opacity(0.9) : .white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if let link = MeetingLinkDetector.firstLink(in: event) {
                joinButton(link)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // A finished meeting stays in place — the morning is context — but it
        // recedes, so the eye lands on what has not happened yet.
        .opacity(timing.phase == .ended ? 0.45 : 1)
    }

    /// The owning calendar's colour, so several calendars are told apart without
    /// a legend. A calendar with no colour gets a neutral bar rather than none,
    /// which would leave its rows a couple of points out of line with the rest.
    private func colorBar(_ event: AgendaEvent) -> some View {
        Capsule()
            .fill(color(of: event))
            .frame(width: 2.5, height: 20)
    }

    private func color(of event: AgendaEvent) -> Color {
        guard let color = event.calendarColor else { return .white.opacity(0.35) }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func joinButton(_ link: MeetingLink) -> some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "video.fill")
                    .font(.system(size: 8))
                Text("Join")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help("Join the \(link.provider.name) meeting")
    }
}
