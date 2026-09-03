import SwiftUI

struct MediaPeekView: View {
    let state: NowPlaying
    /// Decoded by the module once per distinct image; nil shows a placeholder.
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            artworkView
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Spacer(minLength: 0)
            Visualiser(isAnimating: state.isPlaying)
                .frame(width: 18, height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.15))
        }
    }
}

/// Three bars that breathe while a track plays and rest flat when it is paused.
private struct Visualiser: View {
    let isAnimating: Bool
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 3, height: height(index))
            }
        }
        // The repeating curve must apply only while playing: applied to the
        // 1 → 0 change as well, it would keep the bars bouncing between the
        // two heights forever instead of settling flat on pause.
        .animation(
            isAnimating
                ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.2),
            value: phase
        )
        .onAppear { phase = isAnimating ? 1 : 0 }
        .onChange(of: isAnimating) { _, playing in phase = playing ? 1 : 0 }
    }

    private func height(_ index: Int) -> CGFloat {
        guard phase > 0 else { return 3 }
        return [10.0, 6.0, 12.0][index]
    }
}
