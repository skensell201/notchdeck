import SwiftUI

struct AirDropZone: View {
    let module: ShelfModule

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "shareplay")
                .font(.system(size: 16))
            Text("AirDrop")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.white.opacity(module.isAirDropTargeted ? 1 : 0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    .white.opacity(module.isAirDropTargeted ? 0.8 : 0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { module.airDropAll() }
        // Published in the hosting view's space, which is the space the container
        // reports drop locations in — so the module can compare them directly.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            module.airDropZoneRect = $0
        }
        .help("Drop files here to AirDrop them, or click to send the whole shelf")
    }
}
