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
                // Above the black, below everything else. Sized in points rather
                // than to the shape, so the band the housing sits behind only ever
                // shows the top of the gradient — see `panelFillHeight`.
                .overlay(alignment: .top) {
                    panelFill
                        .frame(height: model.panelFillHeight)
                        .allowsHitTesting(false)
                }
                .overlay { rim }
                .overlay(alignment: .top) { content }
                .clipShape(shape)
                // Composited first so the shadow is cast by the finished shape
                // rather than by each layer separately, and applied after the clip
                // so the clip does not cut it away. There is deliberately no outer
                // glow: it read as a halo around the notch rather than as depth.
                .compositingGroup()
                .shadow(
                    color: .black.opacity(model.appearance.shadowOpacity),
                    radius: model.appearance.shadowRadius,
                    y: model.appearance.shadowOffset
                )
                // One animation scope, not two: separate modifiers on `targetSize`
                // and `mode` nest, and the same change then drives both. Keyed
                // on `targetSize` rather than `mode` because the collapsed notch
                // also widens for live content without a mode change, and every
                // mode change that alters the shape alters the size too.
                //
                // `.smooth` rather than a spring: a bouncy curve overshoots the
                // final size, and the shape is anchored to the screen edge, so the
                // overshoot reads as the panel wobbling rather than settling.
                .animation(.smooth(duration: 0.3), value: model.targetSize)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) { dropLayer }
    }

    /// A hairline along the edge, masked so it is completely absent at the top and
    /// reaches full strength further down. The stroke straddles the path and the
    /// outer half is removed by the shell's `clipShape`, leaving an inner bevel.
    /// Flat black until the user picks a tint — see `NotchPanelFill` for why the
    /// top of the panel is never allowed to be anything else.
    private var panelFill: LinearGradient {
        LinearGradient(
            stops: model.panelFillStops.map { stop in
                Gradient.Stop(
                    color: Color(red: stop.tint.red, green: stop.tint.green, blue: stop.tint.blue),
                    location: stop.location
                )
            },
            startPoint: .top,
            endPoint: .bottom
        )
    }

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

    private var leadingTabs: [any NotchModule] {
        let all = model.registry.visibleModules
        return Array(all.prefix((all.count + 1) / 2))
    }

    private var trailingTabs: [any NotchModule] {
        let all = model.registry.visibleModules
        return Array(all.dropFirst((all.count + 1) / 2))
    }

    /// The collapsed silhouette's corners, shared with the drop: it draws its own
    /// copy of the band, and a copy with different corners would show as a seam.
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 10

    private var shape: NotchShape {
        NotchShape(
            topCornerRadius: model.mode.isExpanded ? 10 : Self.closedTopRadius,
            bottomCornerRadius: model.mode.isExpanded ? 22 : Self.closedBottomRadius
        )
    }

    /// Drawn outside the shell's `clipShape`, because the whole point of a drop is
    /// that it leaves the shape. Nothing here is interactive, and it sits outside
    /// `presentedRectInView`, so the gap under the notch keeps falling through to
    /// whatever is behind the panel.
    @ViewBuilder
    private var dropLayer: some View {
        if let payload = model.drop {
            NotchDropView(
                payload: payload,
                // Hangs from whatever the shell is drawing right now, so an
                // announcement that arrives while the panel is open falls out of
                // the panel rather than out of where the band used to be.
                band: model.targetSize,
                topRadius: shape.topCornerRadius,
                bottomRadius: shape.bottomCornerRadius
            )
            // A second announcement while the first is still falling has to start
            // its own drop, not inherit the elapsed time of the one before it.
            .id(payload.id + payload.title)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .closed where model.registry.hasLiveContent:
            peekContent
        case .closed:
            EmptyView()
        case .peek(let payload):
            // A timed announcement — charging, volume, a device connecting. This
            // is not module live content, which shows in `.closed` instead.
            PeekActivityView(payload: payload, notchWidth: model.metrics.rect.width)
                .frame(width: model.peekSize.width, height: model.peekSize.height)
                .transition(.opacity)
        case .open, .pinned:
            expandedContent
        }
    }

    @ViewBuilder
    private var peekContent: some View {
        if let peek = model.registry.peekView {
            peek
                .padding(.horizontal, model.closedFlare + 4)
                // Laid out at the final size from the first frame — see the note
                // on `expandedContent` below; the same reflow-avoidance applies
                // here while the peek band is animating.
                .frame(width: model.peekSize.width, height: model.peekSize.height)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Split around the camera housing rather than crowded onto one
            // flank: a single row runs under the housing as soon as there are
            // more than about four modules, and the space either side of the
            // notch is otherwise wasted.
            HStack(spacing: 0) {
                ModuleTabStrip(registry: model.registry, modules: leadingTabs)
                Spacer(minLength: model.metrics.rect.width + 16)
                ModuleTabStrip(registry: model.registry, modules: trailingTabs)
            }
            .frame(height: model.metrics.rect.height)
            if let module = model.registry.selectedModule {
                module.expandedView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No modules enabled")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        // Laid out at the final size from the first frame. An overlay is
        // proposed its parent's *current* size, so without this the content is
        // squeezed into the collapsed notch, wraps, and unwraps again as the
        // panel grows — which is what made the expansion look like it swam.
        .frame(width: model.openSize.width, height: model.openSize.height)
        .transition(.opacity)
    }
}
