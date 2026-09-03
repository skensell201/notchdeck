import SwiftUI

struct MediaPlayerView: View {
    // A plain reference is enough: the module is `@Observable`, so reads in
    // `body` are tracked, and the gesture closures mutate it directly.
    let module: MediaModule

    var body: some View {
        if module.isDegraded && module.state == nil {
            unavailable
        } else if let state = module.state {
            player(state)
        } else {
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            Text("Now playing is unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text("Playback controls still work.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            transport
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func player(_ state: NowPlaying) -> some View {
        HStack(spacing: 14) {
            artwork
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist ?? state.album ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                scrubber

                transport
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = module.artworkImage {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.3)))
        }
    }

    @ViewBuilder
    private var scrubber: some View {
        if let progress = module.progress {
            // `positionTick` is read so the once-a-second tick redraws the bar.
            let _ = module.positionTick
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            module.scrubbingProgress = min(max(value.location.x / proxy.size.width, 0), 1)
                        }
                        .onEnded { value in
                            module.seek(toProgress: min(max(value.location.x / proxy.size.width, 0), 1))
                        }
                )
            }
            .frame(height: 4)
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            button("backward.fill") { module.perform(.previous) }
            button(module.state?.isPlaying == true ? "pause.fill" : "play.fill") { module.perform(.toggle) }
            button("forward.fill") { module.perform(.next) }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
    }
}
