import SwiftUI

/// The countdown in the collapsed notch. The band is only as tall as the physical
/// notch and the camera housing sits in the middle of it, so the two pieces are
/// pushed to the ends rather than centred, exactly as the media peek does.
struct TimerPeekView: View {
    let module: TimerModule

    var body: some View {
        // Read so the module's tick redraws the countdown while the notch is
        // closed — the shell only rebuilds this view when live content appears
        // or goes away.
        let _ = module.tick
        HStack(spacing: 0) {
            Image(systemName: module.machine.phase.symbolName)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            Text(module.countdownText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        // A held countdown is dimmed rather than hidden: the time left is still
        // owed to the user, but it must not look like it is still counting.
        .foregroundStyle(.white.opacity(module.machine.isRunning ? 0.9 : 0.45))
        .frame(maxWidth: .infinity)
    }
}
