import NotchCore
import SwiftUI

/// A live activity in the collapsed band: symbol on one side of the camera
/// housing, words on the other, and a level bar under the words when the thing
/// being announced has a level.
struct PeekActivityView: View {
    let payload: PeekPayload
    /// Width of the camera housing, kept clear in the middle.
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: payload.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            Spacer(minLength: notchWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let level = payload.level {
                    levelBar(level)
                } else if let detail = payload.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
    }

    private func levelBar(_ level: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.9))
                    .frame(width: max(proxy.size.width * level, level > 0 ? 2 : 0))
            }
        }
        .frame(height: 3)
    }
}
