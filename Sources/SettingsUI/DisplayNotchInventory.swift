import AppKit
import NotchCore
import NotchWindow

/// One attached display, and whether NotchDeck draws its notch or the display
/// brought its own.
public struct DisplayNotch: Equatable, Sendable {
    public var name: String
    public var kind: NotchKind

    public init(name: String, kind: NotchKind) {
        self.name = name
        self.kind = kind
    }
}

@MainActor
public protocol DisplayNotchInventorying: Sendable {
    var displays: [DisplayNotch] { get }
}

public struct SystemDisplayNotchInventory: DisplayNotchInventorying {
    public init() {}

    public var displays: [DisplayNotch] {
        NSScreen.screens.map { screen in
            // The kind never depends on the size we would draw: a display that
            // reports a camera housing is physical whatever the sliders say, and
            // one that reports none is synthetic at every size.
            let kind = NotchResolver.resolve(screen: screen.notchDescription, syntheticSize: .zero).kind
            return DisplayNotch(name: screen.localizedName, kind: kind)
        }
    }
}

/// Says which of the attached displays the synthetic size actually reaches.
///
/// The settings themselves are silent on a Mac whose only display has a real
/// notch — the resolver takes that display's own measurements and never looks at
/// them — and a slider that moves while nothing else does reads as a bug. This
/// turns that silence into a sentence.
enum SyntheticNotchNote {
    static func text(for displays: [DisplayNotch]) -> String? {
        guard !displays.isEmpty else { return nil }
        let synthetic = displays.filter { $0.kind == .synthetic }.map(\.name)
        let physical = displays.filter { $0.kind == .physical }.map(\.name)

        if synthetic.isEmpty {
            return "\(list(physical)) \(own(physical)), so nothing here applies right now."
        }
        if physical.isEmpty {
            return "In use on \(list(synthetic))."
        }
        let ignore = physical.count == 1 ? "ignores" : "ignore"
        return "In use on \(list(synthetic)). \(list(physical)) \(own(physical)) and \(ignore) these numbers."
    }

    private static func own(_ names: [String]) -> String {
        names.count == 1 ? "has a notch of its own" : "have notches of their own"
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names.dropLast().joined(separator: ", ")), and \(names[names.count - 1])"
        }
    }
}
