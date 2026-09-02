import NotchCore
import SwiftUI

public struct NotchShellView: View {
    @Bindable private var model: NotchViewModel

    public init(model: NotchViewModel) {
        self._model = Bindable(model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            NotchShape(
                topCornerRadius: model.isExpandedMode ? 10 : 6,
                bottomCornerRadius: model.isExpandedMode ? 22 : 10
            )
            .fill(.black)
            .frame(width: model.targetSize.width, height: model.targetSize.height)
            .overlay(alignment: .center) { content }
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.targetSize)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

extension NotchViewModel {
    var isExpandedMode: Bool {
        switch mode {
        case .open, .pinned: true
        case .closed, .peek: false
        }
    }
}
