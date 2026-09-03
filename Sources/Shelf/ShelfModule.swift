import NotchCore
import NotchUI
import Observation
import SwiftUI

@MainActor
@Observable
public final class ShelfModule: NotchModule {
    public static let id = ModuleID("shelf")
    public let title = "Shelf"
    public let symbolName = "tray.full"

    public private(set) var droppedNames: [String] = []

    public init() {}

    public func activate() {}
    public func deactivate() {}
    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }

    public func expandedView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                if droppedNames.isEmpty {
                    Text("Drop files here")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(droppedNames, id: \.self) { name in
                        Text(name).font(.system(size: 11)).foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
        )
    }

    public func accept(_ urls: [URL]) -> Bool {
        droppedNames.append(contentsOf: urls.map(\.lastPathComponent))
        return true
    }
}
