/// A module's stable identity. It is persisted, so it must not change when a
/// module is renamed in the UI.
public struct ModuleID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
