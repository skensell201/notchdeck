import NotchCore
import SwiftUI

public struct NotchShellView: View {
    private let model: NotchViewModel

    public init(model: NotchViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            shape
                .fill(.black)
                .frame(width: model.targetSize.width, height: model.targetSize.height)
                // The shell's root fills the hosting view, which in turn fills the
                // container view, so `.global` here is the hosting view's own
                // top-left-origin space — exactly what the container hit-tests in.
                // Measured before the bloom, because shadows must not enlarge the
                // area that swallows clicks.
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    model.presentedRectInView = frame
                }
                .overlay { rim }
                .overlay(alignment: .top) { content }
                .clipShape(shape)
                // Composited first so both shadows are cast by the finished shape
                // rather than by each layer separately, and applied after the clip
                // so the clip does not cut them away.
                .compositingGroup()
                .shadow(
                    color: .black.opacity(model.appearance.shadowOpacity),
                    radius: model.appearance.shadowRadius,
                    y: model.appearance.glowOffset
                )
                .shadow(
                    color: .white.opacity(model.appearance.glowOpacity),
                    radius: model.appearance.glowRadius,
                    y: model.appearance.glowOffset
                )
                // One animation scope, not two: separate modifiers on `targetSize`
                // and `mode` nest, and the same change then drives both.
                //
                // `.smooth` rather than a spring: a bouncy curve overshoots the
                // final size, and the shape is anchored to the screen edge, so the
                // overshoot reads as the panel wobbling rather than settling.
                .animation(.smooth(duration: 0.3), value: model.mode)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A hairline along the edge, masked so it is completely absent at the top and
    /// reaches full strength further down. The stroke straddles the path and the
    /// outer half is removed by the shell's `clipShape`, leaving an inner bevel.
    private var rim: some View {
        shape
            .stroke(.white, lineWidth: model.appearance.rimWidth)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: model.appearance.rimFadeEnd)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(model.appearance.rimOpacity)
            .blendMode(.plusLighter)
    }

    private var shape: NotchShape {
        NotchShape(
            topCornerRadius: model.mode.isExpanded ? 10 : 6,
            bottomCornerRadius: model.mode.isExpanded ? 22 : 10
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .closed:
            EmptyView()
        case .peek(let payload):
            Text(payload.id)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, model.closedFlare + 4)
                .frame(width: model.peekSize.width, height: model.peekSize.height)
                .transition(.opacity)
        case .open, .pinned:
            VStack(spacing: 8) {
                Text("NotchDeck")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.mode == .pinned ? "Pinned — click outside to close" : "Move away to close")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, model.metrics.rect.height)
            // Laid out at the final size from the first frame. An overlay is
            // proposed its parent's *current* size, so without this the text is
            // squeezed into the collapsed notch, wraps, and unwraps again as the
            // panel grows — which is what made the expansion look like it swam.
            .frame(width: model.openSize.width, height: model.openSize.height)
            .transition(.opacity)
        }
    }
}
