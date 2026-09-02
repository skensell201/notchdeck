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
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    model.presentedRectInView = frame
                }
                .overlay(alignment: .top) { content }
                .clipShape(shape)
                .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.targetSize)
                .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.mode)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                .frame(maxHeight: .infinity)
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
            .transition(.opacity)
        }
    }
}
