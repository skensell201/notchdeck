import SwiftUI

struct TimerView: View {
    // A plain reference is enough: the module is `@Observable`, so reads in
    // `body` are tracked and the buttons mutate it directly.
    let module: TimerModule

    var body: some View {
        // Read so the module's once-a-second tick redraws the countdown and ring;
        // both are derived from a clock the view cannot observe.
        let _ = module.tick
        HStack(spacing: 18) {
            ring
            details
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let ringSide: CGFloat = 76
    private static let ringWidth: CGFloat = 6

    /// The phase's progress, drawn once around the glyph that names the phase.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: module.progress)
                .stroke(
                    .white.opacity(0.85),
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                // Starts at the top rather than at three o'clock, where a clock
                // face starts.
                .rotationEffect(.degrees(-90))
            Image(systemName: module.machine.phase.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: Self.ringSide, height: Self.ringSide)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(module.machine.phase.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            Text(module.countdownText)
                .font(.system(size: 32, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.top, 1)
            controls
                .padding(.top, 5)
        }
    }

    /// Where the user is in the cycle, so the long break is not a surprise.
    private var subtitle: String {
        let machine = module.machine
        let total = machine.configuration.workPhasesPerCycle
        let position = switch machine.phase {
        case .work: "Session \(machine.workPhaseNumber) of \(total)"
        case .shortBreak: "\(machine.completedWorkPhases) of \(total) done"
        case .longBreak: "Cycle complete"
        }
        return machine.isPaused ? "\(position) · Paused" : position
    }

    private var controls: some View {
        HStack(spacing: 18) {
            button(module.machine.isRunning ? "pause.fill" : "play.fill", "Start or pause") {
                module.toggle()
            }
            button("forward.end.fill", "Skip to the next phase") { module.skip() }
            button("arrow.counterclockwise", "Start the cycle over") { module.reset() }
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
